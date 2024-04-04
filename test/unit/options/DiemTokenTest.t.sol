pragma solidity ^0.8.18;

//HELPERS
import "forge-std/Test.sol";
import {Helper, IIVXOracle, IIVXRiskEngine, MockupAggregatorV3, MockupERC20} from "../../helpers/Helper.sol";
import {IIVXDiemToken} from "../../../src/interface/options/IIVXDiemToken.sol";
import {Binomial} from "../../../src/libraries/Binomial.sol";

//INTERFACES
import {IIVXDiemToken} from "../../../src/interface/options/IIVXDiemToken.sol";

contract DiemTokenTest is Helper {

    uint256 strike = 1510 ether;
    address weth;
    address usdc;

    function setUp() public {
        deployTestDiem();

        weth = address(mockupWETH);
        usdc = address(mockupERC20);

        optionToken.setParams(IIVXDiemToken.OptionTradingParams(0.05 ether, 3600, 1 days, 4 days, 0.01 ether)); //binomial: 1 day, blackScholes: 4 days
    }

    function test_calculatePremium() public {
        strike = 1520000000000000000000;

        //create option
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);

        // uint256 price = oracle.getSpotPrice(weth);
        // console.log("price: %s", price);

        (, uint256 singlePremium,,) = optionToken.calculateCosts(1, 0, false);
        console.log("singlePremium: %s", singlePremium);

        uint256 spot = oracle.getSpotPrice(weth);
        uint256 timeToExp = 1 days;
        uint256 vol = oracle.getVolatility(weth, strike);
        int256 rate = oracle.getRiskFreeRate(weth);
        uint256 deltaT = timeToExp / 15;

        Binomial.PricingInputs memory inputs =
            Binomial.PricingInputs(timeToExp, vol, spot, strike, uint256(rate), deltaT);
        uint256 call = Binomial.callOptionPrices(inputs);
        console.log("call           %s", call);

        assertTrue(singlePremium == call, "premium is not what was expected");
    }

    function test_CreateOption() public {
        IIVXDiemToken.OptionAttributes memory p = createOption(100, 100, weth);
        // console.log("strikePrice: %s", strikePrice);
        // console.log("expiry: %s", expiry);
        // console.log("underlyingAsset: %s", underlyingAsset);
        assertTrue(p.option.strikePrice == 100, "strikePrice should be 100");
        assertTrue(p.option.expiry == 100, "expiry should be 100");
        assertTrue(p.option.underlyingAsset == address(weth), "underlyingAsset should be weth");
        // console.log("optionId: %s", optionToken.currentOptionId());
        assertTrue(optionToken.currentOptionId() == 4);
        //getOptionIDAttributes
        // 1 and 2 are the first two options created : true
        // 3 is the third option created : false
        // 4 is the fourth option created : false
        IIVXDiemToken.OptionAttributes memory ps = optionToken.getOptionIDAttributes(1); //BUY CALL
        // console.log("isCall: %s", ps.isCall);
        // console.log("isBuy: %s", ps.isBuy);
        assertTrue(ps.isCall == true, "should be call");
        assertTrue(ps.isBuy == true, "should be buy");

        ps = optionToken.getOptionIDAttributes(2); //SELL CALL
        // console.log("isCall: %s", ps.isCall);
        // console.log("isBuy: %s", ps.isBuy);
        assertTrue(ps.isCall == true, "should be call");
        assertTrue(ps.isBuy == false, "should be sell");

        ps = optionToken.getOptionIDAttributes(3); //BUY PUT
        // console.log("isCall: %s", ps.isCall);
        // console.log("isBuy: %s", ps.isBuy);
        assertTrue(ps.isCall == false, "should be put");
        assertTrue(ps.isBuy == true, "should be buy");

        ps = optionToken.getOptionIDAttributes(4); //SELL PUT
        // console.log("isCall: %s", ps.isCall);
        // console.log("isBuy: %s", ps.isBuy);
        assertTrue(ps.isCall == false, "should be put");
        assertTrue(ps.isBuy == false, "should be sell");

        bool found;
        address[] memory arrayAssets = optionToken.getUnderlyings();
        for (uint256 i; i < optionToken.getUnderlyings().length; ++i) {
            // console.log("asset", arrayAssets[i]);
            if (arrayAssets[i] == address(weth)) {
                found = true;
                break;
            } else {
                found = false;
            }
        }
        assertTrue(found == true, "asset is not in array");
    }

    function test_NotTradeable_TooFarOutOfMoney() public {
        createOption(200000 ether, block.timestamp + 1 days, weth);
        uint256 optionID = 1;
        vm.expectRevert(
            abi.encodeWithSelector(IIVXDiemToken.IVXOptionNotTradeable_DeltaCutoffReached.selector, optionID, 0)
        );
        optionToken.isTradeable(optionID);
    }

    function test_NotTradeable_TooMuchInMoney() public {
        createOption(1000 ether, block.timestamp + 1 days, weth);
        uint256 optionID = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IIVXDiemToken.IVXOptionNotTradeable_DeltaCutoffReached.selector, optionID, 1000000000000000000
            )
        );
        optionToken.isTradeable(optionID);
    }

    function test_Tradeable() public {
        createOption(1520 ether, block.timestamp + 1 days, weth);
        uint256 optionID = 1;
        optionToken.isTradeable(optionID);
    }

    function test_calculateCostsOpen() public {
        createOption(strike, block.timestamp + 1 days, weth);

        uint256 optionID = 1;
        uint256 amount = 5e18;
        uint256 fee;
        uint256 premium;

        console.log("strike", strike);
        console.log("volatility", oracle.getVolatility(address(mockupWETH), strike));
        vm.warp(block.timestamp + 6 hours);
        (fee, premium,,) = optionToken.calculateCosts(optionID, amount, false);
        console.log("fee", fee);
        console.log("premium", premium);
    }

    function test_calculateCostsClose() public {
        createOption(strike, block.timestamp + 1 days, weth);
        uint256 optionID = 1;
        uint256 amount = 5e18;
        uint256 fee;
        uint256 premium;

        console.log("strike", strike);
        console.log("volatility", oracle.getVolatility(address(mockupWETH), strike));
        vm.warp(block.timestamp + 6 hours);
        (fee, premium,,) = optionToken.calculateCosts(optionID, amount, true);
        console.log("fee", fee);
        console.log("premium", premium);
    }

    function test_Settlement() public {
        createOption(strike, block.timestamp + 1 days, weth);
        uint256 optionID = 4;

        vm.warp(block.timestamp + 25 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike - 100 ether));

        optionToken.settleOptionsExpired(optionID);

        uint256 currentId = optionToken.currentOptionId();
        uint256[] memory activeIds = optionToken.getUnderlying_ActiveOptions(weth);
        for (uint256 i; i < activeIds.length; ++i) {
            assertTrue(activeIds[i] != currentId, "id still in current active options");
        }

        //SELL PUT
        (uint256 fee, uint256 premium,,) = optionToken.calculateCosts(4, 1 ether, true);
        console.log("fee", fee);
        console.log("premium", premium);

        assertTrue(fee == 1 ether, "fee is not 1 sell put");
        assertTrue(premium == 100 ether, "premium is not 100 sell put");
        assertTrue(optionToken.getOptionIDAttributes(currentId).status.isSettled == true);
        assertTrue(optionToken.getOptionIDAttributes(currentId - 1).status.isSettled == true);
        assertTrue(optionToken.getOptionIDAttributes(currentId - 2).status.isSettled == true);
        assertTrue(optionToken.getOptionIDAttributes(currentId - 3).status.isSettled == true);
        assertTrue(
            optionToken.getOptionIDAttributes(currentId).status.settlementPayoff == 100 ether,
            "payoff not what was expected, sell put"
        );
    }

    function test_settlementPayoff() public {
        uint256 expiry = block.timestamp + 1 days;
        createOption(strike, expiry, weth);
        uint256 optionID = 1;
        uint256 amount = 1e18;
        uint256 fee;
        uint256 premium;

        console.log("strike", strike);
        console.log("volatility", oracle.getVolatility(address(mockupWETH), strike));
        vm.warp(expiry + 1 hours);
        mockupAssetAggregatorV3.setPrice(1550 ether);
        (fee, premium,,) = optionToken.calculateCosts(optionID, amount, true);
        assertTrue(premium == 40 ether, "payoff not expected value");
        // console.log("fee", fee);
        // console.log("premium", premium);
        uint256 expectedFee = (premium * amount / 1e18) * 0.01 ether / 1e18;
        // console.log("expectedFee", expectedFee);
        assertTrue(fee == expectedFee, "fee not what was expected");
    }

    function test_PremiumDollarDepeg() public {
        uint256 expiry = block.timestamp + 1 days;
        createOption(strike, expiry, weth);
        (uint256 fee1, uint256 premium1, , ) = optionToken.calculateCosts(1, 1e18, false);
        console.log("premium1", premium1);
        console.log("fee1", fee1);

        //depeg dollar oracle
        mockupDollarAggregatorV3.setPrice(9 * 1e5);

        (uint256 fee2, uint256 premium2, , ) = optionToken.calculateCosts(1, 1e18, false);
        console.log("premium2", premium2);
        console.log("fee2", fee2);

        assertTrue(premium2 > premium1, "premium should be higher");
        assertTrue(fee2 > fee1, "fee should be higher");
    }

    function test_MultipleAssetsOptions_getUnderlyings() public {
        uint256 expiry = block.timestamp + 1 days;
        createOption(strike, expiry, weth, false);

        //set shock loss
        createOption(strike, expiry, usdc, false);

        address[] memory arrayAssets = optionToken.getUnderlyings();
        for (uint256 i; i < optionToken.getUnderlyings().length; ++i) {
            console.log("asset", arrayAssets[i]);
        }

        address asset = optionToken.getOptionIDAttributes(1).option.underlyingAsset;
        assertTrue(asset == address(weth), "asset should be weth");
        asset = optionToken.getOptionIDAttributes(2).option.underlyingAsset;
        assertTrue(asset == address(weth), "asset should be weth");

        asset = optionToken.getOptionIDAttributes(5).option.underlyingAsset;
        assertTrue(asset == address(usdc), "asset should be usdc");
    }
}
