// SPDX-License-Identifier: ISC
pragma solidity ^0.8.18;

// Libraries
import "./math/SignedDecimalMath.sol";
import "./math/DecimalMath.sol";
import "./math/MathLib.sol";
import "./math/Math.sol";

/**
 * @title BlackScholes
 * @author gradient (@gradientIVX), MiguelBits (@MiguelBits)
 * @dev Inspired in Lyra Black-Scholes, Contract to compute the black scholes price of options. Where the unit is unspecified, it should be treated as a
 * PRECISE_DECIMAL, which has 1e27 units of precision. The default decimal matches the Ethereum standard of 1e18 units of precision.
 */
library BlackScholes {
    using DecimalMath for uint256;
    using SignedDecimalMath for int256;

    uint256 private constant SECONDS_PER_YEAR = Math.SECONDS_PER_YEAR;
    uint256 private constant PRECISE_UNIT = Math.PRECISE_UNIT;

    /// @dev Value to use to avoid any division by 0 or values near 0
    uint256 private constant MIN_T_ANNUALISED = PRECISE_UNIT / SECONDS_PER_YEAR; // 1 second
    uint256 private constant MIN_VOLATILITY = PRECISE_UNIT / 10000; // 0.001%
    uint256 private constant VEGA_STANDARDISATION_MIN_DAYS = 7 days;

    //////////////////////
    // Computing Greeks //
    //////////////////////

    /**
     * @dev Returns internal coefficients of the Black-Scholes call price formula, d1 and d2.
     * @param tAnnualised Number of years to expiry
     * @param volatility Implied volatility over the period til expiry as a percentage
     * @param spot The current price of the base asset
     * @param strikePrice The strikePrice price of the option
     * @param rate The percentage risk free rate + carry cost
     */
    function _d1d2(uint256 tAnnualised, uint256 volatility, uint256 spot, uint256 strikePrice, int256 rate)
        internal
        pure
        returns (int256 d1, int256 d2)
    {
        // Set minimum values for tAnnualised and volatility to not break computation in extreme scenarios
        // These values will result in option prices reflecting only the difference in stock/strikePrice, which is expected.
        // This should be caught before calling this function, however the function shouldn't break if the values are 0.
        tAnnualised = tAnnualised < MIN_T_ANNUALISED ? MIN_T_ANNUALISED : tAnnualised;
        volatility = volatility < MIN_VOLATILITY ? MIN_VOLATILITY : volatility;

        int256 vtSqrt = int256(volatility.multiplyDecimalRoundPrecise(Math._sqrtPrecise(tAnnualised)));
        int256 log = MathLib.lnPrecise(int256(spot.divideDecimalRoundPrecise(strikePrice)));
        int256 v2t = (int256(volatility.multiplyDecimalRoundPrecise(volatility) / 2) + rate).multiplyDecimalRoundPrecise(
            int256(tAnnualised)
        );
        d1 = (log + v2t).divideDecimalRoundPrecise(vtSqrt);
        d2 = d1 - vtSqrt;
    }

    /**
     * @dev Internal coefficients of the Black-Scholes call price formula.
     * @param tAnnualised Number of years to expiry
     * @param spot The current price of the base asset
     * @param strikePrice The strikePrice price of the option
     * @param rate The percentage risk free rate + carry cost
     * @param d1 Internal coefficient of Black-Scholes
     * @param d2 Internal coefficient of Black-Scholes
     */
    function _calculateBSPrices(
        uint256 tAnnualised,
        uint256 spot,
        uint256 strikePrice,
        int256 rate,
        int256 d1,
        int256 d2
    ) internal pure returns (uint256 call, uint256 put) {
        uint256 strikePricePV = strikePrice.multiplyDecimalRoundPrecise(
            MathLib.expPrecise(int256(-rate.multiplyDecimalRoundPrecise(int256(tAnnualised))))
        );
        uint256 spotNd1 = spot.multiplyDecimalRoundPrecise(Math._stdNormalCDF(d1));
        uint256 strikePriceNd2 = strikePricePV.multiplyDecimalRoundPrecise(Math._stdNormalCDF(d2));

        // We clamp to zero if the minuend is less than the subtrahend
        // In some scenarios it may be better to compute put price instead and derive call from it depending on which way
        // around is more precise.
        call = strikePriceNd2 <= spotNd1 ? spotNd1 - strikePriceNd2 : 0;
        put = call + strikePricePV;
        put = spot <= put ? put - spot : 0;
    }

    /*
    * Greeks
    */

    /**
     * @dev Returns the option's delta value
     * @param d1 Internal coefficient of Black-Scholes
     */
    function _delta(int256 d1) internal pure returns (int256 callDelta, int256 putDelta) {
        callDelta = int256(Math._stdNormalCDF(d1));
        putDelta = callDelta - int256(Math.PRECISE_UNIT);
    }

    /**
     * @dev Returns the option's vega value based on d1. Quoted in cents.
     *
     * @param d1 Internal coefficient of Black-Scholes
     * @param tAnnualised Number of years to expiry
     * @param spot The current price of the base asset
     */
    function _vega(uint256 tAnnualised, uint256 spot, int256 d1) internal pure returns (uint256) {
        return Math._sqrtPrecise(tAnnualised).multiplyDecimalRoundPrecise(
            Math._stdNormal(d1).multiplyDecimalRoundPrecise(spot)
        );
    }

    /**
     * @dev Returns the option's vega value with expiry modified to be at least VEGA_STANDARDISATION_MIN_DAYS
     * @param d1 Internal coefficient of Black-Scholes
     * @param spot The current price of the base asset
     * @param timeToExpirySec Number of seconds to expiry
     */
    function _standardVega(int256 d1, uint256 spot, uint256 timeToExpirySec) internal pure returns (uint256, uint256) {
        uint256 tAnnualised = Math._annualise(timeToExpirySec);
        uint256 normalisationFactor = _getVegaNormalisationFactorPrecise(timeToExpirySec);
        uint256 vegaPrecise = BlackScholes._vega(tAnnualised, spot, d1);
        return (vegaPrecise, vegaPrecise.multiplyDecimalRoundPrecise(normalisationFactor));
    }

    function _getVegaNormalisationFactorPrecise(uint256 timeToExpirySec) internal pure returns (uint256) {
        timeToExpirySec =
            timeToExpirySec < VEGA_STANDARDISATION_MIN_DAYS ? VEGA_STANDARDISATION_MIN_DAYS : timeToExpirySec;
        uint256 daysToExpiry = timeToExpirySec / 1 days;
        uint256 thirty = 30 * 1e27;
        return Math._sqrtPrecise(thirty / daysToExpiry) / 100;
    }
}
