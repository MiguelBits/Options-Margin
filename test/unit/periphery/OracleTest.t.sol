pragma solidity ^0.8.18;

//HELPERS
import "forge-std/Test.sol";
import "../../helpers/Helper.sol";

//INTERFACES
import {IAggregatorV3} from "../../../src/interface/IAggregatorV3.sol";
import {IIVXOracle} from "../../../src/interface/periphery/IIVXOracle.sol";
import {IDecimals} from "../../interface/IDecimals.sol";

//PROTOCOL CONTRACTS
import {IVXOracle} from "../../../src/periphery/IVXOracle.sol";

contract OracleTest is Helper {
    function setUpTest() public {
        deployTestOracle();
    }

    function setUpReal() public {
        deployRealOracle();
    }

    function test_getSpotPriceRevertUnsupportedAsset() public {
        setUpTest();
        vm.expectRevert(abi.encodeWithSelector(IIVXOracle.UnsupportedOracleAsset.selector, address(0)));
        oracle.getSpotPrice(address(0));
    }

    function test_getSpotPrice() public {
        setUpTest();
        address _asset = address(mockupWETH);
        // console.log("Sequencer answer", uint256(mockupSequencer.answer()));
        // console.log("Aggregator answer", uint256(mockupAggregatorV3.answer()));
        uint256 answer = uint256(mockupAssetAggregatorV3.answer());
        uint256 spotPrice = oracle.getSpotPrice(_asset);
        // console.log("Spot price", spotPrice);
        assertTrue(spotPrice == answer);
    }

    function test_SpotPriceDecimalsBelow18Decimals() public {
        setUpTest();
        address _asset = address(mockupERC20);

        // uint256 answer = uint256(mockupDollarAggregatorV3.answer());
        uint256 spotPrice = oracle.getSpotPrice(_asset);
        // console.log("Spot price", spotPrice);
        // console.log("Answer    ", answer);
        assertTrue(spotPrice / 1e18 == 1);
    }

    function test_getSpotPriceAbove20Decimals() public {
        setUpTest();
        MockupERC20 mockup20Decimals = new MockupERC20("Nothing",20);
        MockupAggregatorV3 mockupAsset20Decimals = new MockupAggregatorV3(
            20, //decimals
            "NoName", //description
            1, //version
            0, //roundId
            1500 * 1e20, //answer
            0, //startedAt
            0, //updatedAt
            0 //answeredInRound
        );
        address _asset = address(mockup20Decimals);
        oracle.addAssetPriceFeed(_asset, address(mockupAsset20Decimals));
        uint256 answer = uint256(mockupAsset20Decimals.answer());
        uint256 spotPrice = oracle.getSpotPrice(_asset);
        // console.log("Spot price", spotPrice);
        // console.log("Answer    ", answer);
        assertTrue(spotPrice == answer / 10 ** 2); //lost 2 decimals because of 20-18 decimals difference
    }

    function test_setValues() public {
        setUpTest();
        // console.log(
        // ">> Should correctly set the values of the oracle"
        // );

        address _asset = address(mockupWETH);

        (uint256 initialBeta, uint256 initialAlpha) = oracle.assetData(_asset);
        uint256 initialVolatilityIndex = oracle.assetStrikeVols(_asset, 1500 ether);

        /// Check that the initial values default to 0
        assertEq(initialVolatilityIndex, 0);
        assertEq(initialBeta, 0);
        assertEq(initialAlpha, 0);

        oracle.setStrikeVolatility(_asset, 1500 ether, 100);
        /// Push an update to the oracle
        oracle.setValues(_asset, IIVXOracle.EncodedData({beta: 200, alpha: 300}));

        (uint256 beta, uint256 alpha) = oracle.assetData(_asset);
        uint256 volatilityIndex = oracle.assetStrikeVols(_asset, 1500 ether);
        /// Check that the values have been updated
        assertEq(volatilityIndex, 100);
        assertEq(beta, 200);
        assertEq(alpha, 300);

        /// Push a second update to the oracle
        oracle.setValues(_asset, IIVXOracle.EncodedData({beta: 300, alpha: 400}));

        (beta, alpha) = oracle.assetData(_asset);
        oracle.setStrikeVolatility(_asset, 1500 ether, 200);
        volatilityIndex = oracle.assetStrikeVols(_asset, 1500 ether);

        /// Check that the values have been updated
        assertEq(volatilityIndex, 200);
        assertEq(beta, 300);
        assertEq(alpha, 400);
    }

    function test_getRiskFreeRate() public {
        setUpTest();
        address _asset = address(mockupWETH);
        oracle.setRiskFreeRate(_asset, 100);
        int256 riskFreeRate = oracle.getRiskFreeRate(_asset);
        // console.log("Risk free rate", riskFreeRate);
        assertTrue(riskFreeRate == 100);
    }

    function test_getVolatility_ExpectRevert() public {
        setUpTest();
        // console.log(
        // ">> Should correctly calculate the volatility from the oracle"
        // );

        address _asset = address(mockupWETH);

        oracle.setRiskFreeRate(_asset, 1000000000000000000);

        vm.expectRevert(abi.encodeWithSelector(IIVXOracle.UnsupportedOracleVolatility.selector, _asset, 1500 ether));
        oracle.getVolatility(_asset, 1500 ether);
    }

    function test_Volatility() public {
        setUpTest();
        address _asset = address(mockupWETH);
        uint256 _strike = 1500 ether;

        IIVXOracle.EncodedData memory decodedData = IIVXOracle.EncodedData({beta: 1e18, alpha: 100000000000000000});

        oracle.setValues(_asset, decodedData);
        oracle.setStrikeVolatility(_asset, _strike, 650000000000000000);
        oracle.setRiskFreeRate(_asset, 1000000000000000000);
        (uint256 Vol) = oracle.getVolatility(_asset, _strike);
        console.log("vol", Vol);
    }

    function test_getAmountPriced() public {
        setUpTest();
        address _asset = address(mockupWETH);
        uint256 price = oracle.getSpotPrice(_asset);
        // console.log("Price        ", price);

        // console.log("10", 10 ** 18); this is
        // console.log("1 ", 1e18);     the same

        uint256 desiredPricedAmount = 2 ether / 1e18 * price;
        // console.log("Desired priced amount", desiredPricedAmount);

        uint256 pricedAmount = oracle.getAmountPriced(2 ether, _asset);
        // console.log("Priced amount", pricedAmount);

        assertTrue(pricedAmount == desiredPricedAmount);
    }

    function test_getAmountInAssetEth() public {
        setUpTest();
        address _asset = address(mockupWETH);
        uint256 price = oracle.getSpotPrice(_asset);
        console.log("Price        ", price);

        uint256 pricedAmount = 2 ether / 1e18 * price;
        uint256 desiredAmountInAsset = 2 ether;
        console.log("Desired amount in asset", desiredAmountInAsset);

        uint256 amountInAsset = oracle.getAmountInAsset(pricedAmount, _asset);
        console.log("Amount in asset", amountInAsset);

        assertTrue(amountInAsset == desiredAmountInAsset);
    }

    function test_getAmountInAssetDollar() public {
        setUpTest();
        address _asset = address(mockupERC20);
        uint256 price = oracle.getSpotPrice(_asset);
        console.log("Price                  ", price);

        uint256 pricedAmount = 2 * price;
        uint256 desiredAmountInAsset = 2 * dollar;
        console.log("Desired amount in asset", desiredAmountInAsset);

        uint256 amountInAsset = oracle.getAmountInAsset(pricedAmount, _asset);
        console.log("Amount in asset        ", amountInAsset);

        assertTrue(amountInAsset == desiredAmountInAsset);
    }

    function test_Fork_getAmountPricedEth() public {
        setUpReal();
        address _asset = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        uint256 price = oracle.getSpotPrice(_asset);
        console.log("Price                ", price);

        uint256 desiredPricedAmount = 2 * price;
        console.log("Desired priced amount", desiredPricedAmount);

        uint256 _amount = 2 * 10 ** IDecimals(_asset).decimals();
        console.log("Amount               ", _amount);

        uint256 pricedAmount = oracle.getAmountPriced(_amount, _asset); //2000 dollars
        console.log("Priced amount        ", pricedAmount);

        assertTrue(pricedAmount == desiredPricedAmount, "Priced amount is not correct");
    }

    function test_Fork_getAmountPricedBtc() public {
        setUpReal();
        address _asset = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // BTC
        uint256 price = oracle.getSpotPrice(_asset);
        console.log("Price                ", price);

        uint256 desiredPricedAmount = 2 * price;
        console.log("Desired priced amount", desiredPricedAmount);

        uint256 _amount = 2 * 10 ** IDecimals(_asset).decimals();
        console.log("Amount               ", _amount);

        uint256 pricedAmount = oracle.getAmountPriced(_amount, _asset); //2000 dollars
        console.log("Priced amount        ", pricedAmount);

        assertTrue(pricedAmount == desiredPricedAmount, "Priced amount is not correct");
    }

    function test_Fork_getAmountInAssetEth() public {
        setUpReal();
        address _asset = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        uint256 price = oracle.getSpotPrice(_asset);
        console.log("Price                  ", price);

        uint256 pricedAmount = 2 * price;
        uint256 desiredAmountInAsset = 2 * 10 ** IDecimals(_asset).decimals();
        console.log("Desired amount in asset", desiredAmountInAsset);

        uint256 amountInAsset = oracle.getAmountInAsset(pricedAmount, _asset);
        console.log("Amount in asset        ", amountInAsset);

        assertTrue(amountInAsset == desiredAmountInAsset);
    }

    function test_Fork_getAmountInAssetBtc() public {
        setUpReal();
        address _asset = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // BTC
        uint256 price = oracle.getSpotPrice(_asset);
        console.log("Price                  ", price);

        uint256 pricedAmount = 2 * price;
        uint256 desiredAmountInAsset = 2 * 10 ** IDecimals(_asset).decimals();
        console.log("Desired amount in asset", desiredAmountInAsset);

        uint256 amountInAsset = oracle.getAmountInAsset(pricedAmount, _asset);
        console.log("Amount in asset        ", amountInAsset);

        assertTrue(amountInAsset == desiredAmountInAsset);
    }

    function test_Fork_getPriceAtTime() public {
        setUpReal();
        uint256 time = 1692911164;
        console.log("Time", time);
        vm.warp(time + 1 days);
        address _asset = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        uint256 price = oracle.getSpotPriceAtTime(_asset, time);
        console.log("Price", price);
        assertTrue(1651763100000000000000 == price, "Price is not correct");
    }
}
