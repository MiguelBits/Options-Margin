// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

// Libraries
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ConvertDecimals} from "../libraries/ConvertDecimals.sol";

// Interfaces
import {IIVXDiem} from "../interface/options/IIVXDiem.sol";
import {IIVXLP} from "../interface/liquidity/IIVXLP.sol";
import {IIVXOracle} from "../interface/periphery/IIVXOracle.sol";
import {IIVXDiemToken} from "../interface/options/IIVXDiemToken.sol";
import {IIVXRiskEngine} from "../interface/margin/IIVXRiskEngine.sol";
import {IIVXPortfolio} from "../interface/margin/IIVXPortfolio.sol";

/// @title IVXDiem
/// @author gradient (@gradientIVX), MiguelBits (@MiguelBits)
contract IVXDiem is IIVXDiem, Ownable, Pausable, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    FeeDistribution public feeDistribution;

    /// @dev The address of the LP contract which facilitates trading
    IIVXLP public LP;

    /// @dev The address of the margin contract which contains user's margin balances
    IIVXRiskEngine public RiskEngine;

    address Exchange;
    address Oracle;

    IIVXDiemToken public OptionToken;

    /// @dev The address of the treasury
    address public treasury;
    address public staker;

    /// @dev The liquidation percentage at which the user's position is liquidated, 200 = 20%
    uint256 public liquidationThreshold;

    /// @dev The multiplier for fee calculation based on spot price
    uint256 public spotFeeMultiplier;

    uint256 public maxBatchTrading = 5;

    uint256 liqBonusPercent = 0.01 ether; // 100 = 1% ; 10000 = 100%

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier hasIVXPortfolio(address _user) {
        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(_user);
        if (address(portfolio) == address(0)) revert IVX_NoPortfolioContractCreated();
        _;
    }

    constructor(IIVXLP _LP, address _treasury, address _staker, FeeDistribution memory _feeDistribution) {
        if (address(_LP) == address(0)) revert AddressZero();
        if (_treasury == address(0)) revert AddressZero();

        LP = _LP;
        treasury = _treasury;
        staker = _staker;

        //require that fees distribution summed are 1 ether
        if (_feeDistribution.treasuryFee + _feeDistribution.stakerFee + _feeDistribution.lpFee != 1 ether) revert InvalidFeeDistribution();
        feeDistribution = _feeDistribution;        
    }

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @dev Initializes the contract
    /// @param _RiskEngine The address of the IVXMargin contract
    function initialize(IIVXRiskEngine _RiskEngine, IIVXDiemToken _OptionToken, address _exchange, address _oracle)
        external
        onlyOwner
    {
        if (address(RiskEngine) != address(0)) revert AddressZero();
        RiskEngine = _RiskEngine;
        OptionToken = _OptionToken;
        Exchange = _exchange;
        Oracle = _oracle;
    }

    /// @dev Changes the treasury address
    /// @param _treasury The address of the new treasury
    function changeTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert AddressZero();
        treasury = _treasury;

        emit TreasuryChanged(_treasury);
    }

    function changeStaker(address _staker) external onlyOwner {
        if (_staker == address(0)) revert AddressZero();
        staker = _staker;

        emit StakerChanged(_staker);
    }

    function changeFeeDistribution(FeeDistribution memory _feeDistribution) external onlyOwner {
        //require that fees distribution summed are 1 ether
        if (_feeDistribution.treasuryFee + _feeDistribution.stakerFee + _feeDistribution.lpFee != 1 ether) revert InvalidFeeDistribution();
        feeDistribution = _feeDistribution;
    }

    function changeMaxBatchTrading(uint256 _maxBatchTrading) external onlyOwner {
        maxBatchTrading = _maxBatchTrading;
        emit MaxBatchTradingChanged(_maxBatchTrading);
    }

    function changeLiqBonusPercent(uint256 _liqBonusPercent) external onlyOwner {
        liqBonusPercent = _liqBonusPercent;
        emit LiqBonusPercentChanged(_liqBonusPercent);
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/

    function openTrades(TradeInfo[] calldata traded) external nonReentrant whenNotPaused hasIVXPortfolio(msg.sender) {
        if (
            traded.length == 0 || traded.length > maxBatchTrading //fixed max open of trades to avoid ddos
        ) {
            revert InvalidTradeArray();
        }
        
        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(msg.sender);
        _revertIfLiquidatable(portfolio);

        uint256 totalFee;
        uint256 arraylength = traded.length;
        for (uint256 i; i < arraylength; ++i) {
            if (traded[i].amountContracts == 0) revert InvalidTrade();
            uint256 _totalFee = _openTrade(traded[i], portfolio);
            totalFee += _totalFee;
        }

        if (totalFee > 0) {
            //after all trades are opened, transfer the total fee
            _splitFees(portfolio, totalFee);
        }

        //revert if LP maxUtilizationRatio is reached
        if (LP.utilizationRatio() >= LP.maxUtilizationRatio()) {
            revert IIVXLP.IVX_MaxUtilizationReached(LP.utilizationRatio(), LP.maxUtilizationRatio());
        }

        //check if user becomes liquidated
        _revertIfLiquidatable(portfolio);
    }

    function closeTrade(TradeInfo calldata traded) external nonReentrant hasIVXPortfolio(msg.sender) {
        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(msg.sender);

        _revertIfLiquidatable(portfolio);

        (int256 effectivePnl, uint256 totalFee) = _closeTrade(portfolio, traded.optionID, traded.amountContracts);
        _pnlOperations(effectivePnl, totalFee, portfolio);
    }

    function closeTrades(TradeInfo[] calldata traded) external nonReentrant hasIVXPortfolio(msg.sender) {
        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(msg.sender);
        _revertIfLiquidatable(portfolio);

        if (
            traded.length == 0 || traded.length > maxBatchTrading //fixed max open of trades to avoid ddos
        ) {
            revert InvalidTradeArray();
        }

        uint256 arraylength = traded.length;
        int256 effectivePnl;
        uint256 totalFee;

        for (uint256 i; i < arraylength; ++i) {
            (int256 _effectivePnl, uint256 _totalFee) = _closeTrade(portfolio, traded[i].optionID, traded[i].amountContracts);
            effectivePnl += _effectivePnl;
            totalFee += _totalFee;
        }

        _pnlOperations(effectivePnl, totalFee, portfolio);
    }

    /// @notice force closes an option trade if it is already settled and there are still contracts open
    function forceClose(address _user, uint256 _optionId) external nonReentrant hasIVXPortfolio(_user) {
        
        if (OptionToken.getOptionIDAttributes(_optionId).status.isSettled == false) revert IVX_OptionNotSettled();

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(_user);
        _revertIfLiquidatable(portfolio);
        
        (int256 effectivePnl, uint256 _totalFee) = _closeTrade(portfolio, _optionId, 0);

        _pnlOperations(effectivePnl, _totalFee, portfolio);
    }

    function liquidate(address _user) external nonReentrant hasIVXPortfolio(_user) {
        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(_user);

        if (isPortfolioLiquidatable(portfolio) == false) revert IVX_PortfolioNotLiquidatable();

        int256 effectivePnl;
        uint256 totalFee;
        //close all trades
        uint256[] memory optionIds = portfolio.getOpenOptionIds();
        for (uint256 i; i < optionIds.length; i++) {
            uint256 _optionId = optionIds[i];
            (int256 _effectivePnl, uint256 _totalFee) = _closeTrade(portfolio, _optionId, 0);
            effectivePnl += _effectivePnl;
            totalFee += _totalFee;
        }
        uint256 pnl = uint256(-effectivePnl);
        //pnl to portfolio
        if (effectivePnl > 0) {
            //this should never come here
            revert IVX_NotLiquidatedProperly();
        } else if (pnl >= RiskEngine.getEffectiveMargin(portfolio)) {
            //liquidate every asset, because user has more debt than available assets
            pnl = RiskEngine.portfolioDollarMargin(portfolio);
            portfolio.liquidate();
        } else {
            //subtract pnl from portfolio
            portfolio.removeMargin(address(this), pnl);
        }

        _splitFees(totalFee); // using this function because pnl was already transfered to this contract with the fees included
        pnl -= totalFee; //subtract fees from pnl because we added it in calculate pnl
        //take liq bonus out of effective pnl
        uint256 liqBonus = pnl.mulDivDown(liqBonusPercent, 1 ether); //calculate liquidation bonus
        pnl -= liqBonus; //subtract liq bonus

        //scale to collateral decimals
        ERC20 collateral = LP.collateral();
        pnl = ConvertDecimals.convertFrom18AndRoundDown(pnl, collateral.decimals());
        liqBonus = ConvertDecimals.convertFrom18AndRoundDown(liqBonus, collateral.decimals());
        //send bonus to liquidator and remaining pnl to LP
        collateral.transfer(msg.sender, liqBonus); //send liq bonus to liquidator
        collateral.transfer(address(LP), pnl); //send pnl to portfolio

        //check if user health factor improved, this should never be met
        if (calculateHealthFactor(portfolio) != 0) revert IVX_NotLiquidatedProperly();

        emit Liquidated(address(portfolio), msg.sender, effectivePnl);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates Portfolio Net Value
    function calculatePortfolioNetValue(IIVXPortfolio portfolio) external view returns(int256 PNL){
        uint256[] memory optionIds = portfolio.getOpenOptionIds();
        uint256 arraylength = optionIds.length;
        if (arraylength == 0) return 0;

        Trade[] memory trades = new Trade[](arraylength);
        for (uint256 i; i < arraylength; ++i) {
            trades[i] = portfolio.getOptionIdTrade(optionIds[i]);
        }
        
        return TradesNetValue(trades);
    }

    /// @notice Calculates Trades Net Value
    function TradesNetValue(Trade[] memory _trades) public view returns (int256 netValue) {
        uint256 arraylength = _trades.length;

        for (uint256 i; i < arraylength; ++i) {
            (int256 PNL, ) = calculatePnl(_trades[i], _trades[i].contractsOpen);
            netValue += PNL;
        }
    }

    /// @notice Calculates the PNL of a trade, including fees
    function calculatePnl(Trade memory _trade, uint256 closedUnits) public view returns(int256 PNL, uint256 fee){
        Pnl_Premiums_Greeks memory structured = _calculatePnl(_trade, closedUnits);
        PNL = structured.PNL;
        fee = structured.totalFee;
    }


    function isPortfolioLiquidatable(IIVXPortfolio portfolio) public view returns (bool) {
        IIVXRiskEngine.MarginParams memory marginParams = _portfolioMarginParams(portfolio);

        return RiskEngine.isEligibleForLiquidation(portfolio, marginParams);
    }

    function calculateHealthFactor(IIVXPortfolio portfolio) public view returns (uint256 healthFactor) {
        IIVXRiskEngine.MarginParams memory marginParams = _portfolioMarginParams(portfolio);
        healthFactor = RiskEngine.healthFactor(portfolio, marginParams);
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _openTrade(TradeInfo calldata traded, IIVXPortfolio portfolio) internal returns (uint256 totalFee) {
        //check if option is tradeable
        OptionToken.isTradeable(traded.optionID);

        (uint256 _fee, uint256 _premium,,) = OptionToken.calculateCosts(traded.optionID, traded.amountContracts, false);
        
        uint256 totalPremium = _premium.mulDivUp(traded.amountContracts, 1e18);

        IIVXDiem.Trade memory _oldTrade = portfolio.getOptionIdTrade(traded.optionID);
        IIVXDiemToken.OptionAttributes memory attributes = OptionToken.getOptionIDAttributes(traded.optionID);

        totalFee += _fee;
        Trade memory _newTrade;
        //check if there is an existing trade in trade index that matches the traded option direction
        if (_oldTrade.contractsOpen > 0) {
            _newTrade = Trade({
                timestamp: block.timestamp, //update timestamp and pay interest below
                optionID: traded.optionID,
                contractsOpen: _oldTrade.contractsOpen + traded.amountContracts,
                averageEntry: (_oldTrade.averageEntry.mulDivUp(_oldTrade.contractsOpen, 1e18) + totalPremium).mulDivUp(
                    1e18, _oldTrade.contractsOpen + traded.amountContracts
                    ), //single contract average entry
                borrowedAmount: attributes.isBuy ? totalPremium + _oldTrade.borrowedAmount : 0
            });
            portfolio.updateTrade(traded.optionID, _newTrade);

            emit TradeIncreased(_newTrade, address(portfolio));
        } else {
            //add trade to portfolio
            _newTrade = Trade({
                timestamp: block.timestamp,
                optionID: traded.optionID,
                contractsOpen: traded.amountContracts,
                averageEntry: _premium,
                borrowedAmount: attributes.isBuy ? totalPremium : 0
            });
            portfolio.addTrade(traded.optionID, _newTrade);

            emit TradeOpened(_newTrade, address(portfolio));
        }

        //mint option token
        OptionToken.mint(address(portfolio), traded.optionID, traded.amountContracts);

        if (
            attributes.isBuy //if buy add to utilized collateral
        ) {
            LP.addUtilizedCollateral(totalPremium);

            //and add borrow fee to total fee, to pay all borrow fees of last trade
            if (_oldTrade.timestamp > 0) {
                totalFee += RiskEngine.calculateBorrowFee(
                    _oldTrade.borrowedAmount, LP.interestRate(), (block.timestamp - _oldTrade.timestamp)
                );
            }
        } //if sell transfer collateral from amm to portfolio
        else {
            LP.transferCollateral(address(portfolio), totalPremium);
        }
    }

    function _closeTrade(IIVXPortfolio portfolio, uint256 _optionId, uint256 _amountContracts)
        internal
        returns (int256 effectivePnL, uint256 totalFee)
    {
        Trade memory trade = portfolio.getOptionIdTrade(_optionId);
        if (trade.contractsOpen == 0) revert InvalidTrade();

        if (_amountContracts == 0) _amountContracts = trade.contractsOpen; //liquidation specific
        if (trade.contractsOpen < _amountContracts) revert IVX_CannotCloseMoreThanOpenContracts();

        IIVXDiemToken.OptionAttributes memory attributes = OptionToken.getOptionIDAttributes(_optionId);
        if (attributes.option.expiry <= block.timestamp) {
            //if not settled, then settle
            if (attributes.status.isSettled == false) {
                uint256 _id;
                if (attributes.isBuy && attributes.isCall) _id = trade.optionID + 3;
                else if (!attributes.isBuy && attributes.isCall) _id = trade.optionID + 2;
                else if (attributes.isBuy && !attributes.isCall) _id = trade.optionID + 1;
                else _id = trade.optionID;
                OptionToken.settleOptionsExpired(_id);
            }
            _amountContracts = trade.contractsOpen; //close all contracts if expired
        }

        //calculate pnl
        Pnl_Premiums_Greeks memory structured = _calculatePnl(trade, _amountContracts);
        effectivePnL = structured.PNL;
        totalFee = structured.totalFee;

        OptionToken.burn(address(portfolio), _optionId, _amountContracts);

        uint256 borrowedAmount;
        if (trade.borrowedAmount > 0) {
            borrowedAmount = trade.borrowedAmount.mulDivUp(_amountContracts, trade.contractsOpen);
            LP.subUtilizedCollateral(borrowedAmount);
        }

        //update trade
        if (trade.contractsOpen == _amountContracts) {
            //close trade
            portfolio.closeTrade(_optionId);

            emit TradeClosed(trade, address(portfolio));
        } else {
            //update trade
            trade.contractsOpen -= _amountContracts;
            if (trade.borrowedAmount > 0) {
                trade.borrowedAmount -= borrowedAmount;
            }
            trade.timestamp = block.timestamp;
            portfolio.updateTrade(_optionId, trade);

            emit TradeDecreased(trade, address(portfolio));
        }
    }

    function _calculatePnl(Trade memory _trade, uint256 closedUnits)
        internal
        view
        returns (Pnl_Premiums_Greeks memory structured)
    {
        (uint256 closingFee, uint256 premiumValue, int256 delta, uint256 vega) =
            OptionToken.calculateCosts(_trade.optionID, closedUnits, true);
        IIVXDiemToken.OptionAttributes memory attributes = OptionToken.getOptionIDAttributes(_trade.optionID);

        //option expired scenario
        if (attributes.option.expiry <= block.timestamp) {
            if (premiumValue == 0) {
                if (
                    attributes.isBuy //maximum loss is the premium paid
                ) {
                    structured.PNL -= int256(_trade.borrowedAmount);
                } //maximum profit is the premium received
                else {
                    structured.PNL += int256(_trade.averageEntry.mulDivUp(closedUnits, 1e18));
                }
            } else {
                if (
                    attributes.isBuy //profit is infinite
                ) {
                    structured.PNL += int256(premiumValue.mulDivUp(closedUnits, 1e18)) - int256(_trade.borrowedAmount);
                } //loss is infinite
                else {
                    structured.PNL -= int256(premiumValue.mulDivUp(closedUnits, 1e18));
                }
            }
        } else {
            int256 averageEntryValue = int256(closedUnits.mulDivUp(_trade.averageEntry, 1e18)); //entry premium value
            int256 averageExitValue;
            if (premiumValue != 0) {
                averageExitValue = int256(premiumValue.mulDivUp(closedUnits, 1e18));
            }

            // Calculate the realised PNL
            // realisedPnl += (_trade.isBuy) ? averageExitValue - averageEntryValue : averageEntryValue - averageExitValue;
            if (attributes.isBuy) {
                structured.PNL = averageExitValue - averageEntryValue; //spot price - entry price
            } else {
                // sell option case
                structured.PNL = averageEntryValue - averageExitValue; //entry price - spot price
            }
        }

        //fee accounting
        if (
            closingFee > 0 //if > 0 means premium value is also > 0
        ) {
            uint256 _fee = closingFee;
            structured.PNL -= int256(_fee);
            structured.totalFee += _fee;
        } else {
            uint256 _fee = OptionToken.calculateSettlementFee(premiumValue, closedUnits);
            //if < 0 means premium value is also < 0
            structured.PNL -= int256(_fee);
            structured.totalFee += _fee;
        }
        //if selling, dont add borrowFee
        if (attributes.isBuy) {
            if (block.timestamp > _trade.timestamp) {
                uint256 _fee = 
                    RiskEngine.calculateBorrowFee(
                        _trade.borrowedAmount, LP.interestRate(), (block.timestamp - _trade.timestamp)
                    );
                structured.PNL -= int256(_fee);
                structured.totalFee += _fee;
            }
        }

        structured.premiumValue = premiumValue;
        structured.delta = delta;
        structured.vega = vega;
    }

    function _pnlOperations(int256 _effectivePnl, uint256 _totalFee, IIVXPortfolio portfolio) internal {
        //add fee to pnl, because it was subtracted before, and we want to remove fees in a different way than the pnl
        _effectivePnl += int256(_totalFee);

        //pnl to portfolio
        if (_effectivePnl > 0) {
            //add pnl to portfolio
            LP.transferCollateral(address(portfolio), uint256(_effectivePnl));
        } else {
            //subtract pnl from portfolio
            portfolio.removeMargin(address(LP), uint256(-_effectivePnl));
        }
        _splitFees(portfolio, _totalFee);
    }

    function _splitFees(uint256 _totalFee) internal {
        ERC20 _collateral = LP.collateral();
        uint8 _decimals = _collateral.decimals();

        //split the fees
        uint256 _treasuryFee = ConvertDecimals.convertFrom18AndRoundDown(_totalFee.mulDivDown(feeDistribution.treasuryFee, 1 ether), _decimals);
        uint256 _stakerFee = ConvertDecimals.convertFrom18AndRoundDown(_totalFee.mulDivDown(feeDistribution.stakerFee, 1 ether), _decimals);
        uint256 _lpFee = ConvertDecimals.convertFrom18AndRoundDown(_totalFee.mulDivDown(feeDistribution.lpFee, 1 ether), _decimals);

        //send fees to treasury
        _collateral.transfer(treasury, _treasuryFee);

        //send fees to stakers
        _collateral.transfer(staker, _stakerFee);

        //send fees to lp
        _collateral.transfer(address(LP), _lpFee);
    }

    function _splitFees(IIVXPortfolio portfolio, uint256 _totalFee) internal {
        //remove the fees to this contract
        portfolio.removeMargin(address(this), _totalFee);
        
        _splitFees(_totalFee);
    }

    function _portfolioMarginParams(IIVXPortfolio portfolio)
        internal
        view
        returns (IIVXRiskEngine.MarginParams memory marginParams)
    {
        uint256[] memory optionIds = portfolio.getOpenOptionIds();
        uint256 arraylength = optionIds.length;
        if (arraylength == 0) return marginParams;

        int256 pnl;

        marginParams = IIVXRiskEngine.MarginParams({
            contractsTraded: new uint256[](arraylength),
            X: new uint256[](arraylength),
            Y: new uint256[](arraylength),
            asset: new address[](arraylength),
            strikes: new uint256[](arraylength),
            borrowAmount: new uint256[](arraylength),
            interestRate: LP.interestRate(),
            timeOpen: new uint256[](arraylength),
            orderLoss: pnl,
            deltas: new int256[](arraylength),
            vegas: new int256[](arraylength)
        });

        uint256 timestampNow = block.timestamp;
        for (uint256 i; i < arraylength; ++i) {
            // get option attributes
            IIVXDiemToken.OptionAttributes memory attributes = OptionToken.getOptionIDAttributes(optionIds[i]);
            Trade memory _trade = portfolio.getOptionIdTrade(optionIds[i]);

            marginParams.contractsTraded[i] = _trade.contractsOpen;
            marginParams.borrowAmount[i] = _trade.borrowedAmount;
            if (timestampNow != _trade.timestamp) {
                marginParams.timeOpen[i] = (timestampNow - _trade.timestamp);
            }
            Pnl_Premiums_Greeks memory structured = _calculatePnl(_trade, _trade.contractsOpen);
            address _asset = attributes.option.underlyingAsset;
            marginParams.X[i] = IIVXOracle(Oracle).getSpotPrice(_asset);
            marginParams.Y[i] = structured.premiumValue;
            marginParams.asset[i] = _asset;
            marginParams.strikes[i] = attributes.option.strikePrice;
            marginParams.deltas[i] = structured.delta;
            marginParams.vegas[i] = attributes.isBuy ? int256(structured.vega) : -int256(structured.vega); //if sell vega is negative
            pnl += structured.PNL;
        }

        marginParams.orderLoss = pnl;

        return marginParams;
    }

    function _revertIfLiquidatable(IIVXPortfolio portfolio) internal view {
        if (isPortfolioLiquidatable(portfolio)) {
            revert IIVXPortfolio.IVXPortfolio_PortfolioLiquidatable();
        }
    }
}
