pragma solidity ^0.8.18;

import "forge-std/Test.sol";

//LIBRARIES
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ConvertDecimals} from "../libraries/ConvertDecimals.sol";
//IVX INTERFACES
import {IIVXRiskEngine} from "../interface/margin/IIVXRiskEngine.sol";
import {IIVXDiem} from "../interface/options/IIVXDiem.sol";
import {IIVXPortfolio} from "../interface/margin/IIVXPortfolio.sol";
import {IIVXLP} from "../interface/liquidity/IIVXLP.sol";
import {IIVXExchange} from "../interface/exchange/IIVXExchange.sol";
import {IIVXOracle} from "../interface/periphery/IIVXOracle.sol";

/**
 * @title IVXPortolio
 * @notice Contract to store a user's open option positions and closed trades
 * @author gradient (@gradientIVX), MiguelBits (@MiguelBits)
 */
contract IVXPortfolio is IIVXPortfolio, Initializable, ReentrancyGuard, ERC1155Holder {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                 VARIABLES
    //////////////////////////////////////////////////////////////*/

    address diemContract;
    IIVXLP LP;
    IIVXExchange Exchange;
    IIVXRiskEngine RiskEngine;
    IIVXOracle Oracle;
    address public marginUser;
    uint256[] openOptionIds; //array of open option ids

    /*//////////////////////////////////////////////////////////////
                                 MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 optionId => IIVXDiem.Trade) optionIdTrade;

    /*//////////////////////////////////////////////////////////////
                                 MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAllowedContracts(address _contract1, address _contract2) {
        if (msg.sender != _contract1 || msg.sender != _contract2) {
            revert IVXPortfolio_OnlyAllowedContracts(msg.sender, _contract1, _contract2);
        }
        _;
    }

    modifier onlyAllowedContract(address _contract) {
        if (msg.sender != _contract) revert IVXPortfolio_OnlyAllowedContract(msg.sender, _contract);
        _;
    }

    modifier onlyMarginUser() {
        if (msg.sender != marginUser) revert IVXPortfolio_OnlyMarginUser(msg.sender, marginUser);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/
    function initialize(
        address _diem,
        address _lp,
        IIVXRiskEngine _RiskEngine,
        IIVXExchange _exchange,
        address _marginUser
    ) public payable initializer {
        if (_diem == address(0)) revert AddressZero();
        diemContract = _diem;
        RiskEngine = _RiskEngine;
        Exchange = IIVXExchange(_exchange);
        marginUser = _marginUser;
        LP = IIVXLP(_lp);
        Oracle = IIVXOracle(RiskEngine.oracle());

        emit PortfolioInitialized(_diem, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                                 MARGIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Add margin to a user's balance for supported assets
    /// @param _asset The asset to add margin for
    /// @param _amount The amount of margin to add
    function increaseMargin(address _asset, uint256 _amount) external nonReentrant {
        if (RiskEngine.isSupportedAsset(_asset) == false) {
            revert AssetNotSupported(_asset);
        }

        ERC20(_asset).safeTransferFrom(msg.sender, address(this), _amount);

        emit MarginAdded(marginUser, _asset, _amount);
    }

    /// @notice Remove margin from various assets from a user's balance for supported assets
    /// @param _totalAmountOut The total amount of margin to remove, in 1e18 decimals
    function removeMargin(address _receiver, uint256 _totalAmountOut) external onlyAllowedContract(diemContract) {
        address[] memory _assets = RiskEngine.getSupportedAssets();
        ERC20 collateral = LP.collateral();
        address _tokenOut = address(collateral);

        if (_totalAmountOut > RiskEngine.getEffectiveMargin(this)) {
            revert IVXPortfolio_NotEnoughMargin();
        }

        for (uint256 i = 0; i < _assets.length; ++i) {
            if (_totalAmountOut == 0) break; //if totalAmountOut is 0, we have enough margin
            uint256 amountToRemove; //Dollar margin to remove in 1e18 decimals
            uint256 balanceInDollars = RiskEngine.getEffectiveDollarMarginForAsset(_assets[i], userMarginBalance(_assets[i])); //in 1e18 decimals

            if (balanceInDollars < _totalAmountOut) {
                //if balance is less than amount, set removing amount to balance and subtract from totalAmountOut
                _totalAmountOut -= balanceInDollars;
                amountToRemove = balanceInDollars;
            } else {
                //if balance is greater than amount, set totalAmountOut to 0
                amountToRemove = _totalAmountOut;
                _totalAmountOut = 0;
            }

            if (_assets[i] != _tokenOut) {
                //if asset is not collateral, swap to collateral
                ERC20(_assets[i]).safeApprove(address(Exchange), amountToRemove);
                Exchange.swapOnUniswap(
                    _assets[i],
                    _tokenOut,
                    Oracle.getAmountInAsset(amountToRemove, _assets[i]), //in asset decimals,
                    0, //can't avoid slippage
                    _receiver
                );
            } else {
                //if asset is collateral, transfer to receiver
                collateral.safeTransfer(_receiver, ConvertDecimals.convertFrom18AndRoundUp(amountToRemove, ERC20(_tokenOut).decimals()));
            }

            emit MarginRemoved(msg.sender, _assets[i], amountToRemove);
        }
    }

    /// @notice Remove margin from various assets from a user's balance for supported assets
    /// @dev _assets and _amounts must be the same length, and in the respective order
    /// @param _assets The assets to remove margin for
    /// @param _amounts The amounts of margin to remove, in asset decimals
    function decreaseMargin(address[] calldata _assets, uint256[] calldata _amounts)
        external
        onlyMarginUser
        nonReentrant
    {
        uint256 assetsLength = RiskEngine.assetsLength();
        require(_assets.length == _amounts.length, "assets and amounts arrays must be the same length");
        require(_assets.length <= assetsLength, "cannot loop more than the number of supported assets"); //prevention of ddos attack

        uint256 arraylength = _assets.length;
        for (uint256 i; i < arraylength; ++i) {
            if (RiskEngine.isSupportedAsset(_assets[i]) == false) {
                revert AssetNotSupported(_assets[i]);
            }

            ERC20(_assets[i]).safeTransfer(marginUser, _amounts[i]);

            emit MarginRemoved(msg.sender, _assets[i], _amounts[i]);
        }

        if (IIVXDiem(diemContract).isPortfolioLiquidatable(this)) {
            revert IVXPortfolio_PortfolioLiquidatable();
        }
    }

    /// @notice Withdraw assets when assets are delisted from collateral support
    /// @param _asset The asset to withdraw
    function withdrawAssets(address _asset) external {
        //is not supported asset
        if (RiskEngine.isSupportedAsset(_asset)) {
            revert AssetSupported(_asset);
        }
        uint256 _amount = userMarginBalance(_asset);

        ERC20(_asset).safeTransfer(marginUser, _amount);

        emit MarginWithdrawn(marginUser, _asset, _amount);
    }

    /// @notice function is called when liquidation requirements are met and there is not enough margin to cover losses
    function liquidate() external onlyAllowedContract(diemContract) {
        address[] memory _assets = RiskEngine.getSupportedAssets();
        ERC20 collateral = LP.collateral();
        address _tokenOut = address(collateral);

        for (uint256 i = 0; i < _assets.length; ++i) {
            //convert minAmountOut to assets decimals
            uint256 balance = userMarginBalance(_assets[i]);
            if (balance == 0) continue;

            if (_assets[i] != _tokenOut) {
                ERC20(_assets[i]).safeApprove(address(Exchange), balance);
                Exchange.swapOnUniswap(
                    _assets[i],
                    _tokenOut,
                    balance,
                    0, //can't avoid slippage
                    diemContract
                );
            } else {
                collateral.safeTransfer(diemContract, balance);
            }

            emit MarginRemoved(msg.sender, _assets[i], balance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 PORTFOLIO
    //////////////////////////////////////////////////////////////*/

    function userMarginBalance(address _asset) public view returns (uint256) {
        return ERC20(_asset).balanceOf(address(this));
    }

    function addTrade(uint256 _optionId, IIVXDiem.Trade memory _trade) external onlyAllowedContract(diemContract) {
        optionIdTrade[_optionId] = _trade;
        openOptionIds.push(_optionId);
    }

    function updateTrade(uint256 _optionId, IIVXDiem.Trade memory _trade) external onlyAllowedContract(diemContract) {
        optionIdTrade[_optionId] = _trade;
    }

    function closeTrade(uint256 _optionId) external onlyAllowedContract(diemContract) {
        IIVXDiem.Trade memory traded = optionIdTrade[_optionId];
        traded.timestamp = 0;
        traded.contractsOpen = 0;
        traded.borrowedAmount = 0;
        optionIdTrade[_optionId] = traded;

        //remove optionId from openOptionIds
        uint256 openOptionIdsLength = openOptionIds.length;
        for (uint256 i; i < openOptionIdsLength; ++i) {
            if (openOptionIds[i] == _optionId) {
                openOptionIds[i] = openOptionIds[openOptionIdsLength - 1];
                openOptionIds.pop();
                break;
            }
        }
    }

    function getOptionIdTrade(uint256 _id) external view returns (IIVXDiem.Trade memory) {
        return optionIdTrade[_id];
    }

    function getOpenOptionIds() external view returns (uint256[] memory) {
        return openOptionIds;
    }

    /*//////////////////////////////////////////////////////////////
                                 EXCHANGE
    //////////////////////////////////////////////////////////////*/

    function swapMargin(address _assetIn, address _assetOut, uint256 _amountIn, uint256 _amountOut)
        external
        nonReentrant
    {
        if (msg.sender != marginUser || msg.sender != diemContract) {
            revert IVXPortfolio_OnlyAllowedContracts(msg.sender, marginUser, diemContract);
        }

        //require asset in and asset out is supported
        if (RiskEngine.isSupportedAsset(_assetIn) == false) {
            revert AssetNotSupported(_assetIn);
        }
        if (RiskEngine.isSupportedAsset(_assetOut) == false) {
            revert AssetNotSupported(_assetOut);
        }

        require(_amountIn <= userMarginBalance(_assetIn), "cannot swap more than the balance");

        ERC20(_assetIn).safeApprove(address(Exchange), _amountIn);
        uint256 amountOut = Exchange.swapOnUniswap(_assetIn, _assetOut, _amountIn, _amountOut, address(this));

        emit MarginSwapped(msg.sender, _assetIn, _assetOut, _amountIn, amountOut);
    }

    //////////////////////////////////
    /// GMX CROSS MARGIN FUNCTIONS ///
    //////////////////////////////////
}
