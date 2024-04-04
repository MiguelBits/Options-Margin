pragma solidity ^0.8.0;

import "forge-std/Test.sol";

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
import {IIVXOracle} from "../src/interface/periphery/IIVXOracle.sol";
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

// forge script DeployIVX_Testnet --broadcast --private-key $PRIVATE_KEY --rpc-url $GOERLI_ARB --skip-simulation --gas-estimate-multiplier 200 --slow
contract DeployIVX_Testnet is Helper {

    function run() public {
        address admin = 0x82616812FE8f2985316688d1f0f0cC2C87a27b68;

        vm.startBroadcast();

        console.log("admin: %s", admin);

        deployTestDiem();
        queue.setEpochDuration(10 days);       

        vm.stopBroadcast();
    }
}
