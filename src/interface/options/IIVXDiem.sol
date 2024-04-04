// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IIVXDiemToken} from "./IIVXDiemToken.sol";
import {IIVXPortfolio} from "../margin/IIVXPortfolio.sol";

interface IIVXDiem {
    struct TradeInfo {
        uint256 optionID;
        uint256 amountContracts; //number of contracts to open
    }

    struct Trade {
        uint256 timestamp; //last increased/decreased time
        uint256 optionID;
        uint256 contractsOpen; //number of contracts open
        uint256 averageEntry; //average premium price paid on all contracts
        uint256 borrowedAmount; //amount of collateral borrowed, used to calculate borrowing fees only
    }

    struct Pnl_Premiums_Greeks {
        int256 PNL;
        uint256 premiumValue;
        int256 delta;
        uint256 vega;
        uint256 totalFee;
    }

    struct FeeDistribution {
        uint256 treasuryFee;
        uint256 stakerFee;
        uint256 lpFee;
    }

    function OptionToken() external view returns (IIVXDiemToken);
    function isPortfolioLiquidatable(IIVXPortfolio portfolio) external view returns (bool);
    // function TradesNetValue(IIVXPortfolio portfolio) external view returns (int256 netValue);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event StakerChanged (address indexed staker);

    event TreasuryChanged(address indexed treasury);

    event MaxBatchTradingChanged(uint256 maxBatchTrading);

    event LiqBonusPercentChanged(uint256 liqBonusPercent);

    event TradeOpened(Trade trade, address indexed account);

    event TradeIncreased(Trade trade, address indexed account);

    event TradeClosed(Trade trade, address indexed account);

    event TradeDecreased(Trade trade, address indexed account);

    event Liquidated(address indexed account, address liquidator, int256 pnl);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error AddressZero();
    error InvalidTradeArray();
    error InvalidTrade();
    error IVX_NoPortfolioContractCreated();
    error IVX_OptionNotSettled();
    error IVX_CannotCloseMoreThanOpenContracts();
    error IVX_PortfolioNotLiquidatable();
    error IVX_NotLiquidatedProperly();
    error InvalidFeeDistribution();
}
