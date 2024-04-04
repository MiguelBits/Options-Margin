// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Libraries
import "./math/SignedDecimalMath.sol";
import "./math/DecimalMath.sol";
import "./math/MathLib.sol";
import "./math/Math.sol";

/**
 * @title Binomial
 * @author gradient (@gradientIVX), MiguelBits (@MiguelBits)
 * @dev A library to compute the Binomial model implied price of options.
 */
library Binomial {
    uint256 private constant secondsInYear = 31536000;

    struct PricingInputs {
        uint256 secondsToExpiry;
        uint256 impliedVolatility;
        uint256 spotPrice;
        uint256 strikePrice;
        uint256 riskFreeRate;
        uint256 deltaT;
    }

    struct BinomialConstants {
        uint256 N;
        uint256 deltaTRiskFreeRate;
        uint256 p;
        uint256 q;
    }

    struct TerminalPayoffs {
        uint256[] callPayoffs;
        uint256[] putPayoffs;
    }

    struct BinomialConstantsAndSharePrices {
        BinomialConstants constants;
        uint256[] terminalSharePrices;
    }

    struct BinomialConstantsAndPayoffs {
        BinomialConstants constants;
        TerminalPayoffs terminalPayoffs;
    }

    struct BinomialConstantsTerminalPayoffs {
        BinomialConstants constants;
        uint256[] terminalPayoffs;
    }

    /// @dev Calculate the up and down factors for one timestep based on implied volatility and the risk-free rate
    function calculateTransitionFactors(uint256 deltaTImpliedVolatility) internal pure returns (uint256, uint256) {
        uint256 upFactor = MathLib.exp(int256(deltaTImpliedVolatility));
        return (upFactor, 1e36 / upFactor);
    }

    /// @dev Calculates the transition probabilities for a timestep based on the up and down factors
    function calculateTransitionProbabilities(
        uint256 deltaTRiskFreeRate,
        uint256 deltaTUpFactor,
        uint256 deltaTDownFactor
    ) internal pure returns (uint256 p, uint256 q) {
        p = (1e18 * (1e18 + deltaTRiskFreeRate - deltaTDownFactor)) / (deltaTUpFactor - deltaTDownFactor);
        q = 1e18 - p;
    }

    /// @dev Calculates the share prices at the terminal node
    /// @param spotPrice The current share price
    /// @param deltaTUpFactor The up factor
    /// @param deltaTDownFactor The down factor
    /// @param N The number of periods
    function calculateTerminalSharePrices(
        uint256 spotPrice,
        uint256 deltaTUpFactor,
        uint256 deltaTDownFactor,
        uint256 N
    ) internal pure returns (uint256[] memory) {
        uint256[] memory sharePrices = new uint256[](N + 1);
        sharePrices[0] = spotPrice * MathLib.rpow(deltaTDownFactor, N, 1e18) / (1e18);
        for (uint256 i = 1; i <= N; i++) {
            sharePrices[i] = (sharePrices[i - 1] * (deltaTUpFactor)) / (deltaTDownFactor);
        }
        return sharePrices;
    }

    /// @dev Calculates the payoffs of a European call option at the terminal node
    /// @param sharePrices The share prices at the terminal node
    /// @param strikePrice The strike price of the call option
    function calculateTerminalCallPayoffs(uint256[] memory sharePrices, uint256 strikePrice)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256 arraylength = sharePrices.length;
        uint256[] memory callPayoffs = new uint256[](arraylength);
        for (uint256 i = 0; i < arraylength; i++) {
            callPayoffs[i] = sharePrices[i] > strikePrice ? sharePrices[i] - strikePrice : 0;
        }
        return callPayoffs;
    }

    /// @dev Calculates the payoffs of a European call option at the terminal node
    /// @param sharePrices The share prices at the terminal node
    /// @param strikePrice The strike price of the call option
    function calculateTerminalPutPayoffs(uint256[] memory sharePrices, uint256 strikePrice)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256 arraylength = sharePrices.length;
        uint256[] memory putPayoffs = new uint256[](arraylength);
        // console.log("sharePrices.length",sharePrices.length);
        for (uint256 i = 0; i < arraylength; i++) {
            putPayoffs[i] = sharePrices[i] < strikePrice ? strikePrice - sharePrices[i] : 0;
        }
        return putPayoffs;
    }

    /// @dev Calculates the price of a European call option using the binomial pricing model with N-periods
    /// @notice This function is used to calculate both Call and Put options
    function priceNPeriodOption(BinomialConstantsAndPayoffs memory params) internal pure returns (uint256, uint256) {
        uint256 N = params.constants.N;
        uint256[][] memory callPriceVector = new uint256[][]((N + 1) ** 2);
        uint256[][] memory putPriceVector = new uint256[][]((N + 1) ** 2);

        // Initialize the inner arrays
        for (uint256 i = 0; i <= params.constants.N; ++i) {
            callPriceVector[i] = new uint256[](i + 1);
            putPriceVector[i] = new uint256[](i + 1);
        }

        // Set the final entry of callPriceVector to terminalPayoffs
        callPriceVector[N] = params.terminalPayoffs.callPayoffs;
        putPriceVector[N] = params.terminalPayoffs.putPayoffs;

        // Iterate through the callPriceVector, calculating the values of the previous row
        for (uint256 j = N - 1; j >= 0; --j) {
            for (uint256 i = 0; i <= j; ++i) {
                unchecked {
                    // Calculate the value of the current entry based on the next entries
                    callPriceVector[j][i] = (
                        params.constants.p * callPriceVector[j + 1][i]
                            + params.constants.q * callPriceVector[j + 1][i + 1]
                    ) / 1e18;
                    putPriceVector[j][i] = (
                        params.constants.p * putPriceVector[j + 1][i]
                            + params.constants.q * putPriceVector[j + 1][i + 1]
                    ) / 1e18;

                    callPriceVector[j][i] = callPriceVector[j][i] * 1e18 / (1e18 + params.constants.deltaTRiskFreeRate);
                    putPriceVector[j][i] = putPriceVector[j][i] * 1e18 / (1e18 + params.constants.deltaTRiskFreeRate);
                }
            }
            if (j == 0) break;
        }

        // Return the initial entry of callPriceVector
        return (callPriceVector[0][0], putPriceVector[0][0]);
    }

    /// @dev Calculates the price of a European call option using the binomial pricing model with N-periods
    /// @notice This function is used for Calls or Puts with the same parameters
    function priceNPeriodOption(BinomialConstantsTerminalPayoffs memory params) internal pure returns (uint256) {
        uint256 N = params.constants.N;
        uint256[][] memory priceVector = new uint256[][]((N + 1) ** 2);

        // Initialize the inner arrays
        for (uint256 i = 0; i <= N; i++) {
            priceVector[i] = new uint256[](i + 1);
        }

        // Set the final entry of callPriceVector to terminalPayoffs
        priceVector[N] = params.terminalPayoffs;

        // Iterate through the priceVector, calculating the values of the previous row
        for (uint256 j = N - 1; j >= 0; --j) {
            for (uint256 i = 0; i <= j; ++i) {
                unchecked {
                    // Calculate the value of the current entry based on the next entries
                    priceVector[j][i] = (
                        params.constants.p * priceVector[j + 1][i] + params.constants.q * priceVector[j + 1][i + 1]
                    ) / 1e18;
                    priceVector[j][i] = priceVector[j][i] * 1e18 / (1e18 + params.constants.deltaTRiskFreeRate);
                }
            }
            if (j == 0) break;
        }

        // Return the initial entry of callPriceVector
        return (priceVector[0][0]);
    }

    function optionPrices(PricingInputs memory inputs) internal pure returns (uint256 callPrice, uint256 putPrice) {
        BinomialConstantsAndSharePrices memory params = _optionPrices(inputs);

        BinomialConstantsAndPayoffs memory constants = BinomialConstantsAndPayoffs({
            constants: params.constants,
            terminalPayoffs: TerminalPayoffs({
                callPayoffs: calculateTerminalCallPayoffs(params.terminalSharePrices, inputs.strikePrice),
                putPayoffs: calculateTerminalPutPayoffs(params.terminalSharePrices, inputs.strikePrice)
            })
        });

        (callPrice, putPrice) = priceNPeriodOption(constants);
    }

    function callOptionPrices(PricingInputs memory inputs) internal pure returns (uint256 callPrice) {
        BinomialConstantsAndSharePrices memory params = _optionPrices(inputs);

        BinomialConstantsTerminalPayoffs memory constants = BinomialConstantsTerminalPayoffs({
            constants: params.constants,
            terminalPayoffs: calculateTerminalCallPayoffs(params.terminalSharePrices, inputs.strikePrice)
        });

        callPrice = priceNPeriodOption(constants);
    }

    function putOptionPrices(PricingInputs memory inputs) internal pure returns (uint256 putPrice) {
        BinomialConstantsAndSharePrices memory params = _optionPrices(inputs);

        BinomialConstantsTerminalPayoffs memory constants = BinomialConstantsTerminalPayoffs({
            constants: params.constants,
            terminalPayoffs: calculateTerminalPutPayoffs(params.terminalSharePrices, inputs.strikePrice)
        });

        putPrice = priceNPeriodOption(constants);
    }

    function _optionPrices(PricingInputs memory inputs)
        internal
        pure
        returns (BinomialConstantsAndSharePrices memory params)
    {
        unchecked {
            uint256 N = inputs.secondsToExpiry / inputs.deltaT;
            uint256 deltaTRiskFreeRate = (inputs.riskFreeRate * inputs.deltaT * 1e18 / secondsInYear) / 1e18;
            uint256 deltaTImpliedVolatility =
                inputs.impliedVolatility * Math._sqrt(inputs.deltaT * 1e18 / secondsInYear) / 1e9;
            (uint256 upFactor, uint256 downFactor) = calculateTransitionFactors(deltaTImpliedVolatility);

            uint256[] memory terminalSharePrices =
                calculateTerminalSharePrices(inputs.spotPrice, upFactor, downFactor, N);

            (uint256 p, uint256 q) = calculateTransitionProbabilities(deltaTRiskFreeRate, upFactor, downFactor);

            params = BinomialConstantsAndSharePrices({
                constants: BinomialConstants({N: N, deltaTRiskFreeRate: deltaTRiskFreeRate, p: p, q: q}),
                terminalSharePrices: terminalSharePrices
            });
        }
    }
}
