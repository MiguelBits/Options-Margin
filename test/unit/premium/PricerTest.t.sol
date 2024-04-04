// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

//HELPER
import "forge-std/Test.sol";

//LIBRARIES
import {IVXPricer} from "../../../src/libraries/IVXPricer.sol";
import {BlackScholes} from "../../../src/libraries/BlackScholes.sol";
import {MathLib} from "../../../src/libraries/math/MathLib.sol";
import "../../../src/libraries/math/Math.sol";

contract PricerTest is Test {
    uint256 private constant secondsInYear = 31536000;

    function setUp() public {
        // do nothing
    }

    function test_calculateBSPrices() public {
        // Set the test parameters
        uint256 timeToExp = 2 days;
        uint256 vol = 6500000000000000000;
        uint256 spot = 1500000000000000000000;
        uint256 strike = 2000000000000000000000;
        int256 rate = 50000000000000000;

        IVXPricer.PricingInputs memory inputs =
            IVXPricer.PricingInputs(IVXPricer.FetchedInputs(vol, spot, strike), timeToExp, rate, 0);
        (uint256 call, uint256 put) = IVXPricer.calculateBSPrices(inputs);
        console.log("call", call); //buy option
        console.log("put ", put); //sell option
    }

    function test_FuzzBlackScholesOptionPrices() public {
        // Set the test parameters
        uint256 timeToExp = 1 days; //86400
        uint256 vol = 650000000000000000;
        uint256 spot = 2000000000000000000000;
        // uint256 strike = 1700000000000000000000;
        int256 rate = 50000000000000000;
        uint256 deltaT = timeToExp / 7;

        for (uint256 strike = 1700000000000000000000; strike < 2600000000000000000000; strike += 20 ether) {
            IVXPricer.PricingInputs memory inputs =
                IVXPricer.PricingInputs(IVXPricer.FetchedInputs(vol, spot, strike), timeToExp, rate, deltaT);
            (uint256 call, uint256 put) = IVXPricer.calculateBSPrices(inputs);
            // console.log("strike", strike);
            // console.log("call", call);
            // console.log("put ", put);
        }
    }

    function test_FuzzBinomialOptionPrices() public {
        // Set the test parameters
        uint256 timeToExp = 6 hours; //86400
        uint256 vol = 650000000000000000;
        uint256 spot = 2000000000000000000000;
        // uint256 strike = 1700000000000000000000;
        int256 rate = 50000000000000000;
        uint256 deltaT = timeToExp / 15;

        for (uint256 strike = 1700000000000000000000; strike < 2600000000000000000000; strike += 20 ether) {
            IVXPricer.PricingInputs memory inputs =
                IVXPricer.PricingInputs(IVXPricer.FetchedInputs(vol, spot, strike), timeToExp, rate, deltaT);
            (uint256 call, uint256 put) = IVXPricer.calculateBinomialPrices(inputs);
            console.log("strike", strike);
            console.log("call", call);
            console.log("put ", put);
        }
    }

    function test_MixingCoefficient() public {
        // Set the test parameters
        uint256 timeToExp = 1 days; //86400
        uint256 vol = 650000000000000000;
        uint256 spot = 1000000000000000000000;
        uint256 strike = 2020000000000000000000;
        int256 rate = 50000000000000000;
        uint256 deltaT = timeToExp / 15;

        uint256 alpha = 1e18;

        IVXPricer.PricingInputs memory inputs =
            IVXPricer.PricingInputs(IVXPricer.FetchedInputs(vol, spot, strike), timeToExp, rate, deltaT);
        (uint256 call, uint256 put) = IVXPricer.calculateBSPrices(inputs);
        console.log("callBS", call); //buy option
        console.log(" putBS", put); //sell option

        (call, put) = IVXPricer.calculateBinomialPrices(inputs);
        console.log("callBN", call); //buy option
        console.log(" putBN", put); //sell option

        IVXPricer.OptionPricing memory pricer = IVXPricer.OptionPricing(inputs, alpha);
        (call, put) = IVXPricer.optionPricing(pricer);
        console.log("callMX", call); //buy option
        console.log(" putMX", put); //sell option
    }

    function test_AlphaCalculations() public {
        // Set the test parameters
        uint256 timeToExp = 2 days;
        uint256 vol = 650000000000000000;
        uint256 spot = 1000000000000000000000;
        uint256 strike = 1020000000000000000000;
        int256 rate = 50000000000000000;
        uint256 deltaT = timeToExp / 15;

        console.log("Seconds to expire", timeToExp);
        uint256 alpha = IVXPricer.calculateAlpha(timeToExp, 1 days, 4 days);
        console.log("alpha", alpha);

        IVXPricer.PricingInputs memory inputs =
            IVXPricer.PricingInputs(IVXPricer.FetchedInputs(vol, spot, strike), timeToExp, rate, deltaT);
        (uint256 call, uint256 put) = IVXPricer.calculateBSPrices(inputs);
        console.log("callBS", call); //buy option
        console.log(" putBS", put); //sell option

        (call, put) = IVXPricer.calculateBinomialPrices(inputs);
        console.log("callBN", call); //buy option
        console.log(" putBN", put); //sell option

        IVXPricer.OptionPricing memory pricer = IVXPricer.OptionPricing(inputs, alpha);
        (call, put) = IVXPricer.optionPricing(pricer);
        console.log("callMX", call); //buy option
        console.log(" putMX", put); //sell option
    }

    function test_vega() public {
        // Set the test parameters
        uint256 timeToExp = 2 days;
        uint256 vol = 650000000000000000;
        uint256 spot = 1000000000000000000000;
        uint256 strike = 1020000000000000000000;
        int256 rate = 50000000000000000;

        console.log("Seconds to expire", timeToExp);
        uint256 alpha = IVXPricer.calculateAlpha(timeToExp, 1 days, 4 days);
        console.log("alpha", alpha);

        IVXPricer.PricingInputs memory inputs =
            IVXPricer.PricingInputs(IVXPricer.FetchedInputs(vol, spot, strike), timeToExp, rate, 0);
        (uint256 call, uint256 put) = IVXPricer.calculateBSPrices(inputs);
        console.log("callBS", call); //buy option
        console.log(" putBS", put); //sell option

        uint256 vega = IVXPricer.vega(inputs);
        console.log("vega", vega);
    }

    // function test_calculateIVXPricingVega() public view {
    //     // Set the test parameters
    //     uint256 timeToExp = 1 days; //86400
    //     uint256 vol = 650000000000000000;
    //     uint256 spot = 1000000000000000000000;
    //     uint256 strike = 2020000000000000000000;
    //     int256 rate = 50000000000000000;
    //     uint256 deltaT = timeToExp / 15;

    //     uint256 alpha = 1e18;

    //     IVXPricer.OptionPricing memory inputs =
    //         IVXPricer.OptionPricing(
    //             IVXPricer.PricingInputs(IVXPricer.FetchedInputs(vol, spot, strike), timeToExp, rate, deltaT),
    //             alpha
    //         );

    //     (uint256 call, uint256 put, uint256 vega) = IVXPricer.calculateIVXPricingVega(inputs);

    //     console.log("call      ", call);
    //     console.log("put       ", put);
    //     console.log("vega      ", vega);
    // }
}
