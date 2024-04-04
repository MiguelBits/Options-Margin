pragma solidity ^0.8.18;

//HELPERS
import "forge-std/Test.sol";
import {Helper} from "../helpers/Helper.sol";
import {TestnetTradingScript} from "../../script/TradingTestnetScript.s.sol";

//PROTOCOL CONTRACTS
import {IVXLP} from "../../src/liquidity/IVXLP.sol";
import {IVXQueue} from "../../src/liquidity/IVXQueue.sol";
import {IVXOracle} from "../../src/periphery/IVXOracle.sol";
import {IVXRiskEngine} from "../../src/margin/IVXRiskEngine.sol";
import {IVXDiem} from "../../src/options/IVXDiem.sol";
import {Binomial} from "../../src/libraries/Binomial.sol";
import {IVXExchange} from "../../src/exchange/IVXExchange.sol";

//INTERFACES
import {IIVXOracle} from "../../src/interface/periphery/IIVXOracle.sol";
import {IIVXDiem} from "../../src/interface/options/IIVXDiem.sol";
import {IERC20} from "../../src/interface/IERC20.sol";
import {IWETH} from "../interface/IWETH.sol";
import {IIVXDiemToken} from "../../src/interface/options/IIVXDiemToken.sol";
import {IIVXPortfolio} from "../../src/interface/margin/IIVXPortfolio.sol";
import {IIVXRiskEngine} from "../../src/interface/margin/IIVXRiskEngine.sol";

contract ScriptTest is TestnetTradingScript {
    
    // function setUp() public {
    //     vm.createSelectFork(vm.envString("GOERLI_ARB"));
    //     // deployTestDiem();
    // }

    // function testDeployment() public {
    //     vm.startPrank(trader);
    //     deployTestDiem();
    //     createOptionScript();
    //     tradeOptionScript(1 ether);

    //     vm.stopPrank();
    // }

    // function testCreateOptionsScript() public {
    //     vm.startPrank(trader);
    //     createOptionScript();
    //     vm.stopPrank();
    // }

    // function testTradeOptionsScript() public {
    //     vm.startPrank(trader);
    //     tradeOptionScript(1 ether);
    //     vm.stopPrank();
    // }

    // function testUtilizationRatioScript() public {
    //     //log nav
    //     console.log("NAV", lp.NAV());
    //     uint256 ratio = lp.utilizationRatio();
    //     console.log("utilizationRatio", ratio);
    // }

    // function testOpenTrades() public {
    //     IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(trader);
    //     uint256[] memory ids = portfolio.getOpenOptionIds();
    //     console.log("openOptionIds", ids.length);
    //     for (uint256 i = 0; i < ids.length; i++) {
    //         console.log("openOptionId", ids[i]);
    //         IIVXDiem.Trade memory trade = portfolio.getOptionIdTrade(ids[i]);
    //         console.log("trading ", trade.contractsOpen);
    //     }
    // }
}