pragma solidity ^0.8.18;

import {IIVXDiem} from "../options/IIVXDiem.sol";
import {IIVXPortfolio} from "./IIVXPortfolio.sol";
import {IIVXOracle} from "../periphery/IIVXOracle.sol";
interface IIVXRiskEngine {
    error IVXPortfolioAlreadyExists();

    struct AssetAttributes {
        uint16 collateralFactor;
        MarginFactors marginFactors;
        ShockLossFactors shockLossFactors;
    }

    struct MarginFactors {
        uint256 marginFactorA;
        uint256 marginFactorB;
        uint256 marginFactorC;
        uint256 marginFactorD;
        uint256 marginFactorE;
    }

    struct ShockLossFactors {
        uint256 ivFactor;
        uint256 priceFactor;
    }

    struct MarginParams {
        uint256[] contractsTraded; //contracts open
        uint256[] X; //spot prices
        uint256[] Y; //premiums
        address[] asset;
        uint256[] strikes;
        uint256[] borrowAmount;
        uint256 interestRate;
        uint256[] timeOpen;
        int256 orderLoss;
        int256[] deltas;
        int256[] vegas;
    }

    struct ShockLossVariables {
        int256 deltaShock_negative;
        int256 deltaShock_positive;
        int256 vegaShock_negative;
        int256 vegaShock_positive;
    }

    event CollateralAssetAdded(address indexed asset, AssetAttributes factors);
    event CollateralAssetRemoved(address indexed asset);

    function getSupportedAssets() external view returns (address[] memory);
    function getAssetAttributes(address asset) external view returns (AssetAttributes memory);
    function getShockLossFactors(address _asset) external view returns (uint256 ivFactor, uint256 priceFactor);
    function assetsLength() external view returns (uint256);
    function assetsSupported(uint256 i) external view returns (address);
    function addAsset(address _asset, AssetAttributes memory factors, bool _supported) external;
    function removeAsset(address _asset) external;
    function isSupportedAsset(address _asset) external view returns (bool);
    function userIVXPortfolio(address _user) external view returns (IIVXPortfolio);
    function getEffectiveMargin(IIVXPortfolio _user) external view returns (uint256);
    function portfolioDollarMargin(IIVXPortfolio portfolio) external view returns (uint256);
    function getEffectiveMarginAmountOfAsset(address _asset, uint256 _amount) external view returns (uint256);
    function createMarginAccount() external returns (IIVXPortfolio);
    function calculateBorrowFee(uint256 borrowAmount, uint256 interestRate, uint256 _timeOpen)
        external
        view
        returns (uint256);
    function isEligibleForLiquidation(IIVXPortfolio portfolio, MarginParams calldata _params)
        external
        view
        returns (bool);
    function healthFactor(IIVXPortfolio portfolio, MarginParams calldata _params) external view returns (uint256);
    function positionMaintenanceMargin(uint256 X, uint256 Y, address _asset) external view returns (uint256 margin);
    function oracle() external view returns (IIVXOracle);
    function getEffectiveDollarMarginForAsset(address _asset, uint256 _amount) external view returns (uint256);
}
