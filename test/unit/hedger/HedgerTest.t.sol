pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Helper} from "../../helpers/Helper.sol";
import {DiemTest} from "../options/DiemTest.t.sol";

import {IVXLP} from "../../../src/liquidity/IVXLP.sol";
import {IIVXOracle} from "../../../src/interface/periphery/IIVXOracle.sol";
import {IIVXDiem} from "../../../src/interface/options/IIVXDiem.sol";

contract HedgerTest is DiemTest {
    function setUpTrade() public {
        test_openTrade_BuyCall();
    }

    function test_deltaExposure() public {
        setUpTrade();

        int256 delta = lp.deltaExposure(weth);
        if (delta > 0) {
            console.log("+delta", uint256(delta));
        } else {
            console.log("-delta", uint256(delta * -1));
        }

        assertTrue(delta > 0, "delta should be positive");
    }
}
