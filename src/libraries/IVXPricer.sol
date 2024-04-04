// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Libraries
import "./math/SignedDecimalMath.sol";
import "./math/DecimalMath.sol";
import "./math/MathLib.sol";
import "./math/Math.sol";
import "./BlackScholes.sol";
import "./Binomial.sol";

/**
 * @title IVXPricer
 * @author gradient (@gradientIVX), MiguelBits (@MiguelBits)
 * @notice This contract implements the binomial pricing model for European and American options
 */
library IVXPricer {
    using DecimalMath for uint256;
    using SignedDecimalMath for int256;

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @param impliedVolatility Implied impliedVolatility over the period til expiry as a percentage
     * @param spotPrice The current price of the base asset
     * @param strikePrice The strikePrice price of the option
     */
    struct FetchedInputs {
        uint256 impliedVolatility;
        uint256 spotPrice;
        uint256 strikePrice;
    }

    /**
     * @param secondsToExpiry Number of seconds to the expiry of the option
     * @param riskFreeRate The percentage risk free rate + carry cost
     * @param deltaT The time step in seconds, use this to get N = secondsToExpiry / deltaT
     */
    struct PricingInputs {
        FetchedInputs fetchedInputs;
        uint256 secondsToExpiry;
        int256 riskFreeRate;
        uint256 deltaT;
    }
    /// @dev not used for BS pricing

    /**
     * @param Alpha value between 0 and 1, that blends Binomial and BS pricing model,
     * the closer to 0 the more we use Binomial, and the closer to 1 the more we use BS
     */
    struct OptionPricing {
        PricingInputs inputs;
        uint256 Alpha;
    }

    struct BlackScholesInputs {
        uint256 spotPrice;
        uint256 strikePrice;
        uint256 impliedVolatility;
        int256 riskFreeRate;
        uint256 secondsToExpiry;
    }

    struct BlackScholesOutputs {
        uint256 callPremium;
        uint256 putPremium;
        uint256 vega;
        int256 callDelta;
        int256 putDelta;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                        OPTION PRICING                                                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function callIVXPricing(OptionPricing memory optionParams)
        internal
        pure
        returns (uint256 _premium, uint256 _vega, int256 _delta)
    {
        if (optionParams.Alpha == 0) {
            BlackScholesOutputs memory bsOutputs;
            bsOutputs = BlackScholesPrices_Vega_Delta(optionParams.inputs);
            _premium = bsOutputs.callPremium;
            _vega = bsOutputs.vega;
            _delta = bsOutputs.callDelta;
        } else if (optionParams.Alpha == 1e18) {
            _premium = callBinomialPrices(optionParams.inputs);
            _vega = vega(optionParams.inputs);
            (_delta,, _vega) = delta_vega(optionParams.inputs);
        } else {
            BlackScholesOutputs memory bsOutputs;
            bsOutputs = BlackScholesPrices_Vega_Delta(optionParams.inputs);
            uint256 bnCall = callBinomialPrices(optionParams.inputs);
            //blend in bs and bn based on Alpha factor; //blended_price = (Alpha * bnCall) + (1-Alpha * bsCall)
            _premium = (optionParams.Alpha * bnCall + (1e18 - optionParams.Alpha) * bsOutputs.callPremium) / 1e18;
            _vega = bsOutputs.vega;
            _delta = bsOutputs.callDelta;
        }

        _vega = _vega.multiplyDecimalRoundPrecise(
            BlackScholes._getVegaNormalisationFactorPrecise(optionParams.inputs.secondsToExpiry)
        );
    }

    function putIVXPricing(OptionPricing memory optionParams)
        internal
        pure
        returns (uint256 _premium, uint256 _vega, int256 _delta)
    {
        if (optionParams.Alpha == 0) {
            BlackScholesOutputs memory bsOutputs;
            bsOutputs = BlackScholesPrices_Vega_Delta(optionParams.inputs);
            _premium = bsOutputs.putPremium;
            _vega = bsOutputs.vega;
            _delta = bsOutputs.putDelta;
        } else if (optionParams.Alpha == 1e18) {
            _premium = putBinomialPrices(optionParams.inputs);
            _vega = vega(optionParams.inputs);
            (, _delta, _vega) = delta_vega(optionParams.inputs);
        } else {
            BlackScholesOutputs memory bsOutputs;
            bsOutputs = BlackScholesPrices_Vega_Delta(optionParams.inputs);
            uint256 bnPut = putBinomialPrices(optionParams.inputs);
            //blend in bs and bn based on Alpha factor; //blended_price = (Alpha * bnCall) + (1-Alpha * bsCall)
            _premium = (optionParams.Alpha * bnPut + (1e18 - optionParams.Alpha) * bsOutputs.putPremium) / 1e18;
            _vega = bsOutputs.vega;
            _delta = bsOutputs.putDelta;
        }

        _vega = _vega.multiplyDecimalRoundPrecise(
            BlackScholes._getVegaNormalisationFactorPrecise(optionParams.inputs.secondsToExpiry)
        );
    }

    function calculateAlpha(uint256 secondsToExpire, uint256 binomialCutoff, uint256 blackScholesCutoff)
        internal
        pure
        returns (uint256 alpha)
    {
        if (secondsToExpire <= binomialCutoff) return 1e18;
        else if (secondsToExpire >= blackScholesCutoff) return 0;
        return (blackScholesCutoff - secondsToExpire) * 1e18 / (blackScholesCutoff - binomialCutoff);
    }

    function optionPricing(OptionPricing memory optionParams) internal pure returns (uint256, uint256) {
        if (optionParams.Alpha == 0) {
            return calculateBSPrices(optionParams.inputs);
        } else if (optionParams.Alpha == 1e18) {
            return calculateBinomialPrices(optionParams.inputs);
        } else {
            (uint256 bsCall, uint256 bsPut) = calculateBSPrices(optionParams.inputs);
            (uint256 bnCall, uint256 bnPut) = calculateBinomialPrices(optionParams.inputs);
            //blend in bs and bn based on Alpha factor; //blended_price = (Alpha * bnCall) + (1-Alpha * bsCall)
            uint256 call = (optionParams.Alpha * bnCall + (1e18 - optionParams.Alpha) * bsCall) / 1e18;
            uint256 put = (optionParams.Alpha * bnPut + (1e18 - optionParams.Alpha) * bsPut) / 1e18;
            return (call, put);
        }
    }

    function callOptionPricing(OptionPricing memory optionParams) internal pure returns (uint256) {
        if ((optionParams.Alpha == 0) || (optionParams.Alpha == 1e18)) {
            (uint256 _call,) = optionPricing(optionParams);
            return _call;
        }

        (uint256 bsCall,) = calculateBSPrices(optionParams.inputs);
        uint256 bnCall = callBinomialPrices(optionParams.inputs);

        return (optionParams.Alpha * bnCall + (1e18 - optionParams.Alpha) * bsCall) / 1e18;
    }

    function putOptionPricing(OptionPricing memory optionParams) internal pure returns (uint256) {
        if ((optionParams.Alpha == 0) || (optionParams.Alpha == 1e18)) {
            (, uint256 _put) = optionPricing(optionParams);
            return _put;
        }

        (, uint256 bsPut) = calculateBSPrices(optionParams.inputs);
        uint256 bnPut = putBinomialPrices(optionParams.inputs);

        return (optionParams.Alpha * bnPut + (1e18 - optionParams.Alpha) * bsPut) / 1e18;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                        BLACK-SCHOLES OPTION PRICING                                                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Returns call and put prices for options with given parameters.
     */
    function calculateBSPrices(PricingInputs memory optionParams) internal pure returns (uint256 call, uint256 put) {
        uint256 tAnnualised = Math._annualise(optionParams.secondsToExpiry);
        uint256 spotPrecise = optionParams.fetchedInputs.spotPrice.decimalToPreciseDecimal();
        uint256 strikePricePrecise = optionParams.fetchedInputs.strikePrice.decimalToPreciseDecimal();
        int256 ratePrecise = optionParams.riskFreeRate.decimalToPreciseDecimal();
        (int256 d1, int256 d2) = BlackScholes._d1d2(
            tAnnualised,
            optionParams.fetchedInputs.impliedVolatility.decimalToPreciseDecimal(),
            spotPrecise,
            strikePricePrecise,
            ratePrecise
        );
        (call, put) = BlackScholes._calculateBSPrices(tAnnualised, spotPrecise, strikePricePrecise, ratePrecise, d1, d2);
        return (call.preciseDecimalToDecimal(), put.preciseDecimalToDecimal());
    }

    /**
     * @dev Returns call delta given parameters.
     */
    function delta(BlackScholesInputs memory optionParams)
        internal
        pure
        returns (int256 callDeltaDecimal, int256 putDeltaDecimal)
    {
        uint256 tAnnualised = Math._annualise(optionParams.secondsToExpiry);
        uint256 spotPrecise = optionParams.spotPrice.decimalToPreciseDecimal();

        (int256 d1,) = BlackScholes._d1d2(
            tAnnualised,
            optionParams.impliedVolatility.decimalToPreciseDecimal(),
            spotPrecise,
            optionParams.strikePrice.decimalToPreciseDecimal(),
            optionParams.riskFreeRate.decimalToPreciseDecimal()
        );

        (int256 callDelta, int256 putDelta) = BlackScholes._delta(d1);
        return (callDelta.preciseDecimalToDecimal(), putDelta.preciseDecimalToDecimal());
    }

    /**
     * @dev Returns delta and put given parameters.
     */
    function delta_vega(PricingInputs memory optionParams)
        internal
        pure
        returns (int256 callDeltaDecimal, int256 putDeltaDecimal, uint256 vegaPrecise)
    {
        uint256 tAnnualised = Math._annualise(optionParams.secondsToExpiry);
        uint256 spotPrecise = optionParams.fetchedInputs.spotPrice.decimalToPreciseDecimal();

        (int256 d1,) = BlackScholes._d1d2(
            tAnnualised,
            optionParams.fetchedInputs.impliedVolatility.decimalToPreciseDecimal(),
            spotPrecise,
            optionParams.fetchedInputs.strikePrice.decimalToPreciseDecimal(),
            optionParams.riskFreeRate.decimalToPreciseDecimal()
        );

        (int256 callDelta, int256 putDelta) = BlackScholes._delta(d1);
        return (
            callDelta.preciseDecimalToDecimal(),
            putDelta.preciseDecimalToDecimal(),
            BlackScholes._vega(tAnnualised, spotPrecise, d1).preciseDecimalToDecimal()
        );
    }

    /**
     * @dev Returns delta and put given parameters.
     */
    function delta_vega(BlackScholesInputs memory optionParams)
        internal
        pure
        returns (int256 callDeltaDecimal, int256 putDeltaDecimal, uint256 vegaPrecise)
    {
        uint256 tAnnualised = Math._annualise(optionParams.secondsToExpiry);
        uint256 spotPrecise = optionParams.spotPrice.decimalToPreciseDecimal();

        (int256 d1,) = BlackScholes._d1d2(
            tAnnualised,
            optionParams.impliedVolatility.decimalToPreciseDecimal(),
            spotPrecise,
            optionParams.strikePrice.decimalToPreciseDecimal(),
            optionParams.riskFreeRate.decimalToPreciseDecimal()
        );

        (int256 callDelta, int256 putDelta) = BlackScholes._delta(d1);
        return (
            callDelta.preciseDecimalToDecimal(),
            putDelta.preciseDecimalToDecimal(),
            BlackScholes._vega(tAnnualised, spotPrecise, d1).preciseDecimalToDecimal()
        );
    }

    /**
     * @dev Returns non-normalized vega given parameters. Quoted in cents.
     */
    function vega(BlackScholesInputs memory optionParams) internal pure returns (uint256 vegaDecimal) {
        uint256 tAnnualised = Math._annualise(optionParams.secondsToExpiry);
        uint256 spotPrecise = optionParams.spotPrice.decimalToPreciseDecimal();

        (int256 d1,) = BlackScholes._d1d2(
            tAnnualised,
            optionParams.impliedVolatility.decimalToPreciseDecimal(),
            spotPrecise,
            optionParams.strikePrice.decimalToPreciseDecimal(),
            optionParams.riskFreeRate.decimalToPreciseDecimal()
        );
        return BlackScholes._vega(tAnnualised, spotPrecise, d1).preciseDecimalToDecimal();
    }

    /**
     * @dev Returns non-normalized vega given parameters. Quoted in cents.
     */
    function vega(PricingInputs memory optionParams) internal pure returns (uint256 vegaDecimal) {
        uint256 tAnnualised = Math._annualise(optionParams.secondsToExpiry);
        uint256 spotPrecise = optionParams.fetchedInputs.spotPrice.decimalToPreciseDecimal();

        (int256 d1,) = BlackScholes._d1d2(
            tAnnualised,
            optionParams.fetchedInputs.impliedVolatility.decimalToPreciseDecimal(),
            spotPrecise,
            optionParams.fetchedInputs.strikePrice.decimalToPreciseDecimal(),
            optionParams.riskFreeRate.decimalToPreciseDecimal()
        );
        return BlackScholes._vega(tAnnualised, spotPrecise, d1).preciseDecimalToDecimal();
    }

    function standardVega(PricingInputs memory optionParams) internal pure returns (uint256, uint256) {
        uint256 tAnnualised = Math._annualise(optionParams.secondsToExpiry);
        uint256 spotPrecise = optionParams.fetchedInputs.spotPrice.decimalToPreciseDecimal();

        (int256 d1,) = BlackScholes._d1d2(
            tAnnualised,
            optionParams.fetchedInputs.impliedVolatility.decimalToPreciseDecimal(),
            spotPrecise,
            optionParams.fetchedInputs.strikePrice.decimalToPreciseDecimal(),
            optionParams.riskFreeRate.decimalToPreciseDecimal()
        );
        (uint256 vegaPrecise, uint256 stdVegaPrecise) =
            BlackScholes._standardVega(d1, spotPrecise, optionParams.secondsToExpiry);
        return (vegaPrecise.preciseDecimalToDecimal(), stdVegaPrecise.preciseDecimalToDecimal());
    }

    function BlackScholesPrices_Vega_Delta(PricingInputs memory optionParams)
        internal
        pure
        returns (BlackScholesOutputs memory outputs)
    {
        uint256 tAnnualised = Math._annualise(optionParams.secondsToExpiry);
        uint256 spotPrecise = optionParams.fetchedInputs.spotPrice.decimalToPreciseDecimal();
        uint256 strikePricePrecise = optionParams.fetchedInputs.strikePrice.decimalToPreciseDecimal();
        int256 ratePrecise = optionParams.riskFreeRate.decimalToPreciseDecimal();
        (int256 d1, int256 d2) = BlackScholes._d1d2(
            tAnnualised,
            optionParams.fetchedInputs.impliedVolatility.decimalToPreciseDecimal(),
            spotPrecise,
            strikePricePrecise,
            ratePrecise
        );

        (uint256 callPrice, uint256 putPrice) =
            BlackScholes._calculateBSPrices(tAnnualised, spotPrecise, strikePricePrecise, ratePrecise, d1, d2);
        uint256 vegaPrecise = BlackScholes._vega(tAnnualised, spotPrecise, d1);
        (int256 callDelta, int256 putDelta) = BlackScholes._delta(d1);

        outputs = BlackScholesOutputs(
            callPrice.preciseDecimalToDecimal(),
            putPrice.preciseDecimalToDecimal(),
            vegaPrecise.preciseDecimalToDecimal(),
            callDelta.preciseDecimalToDecimal(),
            putDelta.preciseDecimalToDecimal()
        );
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                        BINOMIAL OPTION PRICING                                                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function calculateBinomialPrices(PricingInputs memory optionParams)
        internal
        pure
        returns (uint256 call, uint256 put)
    {
        Binomial.PricingInputs memory pricingParams = Binomial.PricingInputs({
            secondsToExpiry: optionParams.secondsToExpiry,
            impliedVolatility: optionParams.fetchedInputs.impliedVolatility,
            spotPrice: optionParams.fetchedInputs.spotPrice,
            strikePrice: optionParams.fetchedInputs.strikePrice,
            riskFreeRate: uint256(optionParams.riskFreeRate),
            deltaT: optionParams.deltaT
        });
        return Binomial.optionPrices(pricingParams);
    }

    function callBinomialPrices(PricingInputs memory optionParams) internal pure returns (uint256) {
        Binomial.PricingInputs memory pricingParams = Binomial.PricingInputs({
            secondsToExpiry: optionParams.secondsToExpiry,
            impliedVolatility: optionParams.fetchedInputs.impliedVolatility,
            spotPrice: optionParams.fetchedInputs.spotPrice,
            strikePrice: optionParams.fetchedInputs.strikePrice,
            riskFreeRate: uint256(optionParams.riskFreeRate),
            deltaT: optionParams.deltaT
        });
        return Binomial.callOptionPrices(pricingParams);
    }

    function putBinomialPrices(PricingInputs memory optionParams) internal pure returns (uint256) {
        Binomial.PricingInputs memory pricingParams = Binomial.PricingInputs({
            secondsToExpiry: optionParams.secondsToExpiry,
            impliedVolatility: optionParams.fetchedInputs.impliedVolatility,
            spotPrice: optionParams.fetchedInputs.spotPrice,
            strikePrice: optionParams.fetchedInputs.strikePrice,
            riskFreeRate: uint256(optionParams.riskFreeRate),
            deltaT: optionParams.deltaT
        });
        return Binomial.putOptionPrices(pricingParams);
    }
}
