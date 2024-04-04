// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
// Interfaces
import {IIVXLP} from "../interface/liquidity/IIVXLP.sol";
import {IIVXDiem} from "../interface/options/IIVXDiem.sol";
import {IIVXDiemToken} from "../interface/options/IIVXDiemToken.sol";
import {IIVXOracle} from "../interface/periphery/IIVXOracle.sol";
import {IIVXRiskEngine} from "../interface/margin/IIVXRiskEngine.sol";
import {IIVXHedger} from "../interface/exchange/IIVXHedger.sol";
// Libraries
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVXPricer} from "../libraries/IVXPricer.sol";
import {ConvertDecimals} from "../libraries/ConvertDecimals.sol";

/**
 * @title IVXLP
 * @notice The liquidity pool for the IVX protocol, inspired by the ERC4626 standard
 * @author gradient (@gradientIVX), MiguelBits (@MiguelBits)
 */
contract IVXLP is ReentrancyGuard, ERC20, Ownable, IIVXLP {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public queueContract;
    address public diemContract;
    address public hedger;
    IIVXDiem public diem;
    IIVXDiemToken public diemToken;
    IIVXOracle public oracle;
    IIVXRiskEngine public RiskEngine;

    /// @dev The address of the Collateral Token contract for the market lp
    ERC20 public collateral;

    // @dev Max utilization ratio of locked liquidity fires when depositing
    uint256 public vaultMaximumCapacity;

    uint256 public laggingNAV;

    InterestRateParams public interestRateParams;

    // @dev Total collateral assets utilized
    uint256 public utilizedCollateral;

    //daily locked liquidity,
    //when epoch expiries locked liq is released to total assets
    //after
    //paying out the optionMarket positions

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAllowedContract(address _contract) {
        if (msg.sender != _contract) {
            revert OnlyAllowedContract(msg.sender, _contract);
        }
        _;
    }

    modifier onlyAllowedContracts() {
        if (msg.sender != queueContract && msg.sender != diemContract) {
            revert OnlyAllowedContracts(msg.sender, queueContract, diemContract);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @param _vaultMaximumCapacity The max capacity of the vault based in collateral
     * @param _collateral The address of the collateral asset
     */
    constructor(uint256 _vaultMaximumCapacity, ERC20 _collateral) ERC20("IVXLP", "IVXLP", _collateral.decimals()) {
        if (address(_collateral) == address(0)) revert AddressZero();

        vaultMaximumCapacity = _vaultMaximumCapacity;
        collateral = _collateral;
    }

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setInterestRateParams(InterestRateParams calldata _interestRateParams) external onlyOwner {
        interestRateParams = _interestRateParams;
    }

    function setIVXContract(address _queueContract, address _diemContract, address _oracle, address _RiskEngine)
        external
        onlyOwner
    {
        if (address(_queueContract) == address(0)) revert AddressZero();
        queueContract = _queueContract;

        if (address(_diemContract) == address(0)) revert AddressZero();
        diemContract = _diemContract;
        diem = IIVXDiem(_diemContract);
        diemToken = IIVXDiemToken(diem.OptionToken());

        if (address(_oracle) == address(0)) revert AddressZero();
        oracle = IIVXOracle(_oracle);

        if (address(_RiskEngine) == address(0)) revert AddressZero();
        RiskEngine = IIVXRiskEngine(_RiskEngine);
    }

    function setHedger(address _hedger) external onlyOwner {
        if (address(_hedger) == address(0)) revert AddressZero();
        hedger = _hedger;
    }

    function setVaultCapacity(uint256 _vaultMaximumCapacity) external onlyOwner {
        vaultMaximumCapacity = _vaultMaximumCapacity;
    }

    /// @dev Called when Deposit collateral, Process Withraw
    /// @notice changes of collateral balance in the vault, from the queue system, updated to calculate shares properly
    function updateLaggingNAV() external onlyAllowedContract(queueContract) {
        laggingNAV = NAV();
    }

    function withdrawLiquidity(uint256 _shares, address _user) external onlyAllowedContract(queueContract) {
        uint256 _amount = calculateAmountFromShares(_shares);
        collateral.safeTransfer(_user, _amount);
        //update NAV after withdraw
    }

    function transferCollateral(address _receiver, uint256 _amount) external onlyAllowedContract(diemContract) {
        collateral.safeTransfer(_receiver, ConvertDecimals.convertFrom18AndRoundDown(_amount, collateral.decimals()));
    }

    function addUtilizedCollateral(uint256 _amount) external onlyAllowedContract(diemContract) {
        utilizedCollateral += _amount;
    }

    function subUtilizedCollateral(uint256 _amount) external onlyAllowedContract(diemContract) {
        utilizedCollateral -= _amount;
    }

    /// @param _amount comes in 18 decimals
    function transferQuoteToHedge(uint256 _amount) external onlyAllowedContract(hedger) returns (uint256) {
        //convert 18 decimals to asset decimals
        _amount = ConvertDecimals.convertFrom18AndRoundDown(_amount, collateral.decimals());
        collateral.safeTransfer(hedger, _amount);
        return _amount;
    }

    /*//////////////////////////////////////////////////////////////
                    ERC4626 FUNCTIONS FOR QUEUE
    //////////////////////////////////////////////////////////////*/

    function mint(address _user, uint256 _amount) external onlyAllowedContract(queueContract) {
        uint256 _shares = calculateSharesFromAmount(_amount);
        _mint(_user, _shares);
    }

    function burn(address _user, uint256 _amount) external onlyAllowedContract(queueContract) {
        _burn(_user, _amount);
    }

    function calculateSharesFromAmount(uint256 _amount) public view returns (uint256) {
        uint256 _shares = 0;
        if (laggingNAV > 0) {
            _shares = _amount.mulDivDown(totalSupply, laggingNAV);
        } else {
            _shares = _amount;
        }
        return _shares;
    }

    function calculateAmountFromShares(uint256 _shares) public view returns (uint256) {
        uint256 _amount = 0;
        if (laggingNAV > 0) {
            _amount = _shares.mulDivDown(laggingNAV, totalSupply);
        } else {
            _amount = _shares;
        }
        return _amount;
    }

    /*///////////////////////////////////////////////////////////////
                                AMM EXPOSURE
    ///////////////////////////////////////////////////////////////*/

    function DeltaAndVegaExposure(address asset) external view returns (int256 deltaExposed, int256 vegaExposed) {
        uint256[] memory activeOptions = diemToken.getUnderlying_ActiveOptions(asset);
        uint256 arraylength = activeOptions.length;
        if (arraylength == 0) {
            return (0, 0);
        }

        for (uint256 j; j < arraylength; ++j) {
            uint256 id = activeOptions[j];

            (int256 callsExposure, int256 putsExposure) = diemToken.getContractsExposure(id);
            if (callsExposure == 0 && putsExposure == 0) {
                continue;
            }

            // Fetch optionAttributes and pricingInputs once
            IIVXDiemToken.OptionAttributes memory optionAttributes = diemToken.getOptionIDAttributes(id);
            IIVXOracle.PricingInputs memory pricingInputs =
                oracle.getPricingInputs(optionAttributes.option.underlyingAsset, optionAttributes.option.strikePrice);
            IVXPricer.BlackScholesInputs memory blackScholesInputs = IVXPricer.BlackScholesInputs(
                pricingInputs.spot,
                optionAttributes.option.strikePrice,
                pricingInputs.volatility,
                pricingInputs.riskFreeRate,
                optionAttributes.option.expiry - block.timestamp
            );

            (int256 _deltaExposed, int256 _vegaExposed) =
                calculateDeltaAndVega(blackScholesInputs, callsExposure, putsExposure);
            deltaExposed += _deltaExposed;
            vegaExposed += _vegaExposed;
        }
    }

    function deltaExposure(address asset) external view returns (int256 deltaExposed) {
        uint256[] memory activeOptions = diemToken.getUnderlying_ActiveOptions(asset);
        uint256 arraylength = activeOptions.length;
        if (arraylength == 0) {
            return 0;
        }

        for (uint256 j; j < arraylength; ++j) {
            uint256 id = activeOptions[j];

            (int256 callsExposure, int256 putsExposure) = diemToken.getContractsExposure(id);

            if (callsExposure == 0 && putsExposure == 0) {
                // No exposure, continue with other logic or return
                continue;
            } else {
                // Fetch optionAttributes and pricingInputs once
                IIVXDiemToken.OptionAttributes memory optionAttributes = diemToken.getOptionIDAttributes(id);
                IIVXOracle.PricingInputs memory pricingInputs = oracle.getPricingInputs(
                    optionAttributes.option.underlyingAsset, optionAttributes.option.strikePrice
                );

                IVXPricer.BlackScholesInputs memory blackScholesInputs = IVXPricer.BlackScholesInputs(
                    pricingInputs.spot,
                    optionAttributes.option.strikePrice,
                    pricingInputs.volatility,
                    pricingInputs.riskFreeRate,
                    optionAttributes.option.expiry - block.timestamp
                );

                deltaExposed += _calculateDeltaExposure(blackScholesInputs, callsExposure, putsExposure);
            }
        }
    }

    function _calculateDeltaExposure(
        IVXPricer.BlackScholesInputs memory blackScholesInputs,
        int256 callsExposure,
        int256 putsExposure
    ) internal pure returns (int256 deltaExposed) {
        if (callsExposure == 0) {
            // Your logic for putsExposure when callsExposure == 0
            (, int256 putDeltaDecimal) = IVXPricer.delta(blackScholesInputs);
            putDeltaDecimal = (putDeltaDecimal * putsExposure) / 1e18;
            deltaExposed = putDeltaDecimal;
        } else if (putsExposure == 0) {
            // Your logic for callsExposure when putsExposure == 0
            (int256 callDeltaDecimal,) = IVXPricer.delta(blackScholesInputs);
            callDeltaDecimal = (callDeltaDecimal * callsExposure) / 1e18;
            deltaExposed = callDeltaDecimal;
        } else {
            // Your logic for both callsExposure and putsExposure
            (int256 callDeltaDecimal, int256 putDeltaDecimal) = IVXPricer.delta(blackScholesInputs);
            // Multiply delta by contracts open on diem
            callDeltaDecimal = (callDeltaDecimal * callsExposure) / 1e18;
            putDeltaDecimal = (putDeltaDecimal * putsExposure) / 1e18;
            // Add to total delta exposure
            deltaExposed = callDeltaDecimal + putDeltaDecimal;
        }
    }

    function vegaExposure(address asset) external view returns (int256 vegaExposed) {
        uint256[] memory activeOptions = diemToken.getUnderlying_ActiveOptions(asset);
        uint256 arraylength = activeOptions.length;

        for (uint256 j; j < arraylength; ++j) {
            uint256 id = activeOptions[j];

            (int256 callsExposure, int256 putsExposure) = diemToken.getContractsExposure(id);

            if (callsExposure == 0 && putsExposure == 0) {
                // No exposure, continue with other logic or return
                continue;
            } else {
                // Fetch optionAttributes and pricingInputs once
                IIVXDiemToken.OptionAttributes memory optionAttributes = diemToken.getOptionIDAttributes(id);
                IIVXOracle.PricingInputs memory pricingInputs = oracle.getPricingInputs(
                    optionAttributes.option.underlyingAsset, optionAttributes.option.strikePrice
                );
                IVXPricer.BlackScholesInputs memory blackScholesInputs = IVXPricer.BlackScholesInputs(
                    pricingInputs.spot,
                    optionAttributes.option.strikePrice,
                    pricingInputs.volatility,
                    pricingInputs.riskFreeRate,
                    optionAttributes.option.expiry - block.timestamp
                );
                vegaExposed += _calculateVegaExposure(blackScholesInputs, callsExposure, putsExposure);
            }
        }
    }

    function _calculateVegaExposure(
        IVXPricer.BlackScholesInputs memory blackScholesInputs,
        int256 callsExposure,
        int256 putsExposure
    ) internal pure returns (int256 vegaExposed) {
        uint256 vega;
        if (callsExposure == 0) {
            // Your logic for putsExposure when callsExposure == 0
            vega = IVXPricer.vega(blackScholesInputs);
            vegaExposed = (int256(vega) * putsExposure) / 1e18;
        } else if (putsExposure == 0) {
            // Your logic for callsExposure when putsExposure == 0
            vega = IVXPricer.vega(blackScholesInputs);
            vegaExposed = (int256(vega) * callsExposure) / 1e18;
        } else {
            // Your logic for both callsExposure and putsExposure
            vega = IVXPricer.vega(blackScholesInputs);
            int256 _vega = int256(vega);
            // Multiply delta by contracts open on diem & // Add to total delta exposure
            vegaExposed = (_vega * callsExposure) / 1e18 + (_vega * putsExposure) / 1e18;
        }

        //inverse vega, because amm takes counter of trades
        vegaExposed = vegaExposed * -1;
    }

    function calculateDeltaAndVega(
        IVXPricer.BlackScholesInputs memory blackScholesInputs,
        int256 callsExposure,
        int256 putsExposure
    ) public pure returns (int256 deltaExposed, int256 vegaExposed) {
        if (callsExposure == 0 && putsExposure == 0) {
            // No exposure, continue with other logic or return
            vegaExposed = 0;
        } else if (callsExposure == 0) {
            // Your logic for putsExposure when callsExposure == 0
            (, int256 putDeltaDecimal, uint256 vega) = IVXPricer.delta_vega(blackScholesInputs);
            putDeltaDecimal = (putDeltaDecimal * putsExposure) / 1e18;
            deltaExposed = putDeltaDecimal;
            vegaExposed = (int256(vega) * putsExposure) / 1e18;
        } else if (putsExposure == 0) {
            // Your logic for callsExposure when putsExposure == 0
            (int256 callDeltaDecimal,, uint256 vega) = IVXPricer.delta_vega(blackScholesInputs);
            vegaExposed = (int256(vega) * callsExposure) / 1e18;
            callDeltaDecimal = (callDeltaDecimal * callsExposure) / 1e18;
            deltaExposed = callDeltaDecimal;
        } else {
            // Your logic for both callsExposure and putsExposure
            (int256 callDeltaDecimal, int256 putDeltaDecimal, uint256 vega) = IVXPricer.delta_vega(blackScholesInputs);
            // Multiply delta by contracts open on diem
            callDeltaDecimal = (callDeltaDecimal * callsExposure) / 1e18;
            putDeltaDecimal = (putDeltaDecimal * putsExposure) / 1e18;
            // Add to total delta exposure
            deltaExposed = callDeltaDecimal + putDeltaDecimal;

            int256 _vega = int256(vega);
            // Multiply delta by contracts open on diem & // Add to total delta exposure
            vegaExposed = (_vega * callsExposure) / 1e18 + (_vega * putsExposure) / 1e18;
        }

        // vegaExposed > 0 ? console.log("vegaExposed: %s", uint256(vegaExposed)) : console.log("vegaExposed: %s", uint256(-vegaExposed));
        //inverse delta and vega, because amm takes counter of trades
        deltaExposed = deltaExposed * -1;
        vegaExposed = vegaExposed * -1;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function interestRate() external view returns (uint256) {
        uint256 _utilizationRatio = utilizationRatio();
        //between 0% utilization ration and inflection rate
        if (_utilizationRatio <= interestRateParams.InflectionUtilization) {
            //= ((inflection rate - min rate) / inflection utilization) * utilization ratio + min rate
            return (interestRateParams.InflectionRate - interestRateParams.MinRate).mulDivUp(
                1e18, interestRateParams.InflectionUtilization
            ).mulDivUp(_utilizationRatio, 1e18) + interestRateParams.MinRate;
        }
        //between inflection rate and max rate
        else {
            //= ((max rate - inflection rate) / (max utilization - inflection utilization)) * utilization ratio + (max utilization * inflection rate - max rate * inflection utilization) / (max utilization - inflection utilization)
            uint256 divisor = interestRateParams.MaxUtilization - interestRateParams.InflectionUtilization;
            return (interestRateParams.MaxRate - interestRateParams.InflectionRate).mulDivUp(
                1e18, interestRateParams.MaxUtilization - interestRateParams.InflectionUtilization
            ).mulDivUp(_utilizationRatio, 1e18)
                + interestRateParams.MaxUtilization.mulDivUp(interestRateParams.InflectionRate, 1e18).mulDivUp(
                    1e18, divisor
                )
                - interestRateParams.MaxRate.mulDivUp(interestRateParams.InflectionUtilization, 1e18).mulDivUp(
                    1e18, divisor
                );
        }
    }

    //@notice The assets available (excluding the option positions)
    function totalAvailableAssets() external view returns (uint256) {
        return NAV() - utilizedCollateral;
    }

    //@notice This does not include option positions
    //@dev The total collateral assets of the vault
    function NAV() public view returns (uint256) {
        return collateral.balanceOf(address(this));
    }

    function maxUtilizationRatio() external view returns (uint256) {
        return interestRateParams.MaxUtilization;
    }

    /// @notice The utilization ratio of ivx usd to collateral
    function utilizationRatio() public view returns (uint256) {
        if(NAV() == 0) revert IVXLPZeroNAV();

        uint256 hedgerTotalLiq;
        address[] memory allOptionsUnderlyingAssets = diemToken.getUnderlyings();
        uint256 _utilizedCollateral = ConvertDecimals.convertFrom18AndRoundUp(utilizedCollateral, collateral.decimals());
        uint256 MM; //maintenance margin required;

        //loop all assets
        uint256 underlyingsLength = allOptionsUnderlyingAssets.length;
        for (uint256 i; i < underlyingsLength; ++i) {
            address asset = allOptionsUnderlyingAssets[i];
            MM += _getMarginRequired(asset);
            hedgerTotalLiq += IIVXHedger(hedger).getTotalHedgingLiquidity(asset);
        }

        uint8 _decimals = collateral.decimals();
        // (utilized collateral + MM + money on gmx) / NAV
        return ConvertDecimals.convertTo18(
            ConvertDecimals.convertFrom18AndRoundUp(_utilizedCollateral + MM + hedgerTotalLiq, _decimals).mulDivUp(
                10 ** _decimals, NAV()
            ),
            _decimals
        );
    }

    function _getMarginRequired(address asset) internal view returns (uint256 MM) {
        uint256[] memory activeOptionIds = diemToken.getUnderlying_ActiveOptions(asset);
        uint256 activeOptionIdsLength = activeOptionIds.length;
        //loop all active ids
        for (uint256 j; j < activeOptionIdsLength; ++j) {
            uint256 id = activeOptionIds[j];
            IIVXDiemToken.OptionAttributes memory optionAttributes = diemToken.getOptionIDAttributes(id);
            //if option expired do not add
            if (optionAttributes.option.expiry <= block.timestamp) continue;

            StructuredForExposure memory structured = _getPremiumsExposure(id, optionAttributes);

            MM += RiskEngine.positionMaintenanceMargin(structured.call_premium, structured.spot, asset).mulDivUp(
                uint256(structured.callsExposure), 1e18
            )
                + RiskEngine.positionMaintenanceMargin(structured.put_premium, structured.spot, asset).mulDivUp(
                    uint256(structured.putsExposure), 1e18
                );
        }
    }

    function _getPremiumsExposure(uint256 id, IIVXDiemToken.OptionAttributes memory optionAttributes)
        internal
        view
        returns (StructuredForExposure memory structured)
    {
        (int256 nCallsExposed, int256 nPutsExposed) = diemToken.getContractsExposure(id);
        IIVXOracle.PricingInputs memory fetchedInputs =
            oracle.getPricingInputs(optionAttributes.option.underlyingAsset, optionAttributes.option.strikePrice);

        uint256 secondsToExpire = optionAttributes.option.expiry - block.timestamp;
        (uint256 bnCutoff, uint256 bsCutoff) = diemToken.getCutoffs();

        IVXPricer.OptionPricing memory pricing = IVXPricer.OptionPricing({
            inputs: IVXPricer.PricingInputs({
                fetchedInputs: IVXPricer.FetchedInputs({
                    impliedVolatility: fetchedInputs.volatility,
                    spotPrice: fetchedInputs.spot,
                    strikePrice: optionAttributes.option.strikePrice
                }),
                secondsToExpiry: secondsToExpire,
                riskFreeRate: fetchedInputs.riskFreeRate,
                deltaT: secondsToExpire / 15
            }),
            Alpha: IVXPricer.calculateAlpha(secondsToExpire, bnCutoff, bsCutoff)
        });

        if (nCallsExposed >= 0) {
            structured.callsExposure = uint256(nCallsExposed);
        } else {
            structured.callsExposure = uint256(-nCallsExposed);
        }

        if (nPutsExposed >= 0) {
            structured.putsExposure = uint256(nPutsExposed);
        } else {
            structured.putsExposure = uint256(-nPutsExposed);
        }

        structured.call_premium = IVXPricer.callOptionPricing(pricing);
        structured.put_premium = IVXPricer.putOptionPricing(pricing);
        structured.spot = fetchedInputs.spot;

        return structured;
    }
}
