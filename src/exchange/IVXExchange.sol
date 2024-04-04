pragma solidity ^0.8.18;

import {TransferHelper} from "../libraries/TransferHelper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ConvertDecimals} from "../libraries/ConvertDecimals.sol";
import {DecimalMath} from "../libraries/math/DecimalMath.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

//INTERFACES FOR EXCHANGES
import {IUniswap} from "../interface/exchange/IUniswap.sol";
import {IVault} from "../interface/exchange/gmx/v1/IVault.sol";
import {IPositionRouter} from "../interface/exchange/gmx/v1/IPositionRouter.sol";
import {IRouter} from "../interface/exchange/gmx/v1/IRouter.sol";

//INTERFACES FOR IVX
import {IIVXOracle} from "../interface/periphery/IIVXOracle.sol";
import {IIVXLP} from "../interface/liquidity/IIVXLP.sol";
import {IIVXExchange} from "../interface/exchange/IIVXExchange.sol";
import {IIVXPortfolio} from "../interface/margin/IIVXPortfolio.sol";

contract IVXExchange is Ownable, IIVXExchange {
    using DecimalMath for uint256;
    using SafeCast for uint256;

    mapping(address asset => address gmxMarket) public gmxAssetMarket;

    //addresses
    address public UniswapV3;
    address public QuoteUniswap;
    address public gmxRouter;
    IPositionRouter public gmxPositionRouter;
    IVault gmxVault;

    // For this example, we will set the pool fee to 0.3%.
    uint24 public constant poolFee = 3000;

    uint256 public constant GMX_PRICE_PRECISION = 10 ** 30;
    // uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    bytes32 public referralCode = bytes32("IVX");

    //contracts
    IUniswap public UniswapV3_contract;
    IUniswap public QuoteUniswap_contract;
    IIVXOracle public ivxOracle;

    function setGMXContracts(address _gmxRouter, address _gmxPositionRouter) external onlyOwner {
        gmxRouter = _gmxRouter;
        gmxPositionRouter = IPositionRouter(_gmxPositionRouter);
        gmxVault = IVault(gmxPositionRouter.vault());
    }

    function setIVXContracts(address _ivxOracle) external onlyOwner {
        ivxOracle = IIVXOracle(_ivxOracle);
    }

    function setReferralCode(bytes32 _referralCode) external onlyOwner {
        referralCode = _referralCode;
    }

    /*//////////////////////////////////////////////////////////////
                                 UNISWAP
    //////////////////////////////////////////////////////////////*/

    ///@notice function to initialize Router addresses
    ///@param _UniswapV3 address of UniswapV3 Router
    function setUniswapV3(address _UniswapV3, address _QuoteUniswap) external onlyOwner {
        UniswapV3 = _UniswapV3;
        QuoteUniswap = _QuoteUniswap;

        UniswapV3_contract = IUniswap(_UniswapV3);
        QuoteUniswap_contract = IUniswap(_QuoteUniswap);
    }

    ///@notice function to swap tokens on Uniswap and choose the best price
    ///@param _tokenIn address of token to swap
    ///@param _tokenOut address of token to receive
    ///@param _amountIn amount of token to swap
    ///@param _amountOut minimum amount of token to receive
    function swapOnUniswap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut,
        address _recipient
    ) external returns (uint256 amountOut) {
        TransferHelper.safeTransferFrom(_tokenIn, msg.sender, address(this), _amountIn);
        TransferHelper.safeApprove(_tokenIn, UniswapV3, _amountIn);

        IUniswap.ExactInputSingleParams memory params = IUniswap.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: poolFee,
            recipient: _recipient,
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: _amountOut,
            sqrtPriceLimitX96: 0
        });

        ///@dev swap on Uniswap V3
        amountOut = UniswapV3_contract.exactInputSingle(params);
    }

    /*//////////////////////////////////////////////////////////////
                                GMX
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev returns the execution fee plus the cost of the gas callback
     */
    function getExecutionFee() public view returns (uint256) {
        return gmxPositionRouter.minExecutionFee();
    }

    function convertToGMXPrecision(uint256 amt) public pure returns (uint256) {
        return ConvertDecimals.normaliseFrom18(amt, GMX_PRICE_PRECISION);
    }

    function convertFromGMXPrecision(uint256 amt) public pure returns (uint256) {
        return ConvertDecimals.normaliseTo18(amt, GMX_PRICE_PRECISION);
    }

    function getPositionFee(uint256 size, uint256 sizeDelta, uint256 entryFundingRate, address asset)
        external
        view
        returns (uint256)
    {
        // pass in sizes in 18 decimals, will return funding fee and position fee in 18 decimals
        uint256 fundingFee = gmxVault.getFundingFee(asset, size, entryFundingRate);
        return fundingFee + gmxVault.getPositionFee(sizeDelta);
    }

    /**
     * @dev Gets the current open positions. Will return an empty object where a position is not open. First will be long
     * Second will be short.
     */
    function getPositions(address _sender, address collateralAsset, address indexAsset)
        public
        view
        returns (CurrentPositions memory positions)
    {
        TradeInfo memory tradeInfo = TradeInfo({collateralAsset: collateralAsset, indexAsset: indexAsset, isLong: true});
        PositionDetails memory longResult = getPosition(_sender, tradeInfo);
        tradeInfo.isLong = false;
        PositionDetails memory shortResult = getPosition(_sender, tradeInfo);

        uint256 amountOpen = 0;
        if (longResult.size > 0) {
            amountOpen += 1;
        }
        if (shortResult.size > 0) {
            amountOpen += 1;
        }

        bool isLong = longResult.size > shortResult.size;

        return CurrentPositions({
            longPosition: longResult,
            shortPosition: shortResult,
            amountOpen: amountOpen,
            isLong: isLong
        });
    }

    function hasPendingPositionRequest(bytes32 key) public view returns (bool) {
        if (key == bytes32(0)) {
            return false;
        }
        if (_hasPendingIncrease(key)) {
            return true;
        }
        if (_hasPendingDecrease(key)) {
            return true;
        }
        return false;
    }

    /**
     * @dev returns true if there is pending increase position order on GMX
     */
    function _hasPendingIncrease(bytes32 key) internal view returns (bool hasPending) {
        bytes memory data = abi.encodeWithSelector(gmxPositionRouter.increasePositionRequests.selector, key);

        (bool success, bytes memory returndata) = address(gmxPositionRouter).staticcall(data);
        if (!success) {
            // revert GetGMXVaultError(address(this));
        }

        // parse account from the first 32 bytes of returned data
        // same as: (address account,,,,,,,,,,,,) = gmxPositionRouter.increasePositionRequests(pendingOrderKey);
        address account;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            account := mload(add(returndata, 32))
        }
        return account != address(0);
    }

    /**
     * @dev returns true if there is pending decrease position order on GMX
     */
    function _hasPendingDecrease(bytes32 key) internal view returns (bool) {
        bytes memory data = abi.encodeWithSelector(gmxPositionRouter.decreasePositionRequests.selector, key);

        (bool success, bytes memory returndata) = address(gmxPositionRouter).staticcall(data);
        if (!success) {
            // revert GetGMXVaultError(address(this));
        }

        // parse account from the first 32 bytes of returned data
        // same as: (address account,,,,,,,,,,,,,) = gmxPositionRouter.decreasePositionRequests(pendingOrderKey);
        address account;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            account := mload(add(returndata, 32))
        }
        return account != address(0);
    }

    /**
     * @dev get position detail that includes unrealised PNL
     */
    function getPosition(address _sender, TradeInfo memory tradeInfo) public view returns (PositionDetails memory) {
        (
            uint256 size,
            uint256 collateral,
            uint256 averagePrice,
            uint256 entryFundingRate, // uint reserveAmount: GMX internal variable to keep track of collateral reserved for position // uint realised profit: historical pnl // bool hasProfit: if the vault had previously realised profit or loss
            ,
            ,
            ,
            uint256 lastIncreasedTime
        ) = gmxVault.getPosition(_sender, tradeInfo.collateralAsset, tradeInfo.indexAsset, tradeInfo.isLong);

        int256 unrealisedPnl = 0;
        if (averagePrice > 0) {
            // getDelta will revert if average price == 0;
            (bool hasUnrealisedProfit, uint256 absUnrealisedPnl) =
                gmxVault.getDelta(tradeInfo.indexAsset, size, averagePrice, tradeInfo.isLong, lastIncreasedTime);

            if (hasUnrealisedProfit) {
                unrealisedPnl = convertFromGMXPrecision(absUnrealisedPnl).toInt256();
            } else {
                unrealisedPnl = -convertFromGMXPrecision(absUnrealisedPnl).toInt256();
            }
        }

        return PositionDetails({
            size: convertFromGMXPrecision(size),
            collateral: convertFromGMXPrecision(collateral),
            averagePrice: convertFromGMXPrecision(averagePrice),
            entryFundingRate: entryFundingRate, // store in initial percision, will be used in vault.getFundingFee
            unrealisedPnl: unrealisedPnl,
            lastIncreasedTime: lastIncreasedTime,
            isLong: tradeInfo.isLong
        });
    }

    /**
     * @dev get total value from long and short GMX positions.
     * @return total value in USD term.
     */
    function getAllPositionsValue(address _sender, address collateralAsset, address indexAsset)
        external
        view
        returns (uint256)
    {
        CurrentPositions memory positions = getPositions(_sender, collateralAsset, indexAsset);
        return _getAllPositionsValue(positions);
    }

    /**
     * @dev No fees are added in here, as they get re-adjusted every time collateral is adjusted
     * @return value in USD term
     *
     */
    function _getAllPositionsValue(CurrentPositions memory positions) internal pure returns (uint256) {
        uint256 totalValue = 0;

        if (positions.longPosition.size > 0) {
            PositionDetails memory position = positions.longPosition;
            int256 longPositionValue = position.collateral.toInt256() + position.unrealisedPnl;

            // Ignore the case when negative PnL covers collateral (insolvency) as the value is 0
            if (longPositionValue > 0) {
                totalValue += uint256(longPositionValue);
            }
        }

        if (positions.shortPosition.size > 0) {
            PositionDetails memory position = positions.shortPosition;
            int256 shortPositionValue = position.collateral.toInt256() + position.unrealisedPnl;

            // Ignore the case when negative PnL covers collateral (insolvency) as the value is 0
            if (shortPositionValue > 0) {
                totalValue += uint256(shortPositionValue);
            }
        }
        return totalValue;
    }
}
