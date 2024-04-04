pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Binomial} from "../../../src/libraries/Binomial.sol";
import "../../../src/libraries/math/Math.sol";
import {IVXPricer} from "../../../src/libraries/IVXPricer.sol";

contract BinomialTest is Test {
    uint256 private constant secondsInYear = 31536000;

    function test_transitionFactors() public {
        uint256 deltaTImpliedVolatility = 10000000000000000;
        (uint256 dUpFactor, uint256 dDownFactor) = Binomial.calculateTransitionFactors(deltaTImpliedVolatility);
        // console.log("dUpFactor", dUpFactor);
        // console.log("dDownFactor", dDownFactor);
        //assert dUpFactor exp(10000000000000000)
        assertEq(dUpFactor, 1010050167084168057);
        //assert dDownFactor 1/exp(10000000000000000)
        assertEq(dDownFactor, 990049833749168054);
    }

    function test_BinomialTransitionFactors() public {
        // Set the test parameters
        uint256 vol = 650000000000000000;
        uint256 deltaT = 1 hours;
        uint256 deltaTImpliedVolatility = vol * Math._sqrt(deltaT * 1e18 / secondsInYear) / 1e18;

        (uint256 up, uint256 down) = Binomial.calculateTransitionFactors(deltaTImpliedVolatility);
        console.log("up  ", up);
        console.log("down", down);
    }

    function test_BinomialTransitionProbabilities() public {
        // Set the test parameters
        uint256 vol = 1 ether;
        uint256 deltaT = 30 minutes;
        uint256 riskFreeRate = 1 ether / 2;
        uint256 deltaTImpliedVolatility = vol * Math._sqrt(deltaT * 1e18 / secondsInYear) / 1e9;
        uint256 deltaTRiskFreeRate = (riskFreeRate * deltaT * 1e18 / secondsInYear) / 1e18;

        (uint256 up, uint256 down) = Binomial.calculateTransitionFactors(deltaTImpliedVolatility);
        console.log("up  ", up);
        console.log("down", down);
        (uint256 p, uint256 q) = Binomial.calculateTransitionProbabilities(deltaTRiskFreeRate, up, down);

        console.log("p", p);
        console.log("q", q);
        // console.log("p + q", p + q);
        assertTrue(p + q == 1e18);
    }

    function test_BinomialOptionPrices() public {
        // Set the test parameters
        uint256 timeToExp = 1 days; //86400
        uint256 vol = 650000000000000000;
        uint256 spot = 1000000000000000000000;
        uint256 strike = 1020000000000000000000;
        uint256 rate = 50000000000000000;
        uint256 deltaT = timeToExp / 10;

        Binomial.PricingInputs memory inputs = Binomial.PricingInputs(timeToExp, vol, spot, strike, rate, deltaT);
        (uint256 call, uint256 put) = Binomial.optionPrices(inputs);
        console.log("call", call); //buy option
        console.log("put ", put); //sell option
    }

    function test_callOptionPricing() public {
        // Set the test parameters
        uint256 timeToExp = 1 days; //86400
        uint256 vol = 650000000000000000;
        uint256 spot = 1000000000000000000000;
        uint256 strike = 1020000000000000000000;
        uint256 rate = 50000000000000000;
        uint256 deltaT = timeToExp / 10;

        Binomial.PricingInputs memory inputs = Binomial.PricingInputs(timeToExp, vol, spot, strike, rate, deltaT);
        uint256 call = Binomial.callOptionPrices(inputs);
        console.log("call", call); //buy option
    }

    function test_putOptionPricing() public {
        // Set the test parameters
        uint256 timeToExp = 86400;
        uint256 vol = 680000000000000000;
        uint256 spot = 1000000000000000000000;
        uint256 strike = 1020000000000000000000;
        uint256 rate = 50000000000000000;
        uint256 deltaT = timeToExp / 15;

        Binomial.PricingInputs memory inputs = Binomial.PricingInputs(timeToExp, vol, spot, strike, rate, deltaT);
        uint256 put = Binomial.putOptionPrices(inputs);
        console.log("put ", put); //sell option
    }

    function test_calculateTerminalSharePrices() public {
        uint256 spotPrice = 1 ether;
        uint256 up = 1010050167084168057;
        uint256 down = 990049833749168054;
        uint256 N = 3;

        uint256[] memory terminalPrices = Binomial.calculateTerminalSharePrices(spotPrice, up, down, N);
        for (uint256 i = 0; i < terminalPrices.length; i++) {
            // console.log("terminalPrices", terminalPrices[i]);
            assertTrue(terminalPrices[i] > 900000000000000000);
            assertTrue(terminalPrices[i] < 1100000000000000000);
        }
    }

    function test_calculateTerminalPayoffs() public {
        uint256 spotPrice = 1 ether;
        uint256 up = 1010050167084168057;
        uint256 down = 990049833749168054;
        uint256 N = 3;

        uint256[] memory terminalPrices = Binomial.calculateTerminalSharePrices(spotPrice, up, down, N);
        uint256 strike = 1200000000000000000;

        uint256[] memory terminalCallPayoffs = Binomial.calculateTerminalCallPayoffs(terminalPrices, strike);
        for (uint256 i = 0; i < terminalCallPayoffs.length; i++) {
            // console.log("terminalCallPayoffs", terminalCallPayoffs[i]);
            assertTrue(terminalCallPayoffs[i] == 0);
        }

        uint256[] memory terminalPutPayoffs = Binomial.calculateTerminalPutPayoffs(terminalPrices, strike);
        for (uint256 i = 0; i < terminalPutPayoffs.length; i++) {
            // console.log("terminalPutPayoffs", terminalPutPayoffs[i]);
            assertTrue(terminalPutPayoffs[i] > 0);
        }
    }

    function test_Premium_1dayToExpire() public view returns (uint256 call, uint256 put) {
        uint256 timeToExp = 1 days; //86400
        uint256 vol = 0.65 ether; //0.65 ether (65%)
        uint256 spot = 1 ether; //1 ether
        uint256 strike = 1.02 ether; //1.02 ether (2%) above spot
        uint256 rate = 0.05 ether; //0.05 ether
        uint256 deltaT = timeToExp / 15;

        Binomial.PricingInputs memory inputs = Binomial.PricingInputs(timeToExp, vol, spot, strike, rate, deltaT);
        call = Binomial.callOptionPrices(inputs);
        console.log("call", call);
        put = Binomial.putOptionPrices(inputs);
        console.log("put ", put);
    }

    function test_Premium_6HourTillExpire() public view returns (uint256 call, uint256 put) {
        // (uint256 prevCall, uint256 prevPut) = test_Premium_1dayToExpire();
        console.log("TEST_6_HOUR_TO_EXPIRE");
        uint256 timeToExp = 6 hours;
        uint256 vol = 0.65 ether; //0.65 ether (65%)
        uint256 spot = 1 ether; //1 ether
        uint256 strike = 1.02 ether; //1.02 ether (2%) above spot
        uint256 rate = 0.05 ether; //0.05 ether
        uint256 deltaT = timeToExp / 15;

        Binomial.PricingInputs memory inputs = Binomial.PricingInputs(timeToExp, vol, spot, strike, rate, deltaT);
        call = Binomial.callOptionPrices(inputs);
        console.log("call", call);
        put = Binomial.putOptionPrices(inputs);
        console.log("put ", put);
    }

    function test_Premium_1HourToExpire() public returns (uint256 call, uint256 put) {
        // (uint256 prevCall, uint256 prevPut) = test_Premium_6HourTillExpire();
        console.log("TEST_CLOSE_TO_STRIKE");
        uint256 timeToExp = 1 hours;
        uint256 vol = 0.65 ether; //0.65 ether (65%)
        uint256 spot = 1 ether; //1 ether
        uint256 strike = 1.02 ether; //1.02 ether (2%) above spot
        uint256 rate = 0.05 ether; //0.05 ether
        uint256 deltaT = timeToExp / 15;

        Binomial.PricingInputs memory inputs = Binomial.PricingInputs(timeToExp, vol, spot, strike, rate, deltaT);
        call = Binomial.callOptionPrices(inputs);
        console.log("call", call);
        put = Binomial.putOptionPrices(inputs);
        console.log("put ", put);
    }

    function test_Premium_1HourToExpire_PriceAboveStrike() public view returns (uint256 call, uint256 put) {
        // (uint256 prevCall, uint256 prevPut) = test_Premium_6HourTillExpire();
        console.log("TEST_CLOSE_TO_STRIKE");
        uint256 timeToExp = 1 hours;
        uint256 vol = 0.65 ether; //0.65 ether (65%)
        uint256 spot = 1.03 ether; //1 ether
        uint256 strike = 1.02 ether; //1.02 ether (2%) above spot
        uint256 rate = 0.05 ether; //0.05 ether
        uint256 deltaT = timeToExp / 15;

        Binomial.PricingInputs memory inputs = Binomial.PricingInputs(timeToExp, vol, spot, strike, rate, deltaT);
        call = Binomial.callOptionPrices(inputs);
        console.log("call", call);
        put = Binomial.putOptionPrices(inputs);
        console.log("put ", put);
    }
}
