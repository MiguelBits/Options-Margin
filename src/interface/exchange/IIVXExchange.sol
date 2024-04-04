// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./gmx/v1/IPositionRouter.sol";

interface IIVXExchange {
    function swapOnUniswap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut,
        address _receiver
    ) external returns (uint256 amountOut);
    function referralCode() external view returns (bytes32);

    // Note: whenever these values are used, they have already been normalised to 1e18
    // exception: entryFundingRate
    struct PositionDetails {
        uint256 size;
        uint256 collateral;
        uint256 averagePrice;
        uint256 entryFundingRate;
        // int256 realisedPnl;
        int256 unrealisedPnl;
        uint256 lastIncreasedTime;
        bool isLong;
    }

    struct CurrentPositions {
        PositionDetails longPosition;
        PositionDetails shortPosition;
        uint256 amountOpen;
        bool isLong; // only valid if amountOpen == 1
    }

    struct TradeInfo {
        address collateralAsset;
        address indexAsset;
        bool isLong;
    }

    function gmxRouter() external view returns (address);
    function gmxPositionRouter() external view returns (IPositionRouter);
    function getExecutionFee() external view returns (uint256);
    function getPositions(address _sender, address collateralAsset, address indexAsset)
        external
        view
        returns (CurrentPositions memory);
    function hasPendingPositionRequest(bytes32 key) external view returns (bool);
    function getPosition(address _sender, TradeInfo memory tradeInfo) external view returns (PositionDetails memory);
    function getPositionFee(uint256 size, uint256 sizeDelta, uint256 entryFundingRate, address asset)
        external
        view
        returns (uint256);
    function getAllPositionsValue(address _sender, address collateralAsset, address indexAsset)
        external
        view
        returns (uint256);
}
