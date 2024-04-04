pragma solidity ^0.8.18;

interface IIVXHedger {
    error CollateralTransferFailed(address sender, uint256 amount, address recipient);
    error InteractionDelayNotExpired(
        // uint256 lastTimestamp, uint256 interactionDelay, uint256 currentTimestamp
    );
    error PositionRequestPending(address thiscontract, bytes32 pendingOrderKey);
    error GetGMXVaultError(address thiscontract);
    error NoQuoteReceivedFromLP(address thiscontract);
    error QuoteApprovalFailure(address thiscontract, address gmxRouter, uint256 collateralDelta);

    // event GMXPositionCallback(
    //     address thrower,
    //     bytes32 positionKey,
    //     bool isExecuted,
    //     bool isIncrease,
    //     CurrentPositions positions
    // );
    event QuoteReturnedToLP(address recipient, uint256 returnedAmount);
    event CollateralTransferFailedEvent(address sender, uint256 amount);
    event OrderPosted(
        address sender, bytes32 orderKey, uint256 collateralDelta, uint256 sizeDelta, bool isLong, bool isIncrease
    );
    event PositionUpdated(
        address sender, int256 currHedgeNetDelta, int256 expectedHedge, uint256 sizeDelta, bool isIncrease
    );
    event HedgerPosition(address sender, CurrentPositions position);
    event CollateralOrderPosted(address sender, bytes32 orderKey, bool isLong, int256 collateralDelta);

    struct HedgerParameters {
        uint256 interactionDelay;
        uint256 hedgeCap;
        uint256 acceptableSpotSlippage;
        uint256 deltaThreshold; // Bypass interaction delay if delta is outside of a certain range.
        uint256 targetLeverage; // target leverage ratio
    }

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

    function getTotalHedgingLiquidity(address asset) external view returns (uint256);
}
