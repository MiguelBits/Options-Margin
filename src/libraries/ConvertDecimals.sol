//SPDX-License-Identifier: ISC
pragma solidity ^0.8.16;

// Libraries
import "./math/Math.sol";

/**
 * @title ConvertDecimals
 * @dev Contract to convert amounts to and from erc20 tokens to 18 dp.
 */
library ConvertDecimals {
    /// @dev Converts amount from token native dp to 18 dp. This cuts off precision for decimals > 18.
    function convertTo18(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        return (amount * 1e18) / (10 ** decimals);
    }

    /// @dev Converts amount from 18dp to token.decimals(). This cuts off precision for decimals < 18.
    function convertFrom18(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        return (amount * (10 ** decimals)) / 1e18;
    }

    /// @dev Converts amount from a given precisionFactor to 18 dp. This cuts off precision for decimals > 18.
    function normaliseTo18(uint256 amount, uint256 precisionFactor) internal pure returns (uint256) {
        return (amount * 1e18) / precisionFactor;
    }

    // Loses precision
    /// @dev Converts amount from 18dp to the given precisionFactor. This cuts off precision for decimals < 18.
    function normaliseFrom18(uint256 amount, uint256 precisionFactor) internal pure returns (uint256) {
        return (amount * precisionFactor) / 1e18;
    }

    /// @dev Ensure a value converted from 18dp is rounded up, to ensure the value requested is covered fully.
    function convertFrom18AndRoundUp(uint256 amount, uint8 assetDecimals)
        internal
        pure
        returns (uint256 amountConverted)
    {
        // If we lost precision due to conversion we ensure the lost value is rounded up to the lowest precision of the asset
        if (assetDecimals < 18) {
            // Taking the ceil of 10^(18-decimals) will ensure the first n (asset decimals) have precision when converting
            amount = Math.ceil(amount, 10 ** (18 - assetDecimals));
        }
        amountConverted = ConvertDecimals.convertFrom18(amount, assetDecimals);
    }

    /// @dev Ensure a value converted from 18dp is rounded down, to ensure the value requested is covered fully.
    function convertFrom18AndRoundDown(uint256 amount, uint8 assetDecimals)
        internal
        pure
        returns (uint256 amountConverted)
    {
        // If we lost precision due to conversion we ensure the lost value is rounded up to the lowest precision of the asset
        if (assetDecimals < 18) {
            // Taking the ceil of 10^(18-decimals) will ensure the first n (asset decimals) have precision when converting
            amount = Math.floor(amount, 10 ** (assetDecimals));
        }
        amountConverted = ConvertDecimals.convertFrom18(amount, assetDecimals);
    }

    /// @dev convert to 30 decimals
    /// @param amount amount to convert, must be in 18 decimals
    function convertToGMXSpotDecimals(uint256 amount) internal pure returns(uint256) {
        return amount * 1e12;
    }
}
