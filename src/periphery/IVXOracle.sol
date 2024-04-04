// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {IIVXOracle} from "../interface/periphery/IIVXOracle.sol";
import "../interface/IAggregatorV3.sol";
import "../interface/IAggregatorV2V3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {ConvertDecimals} from "../libraries/ConvertDecimals.sol";
import {IDecimals} from "../interface/IDecimals.sol";

/**
 * @title IVXOracle
 * @notice Oracle to store asset volatility and pricing data, priced in 1e18 decimals
 * @author gradient (@gradientIVX), MiguelBits (@MiguelBits)
 */
contract IVXOracle is IIVXOracle, Ownable {
    using FixedPointMathLib for uint256;

    struct Decimals {
        uint8 asset;
        uint8 oracle;
    }

    mapping(address => EncodedData) public assetData;
    mapping(address => IAggregatorV3) public assetPriceFeed;
    mapping(address => Decimals) public assetDecimals;
    mapping(address asset => mapping(uint256 strike => uint256 vol)) public assetStrikeVols;
    mapping(address asset => int256 riskFreeRate) public assetRiskFreeRate;
    mapping(address asset => uint256 slippage) public assetGMXSlippage;

    IAggregatorV2V3Interface public sequencerUptimeFeed;
    uint256 private constant GRACE_PERIOD_TIME = 3600; // 1 hour

    constructor(address _l2Sequencer) {
        if (_l2Sequencer != address(0)) {
            sequencerUptimeFeed = IAggregatorV2V3Interface(_l2Sequencer);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 SETTERS
    //////////////////////////////////////////////////////////////*/

    function setGMXSpotSlippage(address _asset, uint256 _slippage) external onlyOwner {
        require(_slippage <= 1 ether, "IVXOracle: slippage must be <= 1 ether");
        assetGMXSlippage[_asset] = _slippage;
    }

    function setStrikeVolatility(address asset, uint256 strike, uint256 vols) external onlyOwner {
        assetStrikeVols[asset][strike] = vols;
    }

    function setStrikeVolatility(address asset, uint256[] memory strikes, uint256[] memory vols) external onlyOwner {
        uint256 strikesLength = strikes.length;
        require(strikesLength == vols.length, "IVXOracle: strikes and vols length mismatch");
        for (uint256 i; i < strikesLength; ++i) {
            assetStrikeVols[asset][strikes[i]] = vols[i];
            emit StrikeVolatilitySet(asset, strikes[i], vols[i]);
        }
    }

    function addAssetPriceFeed(address _asset, address _priceFeed) external onlyOwner {
        if (_asset == address(0) || _priceFeed == address(0)) revert ZeroAddress();
        assetPriceFeed[_asset] = IAggregatorV3(_priceFeed);
        assetDecimals[_asset] = Decimals(IDecimals(_asset).decimals(), IDecimals(_priceFeed).decimals());
        emit AssetPriceFeedSet(_asset, _priceFeed);
    }

    function setValues(address _asset, EncodedData memory decodedData) external onlyOwner {
        assetData[_asset] = decodedData;
        emit AssetDataUpdated(_asset, decodedData);
    }

    function setRiskFreeRate(address _asset, int256 _riskFreeRate) external onlyOwner {
        assetRiskFreeRate[_asset] = _riskFreeRate;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function checkAssetStrikeSupported(address _asset, uint256 _strike) public view {
        //oracle set
        if (address(assetPriceFeed[_asset]) == address(0)) revert UnsupportedOracleAsset(_asset);
        //risk free rate set
        if (assetRiskFreeRate[_asset] == 0) revert UnsupportedOracleRiskFreeRate(_asset);
        //volatility set for strike
        if (assetStrikeVols[_asset][_strike] == 0) revert UnsupportedOracleVolatility(_asset, _strike);
        //values not set for asset
        EncodedData memory data = assetData[_asset];
        if (data.beta == 0 || data.alpha == 0) revert UnsupportedOracleData(_asset);
    }

    function getPricingInputs(address asset, uint256 strike) external view returns (PricingInputs memory) {
        checkAssetStrikeSupported(asset, strike);
        uint256 spot = getSpotPrice(asset);
        uint256 volatility = getVolatility(asset, strike);
        int256 riskFreeRate = assetRiskFreeRate[asset];
        return PricingInputs(spot, volatility, riskFreeRate);
    }

    function getVolatility(address _asset, uint256 strike) public view returns (uint256) {
        checkAssetStrikeSupported(_asset, strike);
        EncodedData memory data = assetData[_asset];
        return data.beta.mulDivUp(assetStrikeVols[_asset][strike] + data.alpha, 1e18);
    }

    function getRiskFreeRate(address _asset) public view returns (int256) {
        return assetRiskFreeRate[_asset];
    }

    function _checkSequencer() internal view {
        if (address(sequencerUptimeFeed) != address(0)) {
            // Source: https://docs.chain.link/data-feeds/l2-sequencer-feeds/
            (
                /*uint80 roundID*/
                ,
                int256 answer,
                uint256 startedAt,
                /*uint256 updatedAt*/
                ,
                /*uint80 answeredInRound*/
            ) = sequencerUptimeFeed.latestRoundData();

            // Answer == 0: Sequencer is up
            // Answer == 1: Sequencer is down
            bool isSequencerUp = answer == 0;
            if (!isSequencerUp) {
                revert SequencerDown();
            }

            // Make sure the grace period has passed after the sequencer is back up.
            uint256 timeSinceUp = block.timestamp - startedAt;
            if (timeSinceUp <= GRACE_PERIOD_TIME) {
                revert GracePeriodNotOver();
            }
        }
    }

    function getOraclePrice(address _asset) public view returns (int256) {
        IAggregatorV3 priceFeed = assetPriceFeed[_asset];
        if (address(priceFeed) == address(0)) revert UnsupportedOracleAsset(_asset);

        _checkSequencer();

        (uint80 roundID, int256 price,,, uint80 answeredInRound) = priceFeed.latestRoundData();

        if (price <= 0) revert OraclePriceZero();

        if (answeredInRound < roundID) revert RoundIDOutdated();

        return price;
    }

    ///@notice Returns the spot price of an asset in USD 1e18 decimals
    function getSpotPrice(address _asset) public view returns (uint256) {
        int256 price = getOraclePrice(_asset);

        return ConvertDecimals.convertTo18(uint256(price), assetDecimals[_asset].oracle);
    }

    function getSpotPriceForGMXv2Hedger(address _asset, bool _isLong) external view returns (uint256) {
        uint256 price = getSpotPrice(_asset);
        uint256 slippage = assetGMXSlippage[_asset];
        if(slippage == 0) revert SlippageNotSetForAsset(_asset);
        
        if (_isLong) {
            price += price.mulDivDown(slippage, 1 ether);
        } else {
            price -= price.mulDivDown(slippage, 1 ether);
        }

        return ConvertDecimals.convertToGMXSpotDecimals(price);
    }

    ///@notice Returns the spot price of an asset in 1e18 decimals when the price was last updated before _time argument
    ///@dev A timestamp with zero value means the round is not complete and should not be used.
    /* Returns historical price for a round id.
     * roundId is NOT incremental. Not all roundIds are valid.
     * You must know a valid roundId before consuming historical data.
     */
    function getSpotPriceAtTime(address _asset, uint256 _time) external view returns (uint256) {
        _checkSequencer();

        IAggregatorV3 priceFeed = assetPriceFeed[_asset];
        if (address(priceFeed) == address(0)) revert UnsupportedOracleAsset(_asset);
        uint80 _roundID = uint80(priceFeed.latestRound());
        for (uint80 i = _roundID; i > 0; --i) {
            (, int256 answer,, uint256 updatedAt,) = priceFeed.getRoundData(i);
            if (updatedAt <= _time && answer > 0 && updatedAt != 0) {
                return ConvertDecimals.convertTo18(uint256(answer), assetDecimals[_asset].oracle);
            }
        }

        revert IVXOracle_getSpotPriceAtTime_NotFound(_asset, _time);
    }

    ///@notice Returns the spot price of an asset in asset decimals
    function getSpotPriceInAssetDecimals(address _asset) public view returns (uint256) {
        uint256 price = getSpotPrice(_asset);

        return ConvertDecimals.convertFrom18AndRoundDown(price, assetDecimals[_asset].asset);
    }

    /// @notice Returns the amount of asset priced in USD
    /// How much USD is _amount asset worth?
    /// @dev _amount is in asset decimals
    function getAmountPriced(uint256 _amount, address _asset) external view returns (uint256) {
        if (_amount == 0) return 0;
        //amount must be set to 18 decimals
        _amount = ConvertDecimals.convertTo18(_amount, assetDecimals[_asset].asset);
        return _amount.mulDivUp(getSpotPrice(_asset), 1e18);
    }

    /// @notice Returns the spot price of an asset in USD multiplied by _amount
    /// @param _amount in 1e18 decimals
    function getValuePriced(uint256 _amount, address _asset) external view returns (uint256) {
        if (_amount == 0) return 0;
        return _amount.mulDivUp(getSpotPrice(_asset), 1e18);
    }

    /// @notice Returns the amount in asset decimals of asset
    /// How much asset amount do I have of _amountPriced USD?
    /// @dev _amountPriced is 1e18 decimals * spot price, this means it is in USD
    function getAmountInAsset(uint256 _amountPriced, address _asset) external view returns (uint256 amount) {
        uint8 assetDecimalsValue = assetDecimals[_asset].asset;

        //_amountPriced must be set to assetDecimalsValue decimals
        if (assetDecimalsValue < 18) {
            _amountPriced = ConvertDecimals.convertFrom18AndRoundDown(_amountPriced, assetDecimalsValue);
        } else if (assetDecimalsValue > 18) {
            _amountPriced = _amountPriced.mulDivDown(10 ** assetDecimalsValue, 1e18);
        }
        //amount = amountPriced / spotPrice
        amount = _amountPriced.mulDivUp(1e18, getSpotPrice(_asset));
    }

}
