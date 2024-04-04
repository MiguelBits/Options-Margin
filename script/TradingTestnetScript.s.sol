pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

//PROTOCOL CONTRACTS
import {IVXLP} from "../src/liquidity/IVXLP.sol";
import {IVXQueue} from "../src/liquidity/IVXQueue.sol";
import {IVXOracle} from "../src/periphery/IVXOracle.sol";
import {IVXDiem} from "../src/options/IVXDiem.sol";
import {IVXRiskEngine} from "../src/margin/IVXRiskEngine.sol";
import {IVXPortfolio} from "../src/margin/IVXPortfolio.sol";
import {IVXDiemToken} from "../src/options/IVXDiemToken.sol";
import {IVXExchange} from "../src/exchange/IVXExchange.sol";

//INTERFACES
import {IIVXOracle, IAggregatorV3} from "../src/interface/periphery/IIVXOracle.sol";
import {IIVXLP} from "../src/interface/liquidity/IIVXLP.sol";
import {IIVXRiskEngine} from "../src/interface/margin/IIVXRiskEngine.sol";
import {IIVXPortfolio} from "../src/interface/margin/IIVXPortfolio.sol";
import {IIVXDiem} from "../src/interface/options/IIVXDiem.sol";
import {IIVXDiemToken} from "../src/interface/options/IIVXDiemToken.sol";
import {IIVXExchange} from "../src/interface/exchange/IIVXExchange.sol";
//UTILS
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {WETH} from "@solmate/tokens/WETH.sol";
import {MockupERC20} from "../test/mocks/MockupERC20.sol";
import {MockupAggregatorV3} from "../test/mocks/MockupAggregatorV3.sol";
import {MockupSequencerV3} from "../test/mocks/MockupSequencerV3.sol";
import {Helper} from "../test/helpers/Helper.sol";

// forge script TestnetTradingScript --broadcast --private-key $PRIVATE_KEY --rpc-url $GOERLI_ARB

contract TestnetTradingScript is Script, Helper{
    //PROTOCOL CONTRACTS
//   mockupERC20 usdc address 0x0Dac9D3cadF936Da7B487422c54DACC1dc6c3405
//   mockupWETH address 0x3314F660755fF9900C9AC4dc1a78D88Df12fC930
//   oracle address 0x6EAD6EA9bDf0ebf54E657f232081A17034e56536
//   usdcOracle usdc address 0x1692Bdd32F31b831caAc1b0c9fAF68613682813b
//   lp address 0x65F53c4b233F5955fC35412c47E7924F8e3A2f8A
//   queue address 0xbF4912C43F688bBA39D82237de595AaDf38f3a89
//   RiskEngine address 0xc680F5430AfD472e39c7b179C49446802BEd5Ac5
//   option token 0xe73e6707b6555F49143A8e63B5C641f2F7f6349C
//   diem address 0xc502333a1F82C5f6c62eb4d7D93b3CDFBff14232
//   Btc asset 0xd3D2E828222e356EdbdfCb954E5e2a55900D023E
//   Trader: 0x82616812FE8f2985316688d1f0f0cC2C87a27b68

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function tradeOptionScript(uint256 nContracts) public{

        uint256 _amount = 100000 * 1e6;

        mockupERC20.mint(trader, _amount);
        mockupERC20.mint(address(lp), _amount);
        IIVXPortfolio _new = RiskEngine.userIVXPortfolio(trader);
        mockupERC20.approve(address(_new), _amount);
        addMargin(_new, address(mockupERC20), _amount);

        console.log("open trade id 1-5: 1-5 contracts");
        IIVXDiem.TradeInfo[] memory trades = new IIVXDiem.TradeInfo[](4);
        trades[0] = IIVXDiem.TradeInfo({optionID: 1, amountContracts: 1 * nContracts});
        trades[1] = IIVXDiem.TradeInfo({optionID: 2, amountContracts: 2 * nContracts});
        trades[2] = IIVXDiem.TradeInfo({optionID: 3, amountContracts: 3 * nContracts});
        trades[3] = IIVXDiem.TradeInfo({optionID: 4, amountContracts: 4 * nContracts});
        // trades[4] = IIVXDiem.TradeInfo({optionID: 5, amountContracts: 5 * nContracts});

        // diem.openTrades(trades);

        // console.log("open trade id 6-10: 6-10 contracts");
        // trades = new IIVXDiem.TradeInfo[](5);
        // trades[0] = IIVXDiem.TradeInfo({optionID: 6, amountContracts: 6 * nContracts});
        // trades[1] = IIVXDiem.TradeInfo({optionID: 7, amountContracts: 7 * nContracts});
        // trades[2] = IIVXDiem.TradeInfo({optionID: 8, amountContracts: 8 * nContracts});
        // trades[3] = IIVXDiem.TradeInfo({optionID: 9, amountContracts: 9 * nContracts});
        // trades[4] = IIVXDiem.TradeInfo({optionID: 10, amountContracts: 10 * nContracts});

        diem.openTrades(trades);

        // console.log("open trade id 11-15: 11-15 contracts");
        // trades = new IIVXDiem.TradeInfo[](5);
        // trades[0] = IIVXDiem.TradeInfo({optionID: 11, amountContracts: 11 * nContracts});
        // trades[1] = IIVXDiem.TradeInfo({optionID: 12, amountContracts: 12 * nContracts});
        // trades[2] = IIVXDiem.TradeInfo({optionID: 13, amountContracts: 13 * nContracts});
        // trades[3] = IIVXDiem.TradeInfo({optionID: 14, amountContracts: 14 * nContracts});
        // trades[4] = IIVXDiem.TradeInfo({optionID: 15, amountContracts: 15 * nContracts});

        // diem.openTrades(trades);

        // console.log("open trade id 16: 5 contracts");
        // trades = new IIVXDiem.TradeInfo[](1);
        // trades[0] = IIVXDiem.TradeInfo({optionID: 16, amountContracts: 5 * nContracts});
        // diem.openTrades(trades);
    }

    function closeOptionScript(uint256 nContracts) public{
        uint256 _amount = 100000 * 1e6;

        mockupERC20.mint(trader, _amount);
        IIVXPortfolio _new = RiskEngine.userIVXPortfolio(trader);
        mockupERC20.approve(address(_new), _amount);
        addMargin(_new, address(mockupERC20), _amount);

        console.log("close trade id 1-5: 1-5 contracts");
        IIVXDiem.TradeInfo[] memory trades = new IIVXDiem.TradeInfo[](5);
        trades[0] = IIVXDiem.TradeInfo({optionID: 1, amountContracts: 1 * nContracts});
        trades[1] = IIVXDiem.TradeInfo({optionID: 2, amountContracts: 2 * nContracts});
        trades[2] = IIVXDiem.TradeInfo({optionID: 3, amountContracts: 3 * nContracts});
        trades[3] = IIVXDiem.TradeInfo({optionID: 4, amountContracts: 4 * nContracts});
        trades[4] = IIVXDiem.TradeInfo({optionID: 5, amountContracts: 5 * nContracts});
        diem.closeTrades(trades);

        console.log("close trade id 6-10: 6-10 contracts");
        trades = new IIVXDiem.TradeInfo[](5);
        trades[0] = IIVXDiem.TradeInfo({optionID: 6, amountContracts: 6 * nContracts});
        trades[1] = IIVXDiem.TradeInfo({optionID: 7, amountContracts: 7 * nContracts});
        trades[2] = IIVXDiem.TradeInfo({optionID: 8, amountContracts: 8 * nContracts});
        trades[3] = IIVXDiem.TradeInfo({optionID: 9, amountContracts: 9 * nContracts});
        trades[4] = IIVXDiem.TradeInfo({optionID: 10, amountContracts: 10 * nContracts});
        diem.closeTrades(trades);

        console.log("close trade id 11-15: 11-15 contracts");
        trades = new IIVXDiem.TradeInfo[](5);
        trades[0] = IIVXDiem.TradeInfo({optionID: 11, amountContracts: 11 * nContracts});
        trades[1] = IIVXDiem.TradeInfo({optionID: 12, amountContracts: 12 * nContracts});
        trades[2] = IIVXDiem.TradeInfo({optionID: 13, amountContracts: 13 * nContracts});
        trades[3] = IIVXDiem.TradeInfo({optionID: 14, amountContracts: 14 * nContracts});
        trades[4] = IIVXDiem.TradeInfo({optionID: 15, amountContracts: 15 * nContracts});
        diem.closeTrades(trades);

        console.log("close trade id 16: 5 contracts");
        trades = new IIVXDiem.TradeInfo[](1);
        trades[0] = IIVXDiem.TradeInfo({optionID: 16, amountContracts: 5 * nContracts});

        diem.closeTrades(trades);
    }

    function run() public {
        vm.startBroadcast();

        deployTestDiem(30 days);
        createOptionScript();
        tradeOptionScript(1 ether);
        // closeOptionScript(5 ether);

        console.log("portfolio net value");
        console.logInt(diem.calculatePortfolioNetValue(RiskEngine.userIVXPortfolio(trader)));

        vm.stopBroadcast();
    }

}