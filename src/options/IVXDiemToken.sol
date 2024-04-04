pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {Math} from "../libraries/math/Math.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC1155Supply, ERC1155} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IIVXDiemToken} from "../interface/options/IIVXDiemToken.sol";
import {IVXPricer} from "../libraries/IVXPricer.sol";
import {IIVXOracle} from "../interface/periphery/IIVXOracle.sol";
import {IIVXLP} from "../interface/liquidity/IIVXLP.sol";
import {IIVXRiskEngine} from "../interface/margin/IIVXRiskEngine.sol";
import {IIVXQueue} from "../interface/liquidity/IIVXQueue.sol";

contract IVXDiemToken is ERC1155Supply, IIVXDiemToken, Ownable {
    using FixedPointMathLib for uint256;

    /// @dev Maps the optionId to the attributes of the option
    mapping(uint256 id => OptionAttributes) private optionIDAttributes;

    /// @dev Array of all the active expiries timestamps
    mapping(address asset => uint256[] optionIds) private underlying_ActiveOptions;

    mapping(address asset => MAKER_TAKER_FACTORS) private MakerTakerFactors;

    /// @dev The counter for options, gives the number of options previously configured
    uint256 public currentOptionId;

    OptionTradingParams optionTradingParams;

    ///@dev traded assets in underlyings
    address[] public underlyings;

    /// @dev The address of the IVXDiem contract
    address private diem;
    bool initialized;

    /// @dev The address of the oracle contract which fetches volatilities and prices
    IIVXOracle private Oracle;
    IIVXRiskEngine private RiskEngine;

    IIVXLP private LP;

    modifier onlyDiem() {
        if (msg.sender != diem) {
            revert OnlyIVXDiem();
        }
        _;
    }

    modifier idModule(uint256 id) {
        if (id % 4 != 0) {
            revert OnlyUseLastIdCreatedOfThisOptionGroups();
        }
        _;
    }

    constructor() ERC1155("") {}

    function initialize(address _RiskEngine, address _lp, address _Oracle, address _diem) external onlyOwner {
        if (initialized != false) {
            revert AlreadyInitialized();
        }
        if (address(_Oracle) == address(0)) revert AddressZero();
        if (_diem == address(0)) revert AddressZero();

        diem = _diem;
        Oracle = IIVXOracle(_Oracle);
        LP = IIVXLP(_lp);
        RiskEngine = IIVXRiskEngine(_RiskEngine);
        initialized = true;
    }

    function setParams(OptionTradingParams calldata _params) external onlyOwner {
        if (_params.binomialCutoff >= _params.blackScholesCutoff) revert BinomialCutoffMustBeSmallerThanBsCutoff();
        optionTradingParams = _params;
    }

    function setUnderlyingMakerTakerFactors(
        address _asset,
        MAKER_TAKER_FACTORS calldata _makerTakerFactors
    ) external onlyOwner {
        MakerTakerFactors[_asset] = _makerTakerFactors;
    }

    /// @dev Creates a new option with given metadata
    /// @param _option The insides of the option
    /// @notice .strikePrice: The strike price of the option
    /// @notice .underlyingAsset: The address of the underlying asset
    /// @notice .expiry: The expiry of the option
    /// @notice creates 4 options ids, where the 1st is Buy Call, 2nd is Sell Call, 3rd is Buy Put, 4th is Sell Put
    /// @notice only the 4th id is pushed to the active options array as pushing the other ones would be redundant
    function createOption(Option calldata _option) external onlyOwner returns (uint256 id) {
        //check if optionTradingParams set
        if (
            optionTradingParams.binomialCutoff == 0 || optionTradingParams.blackScholesCutoff == 0
                || optionTradingParams.expiryBuffer == 0 || optionTradingParams.deltaCutoff == 0
        ) {
            revert OptionTradingParamsNotSet();
        }

        //check if asset maker taker params are set
        //IIVXRiskEngine.AssetAttributes memory assetAttributes = RiskEngine.getAssetAttributes(_asset)
        if (MakerTakerFactors[_option.underlyingAsset].DELTA_MAKER_FACTOR == 0)
            revert AssetMakerTakerParamsNotSet();

        //if option expiry bigger than the lp queue next epoch, dont allow creation
        if (_option.expiry > IIVXQueue(LP.queueContract()).nextEpochStartTimestamp())
            revert CannotCreateOptionWithExpiryAfterNextEpoch();

        //revert if oracle not set
        Oracle.checkAssetStrikeSupported(_option.underlyingAsset, _option.strikePrice);

        //revert if option asset shockloss factors not set
        (uint256 _ivFactor, uint256 priceFactor) = RiskEngine.getShockLossFactors(_option.underlyingAsset);
        if (_ivFactor == 0 || priceFactor == 0) 
            revert AssetShockLossFactorsNotSet();
        

        // Set the option as available
        for (uint256 i = 0; i <= 3; ++i) {
            // Increment the counter for the next option ID
            currentOptionId++;
            // Store the option attributes at the current option ID
            optionIDAttributes[currentOptionId] = OptionAttributes({
                option: _option,
                isCall: (i < 2),
                isBuy: (i % 2 == 0),
                status: OptionStatus({isSettled: false, settlementPayoff: 0})
            });
        }

        // Add the id to the array
        underlying_ActiveOptions[_option.underlyingAsset].push(currentOptionId);

        //loop underlyings array check if already exists if not add
        bool found = false;
        uint256 arraylength = underlyings.length;
        for (uint256 i; i < arraylength; ++i) {
            if (underlyings[i] == _option.underlyingAsset) {
                found = true;
                break;
            } else {
                found = false;
            }
        }
        if (!found) {
            underlyings.push(_option.underlyingAsset);
        }

        emit OptionCreated(currentOptionId, _option.strikePrice, _option.underlyingAsset, _option.expiry);

        // Return the previous option counter, where the requested option is indexed
        return currentOptionId;
    }

    /// @dev closes an optionID if expired, for all users trading it, and settles it
    /// @param _optionID The optionID to close
    function settleOptionsExpired(uint256 _optionID) external idModule(_optionID) {
        //check if expired
        if (optionIDAttributes[_optionID].option.expiry > block.timestamp) {
            revert IVXOptionIsStillTradeable(_optionID);
        }

        OptionAttributes memory attributes;
        for (uint256 i; i < 4; ++i) {
            uint256 id = _optionID - i;

            //get attributes
            attributes = optionIDAttributes[id];

            //set status
            attributes.status.isSettled = true;
            attributes.status.settlementPayoff = _settledPayoff(attributes);
            optionIDAttributes[id] = attributes;
        }

        uint256[] memory activeIds = underlying_ActiveOptions[attributes.option.underlyingAsset];

        //reset delta exposure
        //remove from activeExpireTimes if no more options for that expiry
        uint256 arraylength = activeIds.length;
        for (uint256 i; i < arraylength; ++i) {
            if (activeIds[i] == _optionID) {
                if (arraylength == 1) {
                    delete underlying_ActiveOptions[
                        attributes.option.underlyingAsset
                    ];
                } else {
                    activeIds[i] = activeIds[arraylength - 1];
                    underlying_ActiveOptions[attributes.option.underlyingAsset] = activeIds;
                    underlying_ActiveOptions[attributes.option.underlyingAsset].pop();
                }
            }
        }

        emit OptionSettled(_optionID, attributes.status.settlementPayoff);
    }

    function isTradeable(uint256 _optionID) public view {
        OptionAttributes memory attributes = optionIDAttributes[_optionID];
        if(attributes.option.expiry == 0) revert IVXOptionIdNotFound(_optionID);
        if (attributes.option.expiry <= block.timestamp) revert IVXOptionExpired(_optionID);
        if (attributes.status.isSettled == true) revert IVXOption_isSettled(_optionID);

        uint256 timeToExpiry = attributes.option.expiry - block.timestamp;

        // Catches the scenario where the expiry is in the past also
        if (timeToExpiry < optionTradingParams.expiryBuffer) {
            revert IVXOption_ExpiryBufferReached(_optionID, optionTradingParams.expiryBuffer);
        }

        int256 delta;
        if (attributes.isCall) {
            (delta,) = IVXPricer.delta(
                IVXPricer.BlackScholesInputs({
                    spotPrice: Oracle.getSpotPrice(attributes.option.underlyingAsset),
                    strikePrice: attributes.option.strikePrice,
                    impliedVolatility: Oracle.getVolatility(
                        attributes.option.underlyingAsset, attributes.option.strikePrice
                        ),
                    riskFreeRate: Oracle.getRiskFreeRate(attributes.option.underlyingAsset),
                    secondsToExpiry: timeToExpiry
                })
            );
        } else {
            (, delta) = IVXPricer.delta(
                IVXPricer.BlackScholesInputs({
                    spotPrice: Oracle.getSpotPrice(attributes.option.underlyingAsset),
                    strikePrice: attributes.option.strikePrice,
                    impliedVolatility: Oracle.getVolatility(
                        attributes.option.underlyingAsset, attributes.option.strikePrice
                        ),
                    riskFreeRate: Oracle.getRiskFreeRate(attributes.option.underlyingAsset),
                    secondsToExpiry: timeToExpiry
                })
            );
        }

        //absolute value of delta
        uint256 absoluteDelta = Math.abs(delta);
        //halt trading delta checks
        if (absoluteDelta <= optionTradingParams.deltaCutoff || absoluteDelta >= 1e18 - optionTradingParams.deltaCutoff)
        {
            revert IVXOptionNotTradeable_DeltaCutoffReached(_optionID, absoluteDelta);
        }
    }

    function _preparePricing(OptionAttributes memory optionAttributes)
        internal
        view
        returns (IVXPricer.OptionPricing memory priceInput)
    {
        uint256 secondsToExpiry = 1;
        uint256 deltaT = 1;
        if (block.timestamp < optionAttributes.option.expiry) {
            secondsToExpiry = optionAttributes.option.expiry - block.timestamp;
            deltaT = secondsToExpiry / 15; // N = 15
        }

        uint256 alpha = IVXPricer.calculateAlpha(
            secondsToExpiry, optionTradingParams.binomialCutoff, optionTradingParams.blackScholesCutoff
        );

        IIVXOracle.PricingInputs memory fetchedInputs =
            Oracle.getPricingInputs(optionAttributes.option.underlyingAsset, optionAttributes.option.strikePrice);

        priceInput = IVXPricer.OptionPricing(
            IVXPricer.PricingInputs(
                IVXPricer.FetchedInputs(
                    fetchedInputs.volatility, fetchedInputs.spot, optionAttributes.option.strikePrice
                ),
                secondsToExpiry,
                fetchedInputs.riskFreeRate,
                deltaT
            ),
            alpha
        );
    }

    function _calculateFee(
        bool isBuy,
        int256 amm_net_delta,
        int256 amm_net_vega,
        int256 delta,
        int256 vega,
        address _asset
    ) internal view returns (uint256 feeTaken) {
        int256 expected_delta;
        int256 expected_vega;
        if (isBuy) {
            // amm needs to short
            expected_delta = amm_net_delta - delta;
            expected_vega = amm_net_vega - vega;
        } else {
            // amm needs to long
            expected_delta = amm_net_delta + delta;
            expected_vega = amm_net_vega + vega;
        }

        uint256 absoluteExpectedDelta = Math.abs(expected_delta);
        uint256 absoluteExpectedVega = Math.abs(expected_vega);
        uint256 absoluteCurrentVega = Math.abs(amm_net_vega);
        uint256 absoluteCurrentDelta = Math.abs(amm_net_delta);

        //RETURN
        //MAKER TAKER FEE  |v1| < |v0| --> MAKER ; |v1| >= |v0| --> TAKER
        if (absoluteExpectedDelta < absoluteCurrentDelta) {
            uint256 deltaDifference = absoluteCurrentDelta - absoluteExpectedDelta;
            feeTaken += Oracle.getValuePriced(
                deltaDifference.mulDivUp(MakerTakerFactors[_asset].DELTA_MAKER_FACTOR, 1e18), _asset
            );
        } else {
            uint256 deltaDifference = absoluteExpectedDelta - absoluteCurrentDelta;
            feeTaken += Oracle.getValuePriced(
                deltaDifference.mulDivUp(MakerTakerFactors[_asset].DELTA_TAKER_FACTOR, 1e18), _asset
            );
        }

        if (absoluteExpectedVega < absoluteCurrentVega) {
            uint256 vegaDifference = absoluteCurrentVega - absoluteExpectedVega;
            feeTaken += vegaDifference.mulDivUp(MakerTakerFactors[_asset].VEGA_MAKER_FACTOR, 1e18);
        } else {
            uint256 vegaDifference = absoluteExpectedVega - absoluteCurrentVega;
            feeTaken += vegaDifference.mulDivUp(MakerTakerFactors[_asset].VEGA_TAKER_FACTOR, 1e18);
        }
    }

    function _settledPayoff(OptionAttributes memory optionAttributes) internal view returns (uint256) {
        uint256 underlyingAssetPrice =
            Oracle.getSpotPriceAtTime(optionAttributes.option.underlyingAsset, optionAttributes.option.expiry);

        uint256 strikePrice = optionAttributes.option.strikePrice;
        if (optionAttributes.isCall) {
            if (underlyingAssetPrice > strikePrice) {
                return underlyingAssetPrice - strikePrice;
            } else {
                return 0;
            }
        } else {
            if (underlyingAssetPrice < strikePrice) {
                return strikePrice - underlyingAssetPrice;
            } else {
                return 0;
            }
        }
    }

    function calculateCosts(uint256 _optionID, uint256 _amountContracts, bool _isClose)
        external
        view
        returns (uint256 fee, uint256 premium, int256 delta, uint256 vega)
    {
        // Fetch the option properties given the option ID
        OptionAttributes memory optionAttributes = optionIDAttributes[_optionID];

        (IVXPricer.OptionPricing memory priceInput) = _preparePricing(optionAttributes);

        //if expired
        if (optionAttributes.option.expiry <= block.timestamp) {
            //if settled
            if (optionAttributes.status.isSettled == true) {
                premium = optionAttributes.status.settlementPayoff;
            } else {
                premium = _settledPayoff(optionAttributes);
            }

            if (premium > 0) {
                fee = calculateSettlementFee(premium, _amountContracts);
            }
        } else {
            if (optionAttributes.isCall) {
                (premium, vega, delta) = IVXPricer.callIVXPricing(priceInput);
            } else {
                (premium, vega, delta) = IVXPricer.putIVXPricing(priceInput);
            }

            delta = delta * int256(_amountContracts) / 1e18;
            vega = vega * _amountContracts / 1e18;

            bool _isBuy = _isClose ? !optionAttributes.isBuy : optionAttributes.isBuy;
            (int256 amm_net_delta, int256 amm_net_vega) =
                LP.DeltaAndVegaExposure(optionAttributes.option.underlyingAsset);
            fee = _calculateFee(
                _isBuy, amm_net_delta, amm_net_vega, delta, int256(vega), optionAttributes.option.underlyingAsset
            );
        }

        premium = premium.mulDivUp(1e18, Oracle.getSpotPrice(address(LP.collateral())));
        fee = fee.mulDivUp(1e18, Oracle.getSpotPrice(address(LP.collateral())));
    }

    function calculateSettlementFee(uint256 _value, uint256 _amountContracts) public view returns (uint256) {
        return (_value.mulDivUp(_amountContracts, 1e18)).mulDivUp(optionTradingParams.FEE_TAKEN_PROFITS, 1e18);
    }

    function getOptionIDAttributes(uint256 _optionID) external view returns (OptionAttributes memory) {
        return optionIDAttributes[_optionID];
    }

    function getUnderlying_ActiveOptions(address _underlying) external view returns (uint256[] memory) {
        return underlying_ActiveOptions[_underlying];
    }

    function mint(address _to, uint256 _optionID, uint256 _amount) external onlyDiem {
        _mint(_to, _optionID, _amount, "");
    }

    function burn(address _to, uint256 _optionID, uint256 _amount) external onlyDiem {
        _burn(_to, _optionID, _amount);
    }

    function totalSupply(uint256 id) public view virtual override(ERC1155Supply, IIVXDiemToken) returns (uint256) {
        return ERC1155Supply.totalSupply(id);
    }

    function getContractsExposure(uint256 id)
        public
        view
        idModule(id)
        returns (int256 callsExposure, int256 putsExposure)
    {
        if (id > currentOptionId) revert OptionIdNotFound();

        uint256 sellPuts = totalSupply(id);
        uint256 buyPuts = totalSupply(id - 1);
        uint256 sellCalls = totalSupply(id - 2);
        uint256 buyCalls = totalSupply(id - 3);

        callsExposure = int256(buyCalls) - int256(sellCalls);
        putsExposure = int256(buyPuts) - int256(sellPuts);
    }

    function getUnderlyings() external view returns (address[] memory) {
        return underlyings;
    }

    function getCutoffs() external view returns (uint256 binomialCutoff, uint256 bsCutoff) {
        return (optionTradingParams.binomialCutoff, optionTradingParams.blackScholesCutoff);
    }

}
