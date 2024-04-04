// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../IAggregatorV3.sol";

interface IIVXOracle {
    struct EncodedData {
        uint256 beta;
        uint256 alpha;
    }

    struct PricingInputs {
        uint256 spot;
        uint256 volatility;
        int256 riskFreeRate;
    }

    function assetPriceFeed(address _asset) external view returns (IAggregatorV3);
    function getOraclePrice(address _asset) external view returns (int256);
    function getSpotPrice(address _asset) external view returns (uint256);
    function getVolatility(address _asset, uint256 _strike) external view returns (uint256);
    function getAmountPriced(uint256 _amount, address _asset) external view returns (uint256);
    function getAmountInAsset(uint256 _amount, address _asset) external view returns (uint256);
    function getValuePriced(uint256 _amount, address _asset) external view returns (uint256);
    function getPricingInputs(address asset, uint256 strike) external view returns (PricingInputs memory);
    function getRiskFreeRate(address _asset) external view returns (int256);
    function getSpotPriceAtTime(address _asset, uint256 _time) external view returns (uint256 spotPrice);
    function checkAssetStrikeSupported(address _asset, uint256 _strike) external view;
    function getSpotPriceForGMXv2Hedger(address _asset, bool _isLong) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event StrikeVolatilitySet(address indexed asset, uint256 strike, uint256 vol);
    event AssetPriceFeedSet(address indexed asset, address indexed priceFeed);
    event AssetDataUpdated(address indexed asset, EncodedData data);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error UnsupportedOracleAsset(address _asset);
    error UnsupportedOracleRiskFreeRate(address _asset);
    error UnsupportedOracleVolatility(address _asset, uint256 _strike);
    error UnsupportedOracleData(address _asset);
    error IVXOracle_getSpotPriceAtTime_NotFound(address _asset, uint256 _time);
    error ZeroAddress();
    error RoundIDOutdated();
    error OraclePriceZero();
    error SequencerDown();
    error GracePeriodNotOver();
    error SlippageNotSetForAsset(address _asset);
}
