pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Helper} from "../../helpers/Helper.sol";
import {DiemTradingTest} from "../../integration/DiemTradingTest.t.sol";

import {IIVXLP} from "../../../src/interface/liquidity/IIVXLP.sol";
import {IVXLP} from "../../../src/liquidity/IVXLP.sol";
import {IIVXOracle} from "../../../src/interface/periphery/IIVXOracle.sol";
import {IIVXDiem} from "../../../src/interface/options/IIVXDiem.sol";

import {GmxHedger, IIVXHedger} from "../../../src/exchange/gmx/v1/GmxHedger.sol";
import {IPositionRouter} from "../../../src/interface/exchange/gmx/v1/IPositionRouter.sol";
import {IRouter} from "../../../src/interface/exchange/gmx/v1/IRouter.sol";

contract GmxHedgerTest is DiemTradingTest {
    GmxHedger gmxHedger;

    function logDeltaExposure() public view {
        int256 currentDelta = lp.deltaExposure(weth);
        currentDelta > 0 ? console.log("+delta", uint256(currentDelta)) : console.log("-delta", uint256(-currentDelta));
    }

    function setUpHedger() public {
        gmxHedger = new GmxHedger();
        gmxHedger.init(
            IIVXLP(address(lp)), IIVXOracle(address(oracle)), IPositionRouter(positionRouter), IRouter(address(router))
        );

        gmxHedger.setHedgerParams(
            IIVXHedger.HedgerParameters({
                interactionDelay: 1 hours,
                hedgeCap: 10 ether,
                acceptableSpotSlippage: 1.05 ether,
                deltaThreshold: 100 ether,
                targetLeverage: 1.1 ether
            })
        );

        lp.setHedger(address(gmxHedger));

        deal(usdc, address(lp), 10000 * 10 ** 6); // 10000 USDC to LP

        // logDeltaExposure();
    }

    function _hedgeWETH() internal {
        // test_Trades();
        // logDeltaExposure();
        vm.deal(msg.sender, 1 ether);

        //interact with hedger before interaction delay expires; should revert
        // vm.expectRevert(abi.encodeWithSelector(GmxHedger.InteractionDelayNotExpired.selector));
        gmxHedger.hedgeDelta{value: 0.1 ether}(weth);

        bool pending = gmxHedger._hasPendingIncrease(weth);
        assertTrue(pending, "should have pending increase");

        //execute the pending order with gmx keeper
        address admin = IPositionRouter(positionRouter).admin();
        vm.startPrank(admin);
        IPositionRouter(positionRouter).setPositionKeeper(ALICE, true); //set alice as position keeper
        vm.stopPrank();

        bytes32 key = gmxHedger.pendingOrderKey(weth);
        address payable sender = payable(ALICE);
        vm.startPrank(ALICE);
        IPositionRouter(positionRouter).executeIncreasePosition(key, sender);
        vm.stopPrank();
    }

    function _executeGMXIncrease() internal {
        address admin = IPositionRouter(positionRouter).admin();
        vm.startPrank(admin);
        IPositionRouter(positionRouter).setPositionKeeper(ALICE, true); //set alice as position keeper
        vm.stopPrank();
        bytes32 key = gmxHedger.pendingOrderKey(weth);
        address payable sender = payable(ALICE);
        vm.startPrank(ALICE);
        IPositionRouter(positionRouter).executeIncreasePosition(key, sender);
        vm.stopPrank();

        bool pending = gmxHedger._hasPendingIncrease(weth);
        // console.log("pending", pending);
        assertFalse(pending, "should not have pending increase");
    }

    function test_HedgeWETH() public {
        setUpHedger();
        test_Trades();
        logDeltaExposure();
        vm.deal(msg.sender, 1 ether);
        gmxHedger.hedgeDelta{value: 0.1 ether}(weth);

        _executeGMXIncrease();

        GmxHedger.CurrentPositions memory positions = gmxHedger._getPositions(weth);
        console.log("positions.amountOpen", positions.amountOpen);
        console.log("positions.isLong", positions.isLong);
        // if (positions.isLong) {
        console.log("positions.longPosition.size", positions.longPosition.size);
        console.log("positions.longPosition.collateral", positions.longPosition.collateral);
        console.log("positions.longPosition.averagePrice", positions.longPosition.averagePrice);
        // } else {
        console.log("positions.shortPosition.size", positions.shortPosition.size);
        console.log("positions.shortPosition.collateral", positions.shortPosition.collateral);
        console.log("positions.shortPosition.averagePrice", positions.shortPosition.averagePrice);
        // }

        //open more positions and hedge again
        // _hedgeWETH();

        //wait for interaction delay to expire
        // vm.warp(block.timestamp + 1 hours);
        // gmxHedger.hedgeDelta{value: 0.1 ether}(weth);
    }

    function test_getTotalHedgingLiquidityWETH() public {
        test_HedgeWETH();
        uint256 totalLiq = gmxHedger.getTotalHedgingLiquidity(weth);
        console.log("totalLiq", totalLiq);
    }

    function test_LPUtilizationRation() public {
        test_HedgeWETH();
        uint256 ratio = lp.utilizationRatio();
        console.log("ratio", ratio);
    }

    function test_InterestRate() public {
        test_HedgeWETH();
        uint256 rate = lp.interestRate();
        console.log("rate", rate);
    }

    receive() external payable {
        // console.log("receive", msg.value);
    }
    fallback() external payable {
        // console.log("fallback", msg.value);
    }
}
