pragma solidity ^0.8.18;

import {IIVXDiem} from "../options/IIVXDiem.sol";

interface IIVXPortfolio {
    /*//////////////////////////////////////////////////////////////
                                STRUCTURES
    //////////////////////////////////////////////////////////////*/

    struct AssetMargin {
        address asset;
        uint256 amount;
    }

    struct TradeDetails {
        address[] path;
        address indexAsset;
        address collateralAsset;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptableSpot;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PortfolioInitialized(address indexed diemContract, address portfolio);
    event MarginAdded(address indexed user, address indexed asset, uint256 amount);
    event MarginRemoved(address indexed user, address indexed asset, uint256 amount);
    event MarginWithdrawn(address indexed user, address indexed asset, uint256 amount);
    event MarginSwapped(
        address indexed user, address indexed assetFrom, address indexed assetTo, uint256 amountFrom, uint256 amountTo
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error IVXPortfolio_OnlyMarginUser(address sender, address user);
    error IVXPortfolio_OnlyAllowedContract(address sender, address allowedContract);
    error IVXPortfolio_OnlyAllowedContracts(address sender, address contract1, address contract2);
    error IVXPortfolio_NotEnoughMargin();
    error AssetSupported(address asset);
    error UnsupportedAsset(address asset);
    error SupportedAsset(address asset);
    error AddressZero();
    error AssetNotSupported(address asset);
    error IVXPortfolio_PortfolioLiquidatable();

    function marginUser() external view returns (address);
    function getOpenOptionIds() external view returns (uint256[] memory);
    function userMarginBalance(address _asset) external view returns (uint256);
    function addTrade(uint256 _optionId, IIVXDiem.Trade memory _trade) external;
    function updateTrade(uint256 _optionId, IIVXDiem.Trade memory _trade) external;
    function swapMargin(address _assetFrom, address _assetTo, uint256 _amountFrom, uint256 _amountTo) external;
    function increaseMargin(address _asset, uint256 _amount) external;
    function decreaseMargin(address[] calldata _assets, uint256[] calldata _amounts) external;
    function removeMargin(address _receiver, uint256 _minAmountOut) external;
    function liquidate() external;
    function getOptionIdTrade(uint256 _optionId) external view returns (IIVXDiem.Trade memory _trade);
    function withdrawAssets(address asset) external;
    function closeTrade(uint256 _optionId) external;
    // function increasePosition(TradeDetails calldata trade ) external payable returns (bytes32);
}
