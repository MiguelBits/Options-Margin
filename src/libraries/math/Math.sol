//SPDX-License-Identifier: ISC
pragma solidity ^0.8.18;

import "./SignedDecimalMath.sol";
import "./DecimalMath.sol";
import "./MathLib.sol";

/**
 * @title Math
 * @author IVX
 * @dev Library to unify logic for common shared functions
 */
library Math {
    using DecimalMath for uint256;
    using SignedDecimalMath for int256;

    uint256 public constant SECONDS_PER_YEAR = 31536000;
    /// @dev Internally this library uses 27 decimals of precision
    uint256 public constant PRECISE_UNIT = 1e27;
    uint256 private constant SQRT_TWOPI = 2506628274631000502415765285;

    /// @dev Magic numbers for normal CDF
    uint256 private constant SPLIT = 7071067811865470000000000000;
    uint256 private constant N0 = 220206867912376000000000000000;
    uint256 private constant N1 = 221213596169931000000000000000;
    uint256 private constant N2 = 112079291497871000000000000000;
    uint256 private constant N3 = 33912866078383000000000000000;
    uint256 private constant N4 = 6373962203531650000000000000;
    uint256 private constant N5 = 700383064443688000000000000;
    uint256 private constant N6 = 35262496599891100000000000;
    uint256 private constant M0 = 440413735824752000000000000000;
    uint256 private constant M1 = 793826512519948000000000000000;
    uint256 private constant M2 = 637333633378831000000000000000;
    uint256 private constant M3 = 296564248779674000000000000000;
    uint256 private constant M4 = 86780732202946100000000000000;
    uint256 private constant M5 = 16064177579207000000000000000;
    uint256 private constant M6 = 1755667163182640000000000000;
    uint256 private constant M7 = 88388347648318400000000000;

    /// @dev Return the minimum value between the two inputs
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x < y) ? x : y;
    }

    /// @dev Return the maximum value between the two inputs
    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x > y) ? x : y;
    }

    function maxSigned(int256 x, int256 y) internal pure returns (int256) {
        return (x > y) ? x : y;
    }

    /// @dev Compute the absolute value of `val`.
    function abs(int256 val) internal pure returns (uint256) {
        return uint256(val < 0 ? -val : val);
    }

    /// @dev Takes ceiling of a to m precision
    /// @param m represents 1eX where X is the number of trailing 0's
    function ceil(uint256 a, uint256 m) internal pure returns (uint256) {
        return ((a + m - 1) / m) * m;
    }

    /**
     * @dev Returns the floor relative to UINT
     */
    function floor(uint256 x, uint256 assetDecimals) internal pure returns (uint256) {
        return x - (x % assetDecimals);
    }

    /////////////////////
    // Math Operations //
    /////////////////////

    /// @notice Calculates the square root of x, rounding down (borrowed from https://github.com/paulrberg/prb-math)
    /// @dev Uses the Babylonian method https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method.
    /// @param x The uint256 number for which to calculate the square root.
    /// @return result The result as an uint256.
    function _sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) {
            return 0;
        }

        // Calculate the square root of the perfect square of a power of two that is the closest to x.
        uint256 xAux = uint256(x);
        result = 1;
        if (xAux >= 0x100000000000000000000000000000000) {
            xAux >>= 128;
            result <<= 64;
        }
        if (xAux >= 0x10000000000000000) {
            xAux >>= 64;
            result <<= 32;
        }
        if (xAux >= 0x100000000) {
            xAux >>= 32;
            result <<= 16;
        }
        if (xAux >= 0x10000) {
            xAux >>= 16;
            result <<= 8;
        }
        if (xAux >= 0x100) {
            xAux >>= 8;
            result <<= 4;
        }
        if (xAux >= 0x10) {
            xAux >>= 4;
            result <<= 2;
        }
        if (xAux >= 0x8) {
            result <<= 1;
        }

        // The operations can never overflow because the result is max 2^127 when it enters this block.
        unchecked {
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1; // Seven iterations should be enough
            uint256 roundedDownResult = x / result;
            return result >= roundedDownResult ? roundedDownResult : result;
        }
    }

    /**
     * @dev Returns the square root of the value using Newton's method.
     */
    function _sqrtPrecise(uint256 x) internal pure returns (uint256) {
        // Add in an extra unit factor for the square root to gobble;
        // otherwise, sqrt(x * UNIT) = sqrt(x) * sqrt(UNIT)
        return _sqrt(x * PRECISE_UNIT);
    }

    /**
     * @dev The standard normal distribution of the value.
     */
    function _stdNormal(int256 x) internal pure returns (uint256) {
        return MathLib.expPrecise(int256(-x.multiplyDecimalRoundPrecise(x / 2))).divideDecimalRoundPrecise(SQRT_TWOPI);
    }

    /**
     * @dev The standard normal cumulative distribution of the value.
     * borrowed from a C++ implementation https://stackoverflow.com/a/23119456
     */
    function _stdNormalCDF(int256 x) internal pure returns (uint256) {
        uint256 z = Math.abs(x);
        int256 c = 0;

        if (z <= 37 * PRECISE_UNIT) {
            uint256 e = MathLib.expPrecise(-int256(z.multiplyDecimalRoundPrecise(z / 2)));
            if (z < SPLIT) {
                c = int256(
                    (
                        _stdNormalCDFNumerator(z).divideDecimalRoundPrecise(_stdNormalCDFDenom(z))
                            .multiplyDecimalRoundPrecise(e)
                    )
                );
            } else {
                uint256 f = (
                    z
                        + PRECISE_UNIT.divideDecimalRoundPrecise(
                            z
                                + (2 * PRECISE_UNIT).divideDecimalRoundPrecise(
                                    z
                                        + (3 * PRECISE_UNIT).divideDecimalRoundPrecise(
                                            z + (4 * PRECISE_UNIT).divideDecimalRoundPrecise(z + ((PRECISE_UNIT * 13) / 20))
                                        )
                                )
                        )
                );
                c = int256(e.divideDecimalRoundPrecise(f.multiplyDecimalRoundPrecise(SQRT_TWOPI)));
            }
        }
        return uint256((x <= 0 ? c : (int256(PRECISE_UNIT) - c)));
    }

    /**
     * @dev Helper for _stdNormalCDF
     */
    function _stdNormalCDFNumerator(uint256 z) internal pure returns (uint256) {
        uint256 numeratorInner = ((((((N6 * z) / PRECISE_UNIT + N5) * z) / PRECISE_UNIT + N4) * z) / PRECISE_UNIT + N3);
        return (((((numeratorInner * z) / PRECISE_UNIT + N2) * z) / PRECISE_UNIT + N1) * z) / PRECISE_UNIT + N0;
    }

    /**
     * @dev Helper for _stdNormalCDF
     */
    function _stdNormalCDFDenom(uint256 z) internal pure returns (uint256) {
        uint256 denominatorInner =
            ((((((M7 * z) / PRECISE_UNIT + M6) * z) / PRECISE_UNIT + M5) * z) / PRECISE_UNIT + M4);
        return (
            ((((((denominatorInner * z) / PRECISE_UNIT + M3) * z) / PRECISE_UNIT + M2) * z) / PRECISE_UNIT + M1) * z
        ) / PRECISE_UNIT + M0;
    }

    /**
     * @dev Converts an integer number of seconds to a fractional number of years.
     */
    function _annualise(uint256 secs) internal pure returns (uint256 yearFraction) {
        return secs.divideDecimalRoundPrecise(SECONDS_PER_YEAR);
    }
}
