pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Helper} from "../../helpers/Helper.sol";
import {DiemTradingTest} from "../../integration/DiemTradingTest.t.sol";
import {DecimalMath} from "../../../src/libraries/math/DecimalMath.sol";

import {IIVXLP} from "../../../src/interface/liquidity/IIVXLP.sol";
import {IVXLP} from "../../../src/liquidity/IVXLP.sol";
import {IIVXOracle} from "../../../src/interface/periphery/IIVXOracle.sol";
import {IIVXDiem} from "../../../src/interface/options/IIVXDiem.sol";
import {IIVXExchange} from "../../../src/interface/exchange/IIVXExchange.sol";
import {IIVXPortfolio} from "../../../src/interface/margin/IIVXPortfolio.sol";

import {GmxHedger} from "../../../src/exchange/gmx/v1/GmxHedger.sol";
import {IPositionRouter} from "../../../src/interface/exchange/gmx/v1/IPositionRouter.sol";
import {IRouter} from "../../../src/interface/exchange/gmx/v1/IRouter.sol";
import {IVault} from "../../../src/interface/exchange/gmx/v1/IVault.sol";

import {IERC20} from "../../../src/interface/IERC20.sol";

contract GmxCrossMarginTest is Helper {
    using DecimalMath for uint256;

    address usdc = collateral;
    address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address portfolioSender; //ALICE portfolio address
    IIVXPortfolio porftolio; //ALICE portfolio

    // function setUp() public {
    //     //set up exchange and margin contract for gmx

    //     deployRealDiem();
    //     exchange.setGMXContracts(router, positionRouter);

    //     //set up contract of margin portfolio
    //     vm.startPrank(ALICE);
    //     porftolio = RiskEngine.createMarginAccount();
    //     portfolioSender = address(porftolio);

    //     vm.deal(ALICE, 1 ether);
    //     //deposit margin
    //     uint amount = 10000 * 10 ** 6; // 10000 USDC to ALICE
    //     deal(usdc, ALICE, amount);
    //     IERC20(usdc).approve(address(porftolio), amount);
    //     porftolio.increaseMargin(usdc, amount);

    //     vm.stopPrank();
    // }

    // function executePendingIncrease(bytes32 key, address collat, address index) public {
    //     address payable sender = payable(ALICE);
    //     //execute the pending order with gmx keeper
    //     address admin = IPositionRouter(positionRouter).admin();
    //     vm.startPrank(admin);
    //     IPositionRouter(positionRouter).setPositionKeeper(ALICE, true); //set alice as position keeper
    //     vm.stopPrank();

    //     vm.startPrank(ALICE);
    //     IPositionRouter(positionRouter).executeIncreasePosition(key, sender);
    //     vm.stopPrank();

    //     bool pending = exchange.hasPendingPositionRequest(key);
    //     // console.log("pending", pending);
    //     assertFalse(pending, "should not have pending increase");

    //     IIVXExchange.CurrentPositions memory positions = exchange.getPositions(portfolioSender, collat, index);
    //     console.log("positions.amountOpen", positions.amountOpen);
    //     console.log("positions.isLong", positions.isLong);
    //     // if (positions.isLong) {
    //         console.log("positions.longPosition.size", positions.longPosition.size);
    //         console.log("positions.longPosition.collateral", positions.longPosition.collateral);
    //         console.log("positions.longPosition.averagePrice", positions.longPosition.averagePrice);
    //     // } else {
    //         console.log("positions.shortPosition.size", positions.shortPosition.size);
    //         console.log("positions.shortPosition.collateral", positions.shortPosition.collateral);
    //         console.log("positions.shortPosition.averagePrice", positions.shortPosition.averagePrice);
    //     // }
    // }

    // function test_ShortGmxWETH() public {
    //     uint slippage = 1.05 ether;
    //     uint leverageMultiplier = 5;
    //     uint amount = 10 * 1e6; // 10 USDC

    //     uint spot = oracle.getSpotPrice(weth).divideDecimalRound(slippage);
    //     console.log("spot", spot);

    //     uint executionFee = exchange.getExecutionFee();
    //     // console.log("executionFee", executionFee);
    //     // uint positionFee = exchange.getPositionFee(0, amount * 1e12 * leverageMultiplier, 0, weth);
    //     // console.log("positionFee", positionFee);
    //     // uint sizeDelta = amount * 1e12 * leverageMultiplier - positionFee;
    //     // console.log("sizeDelta", exchange.convertToGMXPrecision(sizeDelta));
    //     // amount += positionFee / 1e12;

    //     address[] memory path = new address[](1);
    //     path[0] = usdc;
    //     IIVXPortfolio.TradeDetails memory trade = IIVXPortfolio.TradeDetails({
    //         path: path,
    //         indexAsset: weth,
    //         collateralAsset: usdc,
    //         collateralDelta: amount,
    //         sizeDelta: 49751243781094526556003885312000,
    //         isLong: false,
    //         acceptableSpot: exchange.convertToGMXPrecision(spot)
    //     });

    //     console.log("trade.collateralDelta", trade.collateralDelta);
    //     console.log("trade.sizeDelta", trade.sizeDelta);
    //     console.log("trade.acceptableSpot", trade.acceptableSpot);

    //     vm.startPrank(ALICE);
    //     bytes32 key = porftolio.increasePosition{value: executionFee}(trade);
    //     vm.stopPrank();

    //     bool pending = exchange.hasPendingPositionRequest(key);
    //     assertTrue(pending, "should have pending position request");

    //     executePendingIncrease(key, usdc, weth);

    //     //check the position
    //     IIVXExchange.CurrentPositions memory positions = exchange.getPositions(portfolioSender, usdc, weth);
    //     console.log("positions.amountOpen", positions.amountOpen);
    //     console.log("positions.isLong", positions.isLong);
    //     // if (positions.isLong) {
    //         console.log("positions.longPosition.size", positions.longPosition.size);
    //         console.log("positions.longPosition.collateral", positions.longPosition.collateral);
    //         console.log("positions.longPosition.averagePrice", positions.longPosition.averagePrice);
    //     // } else {
    //         console.log("positions.shortPosition.size", positions.shortPosition.size);
    //         console.log("positions.shortPosition.collateral", positions.shortPosition.collateral);
    //         console.log("positions.shortPosition.averagePrice", positions.shortPosition.averagePrice);
    //     // }

    //     //check all value
    //     uint value =  exchange.getAllPositionsValue(portfolioSender, usdc, weth);
    //     console.log("value", value); //9.95$ USDC

    // }
}
