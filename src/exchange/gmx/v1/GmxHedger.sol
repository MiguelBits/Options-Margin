pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVault} from "../../../interface/exchange/gmx/v1/IVault.sol";
import {IPositionRouter} from "../../../interface/exchange/gmx/v1/IPositionRouter.sol";
import {IRouter} from "../../../interface/exchange/gmx/v1/IRouter.sol";
// import {IPositionRouterCallbackReceiver} from "../interface/exchange/gmx/v1/IPositionRouterCallbackReceiver.sol";
import {IDecimals} from "../../../interface/IDecimals.sol";
import {IIVXLP} from "../../../interface/liquidity/IIVXLP.sol";
import {IIVXOracle} from "../../../interface/periphery/IIVXOracle.sol";
import {ConvertDecimals} from "../../../libraries/ConvertDecimals.sol";
import {Math} from "../../../libraries/math/Math.sol";
import {DecimalMath} from "../../../libraries/math/DecimalMath.sol";
import {SignedDecimalMath} from "../../../libraries/math/SignedDecimalMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "../../../interface/IERC20.sol";
import {IIVXHedger} from "../../../interface/exchange/IIVXHedger.sol";

contract GmxHedger is Ownable, /*IPositionRouterCallbackReceiver,*/ ReentrancyGuard, IIVXHedger {
    using DecimalMath for uint256;
    using SignedDecimalMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 public constant GMX_PRICE_PRECISION = 10 ** 30;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    modifier onlyGMXKeeper() {
        require(msg.sender == address(positionRouter), "GMXFuturesPoolHedger: only GMX keeper can trigger callback");
        _;
    }

    /// @dev approve target for GMX position router
    IRouter public router;

    /// @dev GMX position router
    IPositionRouter public positionRouter;

    /// @dev GMX vault
    IVault public vault;

    IIVXLP public liquidityPool;
    IIVXOracle public oracle;

    // Parameters for managing the exposure and minimum liquidity of the hedger
    HedgerParameters public HedgerParams;

    uint256 lastInteraction;

    bytes32 public referralCode = bytes32("IVX");

    /// @dev key map to a GMX position. Could be key to increase or decrease position
    mapping(address asset => bytes32 positionKey) public pendingOrderKey;

    /// @dev the last timestamp that we post an order. (Timestamp that pendingOrderKey got updated)
    mapping(address asset => uint256 time) public lastOrderTimestamp;

    constructor() {}

    function init(IIVXLP _liquidityPool, IIVXOracle _oracle, IPositionRouter _positionRouter, IRouter _router)
        external
        onlyOwner
    {
        liquidityPool = _liquidityPool;
        oracle = _oracle;
        positionRouter = _positionRouter;
        router = _router;

        vault = IVault(positionRouter.vault());

        // approve position router as a plugin to enable opening positions
        _router.approvePlugin(address(positionRouter));
    }

    /**
     * @dev attempts to hedge the current delta of the pool by creating a pending order
     */
    function hedgeDelta(address asset) external payable nonReentrant {
        CurrentPositions memory positions = _getPositions(asset);
        int256 currentHedgedDelta = _getCurrentHedgedNetDelta(positions, asset);
        int256 expectedHedge = _getCappedExpectedHedge(asset);

        // Bypass interactionDelay if we want to set hedge to exactly 0
        if (
            expectedHedge != 0 && lastInteraction + HedgerParams.interactionDelay > block.timestamp
                && Math.abs(expectedHedge - currentHedgedDelta) < HedgerParams.deltaThreshold
        ) {
            revert InteractionDelayNotExpired(
                // lastInteraction, HedgerParams.interactionDelay, block.timestamp
            );
        }
        _hedgeDelta(expectedHedge, asset);
        // return any excess eth
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @notice adjust collateral in GMX to match target leverage
     * @dev   if we have excess collateral: create pending order to remove collateral
     * @dev   if we need more collateral: transfer from liquidity pool
     */
    function updateCollateral(address asset) external payable nonReentrant {
        CurrentPositions memory positions = _getPositions(asset);
        emit HedgerPosition(address(this), positions);

        if (positions.amountOpen > 1) {
            int256 expectedHedge = _getCappedExpectedHedge(asset);
            _closeSecondPosition(asset, positions, expectedHedge);
            return;
        }

        (, bool needUpdate, int256 collateralDelta) = _getCurrentLeverage(positions, asset);
        if (!needUpdate) {
            return;
        }

        if (collateralDelta > 0) {
            _increasePosition(
                asset,
                positions.isLong ? positions.longPosition : positions.shortPosition,
                positions.isLong,
                0,
                collateralDelta.toUint256()
            );
        } else {
            // decrease position size (withdraw collateral to liquidity pool directly)
            _decreasePosition(
                asset,
                positions.isLong ? positions.longPosition : positions.shortPosition,
                positions.isLong,
                0,
                (-collateralDelta).toUint256(),
                false // is not close
            );
        }

        emit CollateralOrderPosted(address(this), pendingOrderKey[asset], positions.isLong, collateralDelta);
        // return any excess eth
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @dev gets the current size of the hedged position.
     */
    function getCurrentHedgedNetDelta(address asset) external view returns (int256) {
        // the first index is the size of the position
        CurrentPositions memory positions = _getPositions(asset);
        return _getCurrentHedgedNetDelta(positions, asset);
    }

    /**
     * @dev gets the current size of the hedged position. Use spot price from adaptor.
     */
    function _getCurrentHedgedNetDelta(CurrentPositions memory positions, address asset)
        internal
        view
        returns (int256)
    {
        if (positions.amountOpen == 0) {
            return 0;
        }
        uint256 spot = oracle.getSpotPrice(asset);
        return _getCurrentHedgedNetDeltaWithSpot(positions, spot);
    }

    function _getCurrentHedgedNetDelta(CurrentPositions memory positions, uint256 spot)
        internal
        pure
        returns (int256)
    {
        if (positions.amountOpen == 0) {
            return 0;
        }
        return _getCurrentHedgedNetDeltaWithSpot(positions, spot);
    }

    /**
     * @dev gets the current size of the hedged position. Use spot price from input
     */
    function _getCurrentHedgedNetDeltaWithSpot(CurrentPositions memory positions, uint256 spot)
        internal
        pure
        returns (int256)
    {
        if (positions.amountOpen == 0) {
            return 0;
        }

        // we shouldn't have both long and short positions open at the same time.
        // get the larger of long or short.
        int256 largestPosition = 0;

        if (positions.longPosition.size > 0) {
            largestPosition = positions.longPosition.size.toInt256();
        }
        if (positions.shortPosition.size > positions.longPosition.size) {
            largestPosition = -positions.shortPosition.size.toInt256();
        }

        return largestPosition.divideDecimal(spot.toInt256());
    }

    //////////////
    // Internal //
    /////////////

    /**
     * @dev Updates the hedge position.
     *
     * @param expectedHedge The expected final hedge value.
     */
    function _hedgeDelta(int256 expectedHedge, address asset) internal {
        // Check pending orders first
        if (_hasPendingPositionRequest(asset)) {
            revert PositionRequestPending(address(this), pendingOrderKey[asset]);
        }
        pendingOrderKey[asset] = bytes32(0);

        CurrentPositions memory positions = _getPositions(asset);
        emit HedgerPosition(address(this), positions);

        uint256 spot = oracle.getSpotPrice(asset);

        if (positions.amountOpen > 1) {
            _closeSecondPosition(asset, positions, expectedHedge);
            return;
        }

        // From here onwards, there can only be one position open for the hedger
        int256 currHedgedNetDelta = _getCurrentHedgedNetDelta(positions, spot);

        if (expectedHedge == currHedgedNetDelta) {
            return;
        }

        // Note: position could be empty, which means this will be filled with 0s, which works fine further below.
        PositionDetails memory currentPos = positions.isLong ? positions.longPosition : positions.shortPosition;

        // Need to know if we need to flip from a long to a short (or visa versa)
        if ((expectedHedge <= 0 && currHedgedNetDelta > 0) || (expectedHedge >= 0 && currHedgedNetDelta < 0)) {
            // as we check the current is explicitly > 0, we know a position is currently open.
            // Must flip the hedge, so we will close the position and not reset the interaction delay.
            _decreasePosition(
                asset,
                currentPos,
                positions.isLong,
                currentPos.size,
                // Withdraw excess collateral to make sure we aren't under leveraged and blocked
                currentPos.collateral,
                true
            );

            emit PositionUpdated(
                address(this),
                currHedgedNetDelta,
                expectedHedge,
                currentPos.size,
                Math.abs(expectedHedge) > Math.abs(currHedgedNetDelta)
            );
            return;
        }

        // To get to this point, there is either no position open, or a position on the same side as we want.
        bool isLong = expectedHedge < 0;

        uint256 sizeDelta = Math.abs(expectedHedge - currHedgedNetDelta).multiplyDecimal(spot); // delta is in USD

        // calculate the expected collateral given the new expected hedge
        uint256 expectedCollateral = _getTargetCollateral(Math.abs(expectedHedge).multiplyDecimal(spot));

        uint256 collatAmount = currentPos.collateral;
        bool condition = Math.abs(expectedHedge) > Math.abs(currHedgedNetDelta);
        if (condition) {
            uint256 collatDelta = expectedCollateral > collatAmount ? expectedCollateral - collatAmount : 0;
            _increasePosition(asset, currentPos, isLong, sizeDelta, collatDelta);
        } else {
            uint256 collatDelta = collatAmount > expectedCollateral ? collatAmount - expectedCollateral : 0;

            // The case of being under collateralised here can be fixed after the fact by calling updateCollateral.
            // We are de-risking here (reducing position) so we dont have to do it first.
            _decreasePosition(
                asset,
                currentPos,
                isLong,
                sizeDelta,
                // Withdraw excess collateral to make sure we aren't under-leveraged and blocked
                collatDelta,
                false
            );
        }

        emit PositionUpdated(address(this), currHedgedNetDelta, expectedHedge, sizeDelta, condition);

        lastInteraction = block.timestamp;
        return;
    }

    function _hasPendingPositionRequest(address asset) internal view returns (bool) {
        if (pendingOrderKey[asset] == bytes32(0)) {
            return false;
        }
        if (_hasPendingIncrease(asset)) {
            return true;
        }
        if (_hasPendingDecrease(asset)) {
            return true;
        }
        return false;
    }

    /**
     * @dev returns true if there is pending increase position order on GMX
     */
    function _hasPendingIncrease(address asset) public view returns (bool hasPending) {
        bytes memory data =
            abi.encodeWithSelector(positionRouter.increasePositionRequests.selector, pendingOrderKey[asset]);

        (bool success, bytes memory returndata) = address(positionRouter).staticcall(data);
        if (!success) {
            revert GetGMXVaultError(address(this));
        }

        // parse account from the first 32 bytes of returned data
        // same as: (address account,,,,,,,,,,,,) = positionRouter.increasePositionRequests(pendingOrderKey);
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
    function _hasPendingDecrease(address asset) internal view returns (bool) {
        bytes memory data =
            abi.encodeWithSelector(positionRouter.decreasePositionRequests.selector, pendingOrderKey[asset]);

        (bool success, bytes memory returndata) = address(positionRouter).staticcall(data);
        if (!success) {
            revert GetGMXVaultError(address(this));
        }

        // parse account from the first 32 bytes of returned data
        // same as: (address account,,,,,,,,,,,,,) = positionRouter.decreasePositionRequests(pendingOrderKey);
        address account;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            account := mload(add(returndata, 32))
        }
        return account != address(0);
    }

    function _convertFromGMXPrecision(uint256 amt) internal pure returns (uint256) {
        return ConvertDecimals.normaliseTo18(amt, GMX_PRICE_PRECISION);
    }

    /**
     * @dev Gets the current open positions. Will return an empty object where a position is not open. First will be long
     * Second will be short.
     */
    function _getPositions(address asset) public view returns (CurrentPositions memory positions) {
        PositionDetails memory longResult = _getPosition(true, asset);
        PositionDetails memory shortResult = _getPosition(false, asset);

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

    /**
     * @dev get position detail that includes unrealised PNL
     */
    function _getPosition(bool isLong, address asset) internal view returns (PositionDetails memory) {
        (
            uint256 size,
            uint256 collateral,
            uint256 averagePrice,
            uint256 entryFundingRate, // uint reserveAmount: GMX internal variable to keep track of collateral reserved for position // uint realised profit: historical pnl // bool hasProfit: if the vault had previously realised profit or loss
            ,
            ,
            ,
            uint256 lastIncreasedTime
        ) = vault.getPosition(address(this), address(liquidityPool.collateral()), asset, isLong);

        int256 unrealisedPnl = 0;
        if (averagePrice > 0) {
            // getDelta will revert if average price == 0;
            (bool hasUnrealisedProfit, uint256 absUnrealisedPnl) =
                vault.getDelta(asset, size, averagePrice, isLong, lastIncreasedTime);

            if (hasUnrealisedProfit) {
                unrealisedPnl = _convertFromGMXPrecision(absUnrealisedPnl).toInt256();
            } else {
                unrealisedPnl = -_convertFromGMXPrecision(absUnrealisedPnl).toInt256();
            }
        }

        return PositionDetails({
            size: _convertFromGMXPrecision(size),
            collateral: _convertFromGMXPrecision(collateral),
            averagePrice: _convertFromGMXPrecision(averagePrice),
            entryFundingRate: entryFundingRate, // store in initial percision, will be used in vault.getFundingFee
            unrealisedPnl: unrealisedPnl,
            lastIncreasedTime: lastIncreasedTime,
            isLong: isLong
        });
    }

    /**
     * @dev get the expected delta hedge that the hedger must perfom.
     * @return cappedExpectedHedge amount of delta to be hedged, with 18 decimals
     */
    function _getCappedExpectedHedge(address asset) internal view returns (int256 cappedExpectedHedge) {
        // the cache returns positive value if users are net long delta (AMM is net short)
        // so AMM will need to go long to off set the negative delta.
        // -> AMM always hedge the exact amount reported by getGlobalNetDelta
        int256 expectedHedge = liquidityPool.deltaExposure(asset);

        bool exceedsCap = Math.abs(expectedHedge) > HedgerParams.hedgeCap;

        if (!exceedsCap) {
            cappedExpectedHedge = expectedHedge;
        } else if (expectedHedge < 0) {
            cappedExpectedHedge = -HedgerParams.hedgeCap.toInt256();
        } else {
            // expectedHedge >= 0
            cappedExpectedHedge = HedgerParams.hedgeCap.toInt256();
        }
        return cappedExpectedHedge;
    }

    function _closeSecondPosition(address asset, CurrentPositions memory positions, int256 expectedHedge) internal {
        // we have two positions open (one long and short); so lets close the one we dont want
        if (expectedHedge > 0) {
            _decreasePosition(
                asset,
                positions.shortPosition,
                false,
                positions.shortPosition.size,
                positions.shortPosition.collateral,
                true
            );
        } else {
            _decreasePosition(
                asset,
                positions.longPosition,
                true,
                positions.longPosition.size,
                positions.longPosition.collateral,
                true
            );
        }
    }

    /**
     * @dev return 0 if no position is opened
     * @return leverage in 18 decimals
     * @return needUpdate
     * @return collateralDelta how much collateral needed to bring leverage back to targetLeverage
     */
    function _getCurrentLeverage(CurrentPositions memory positions, address asset)
        internal
        view
        returns (uint256 leverage, bool needUpdate, int256 collateralDelta)
    {
        if (positions.amountOpen == 0) {
            return (0, false, 0);
        }

        PositionDetails memory position = positions.isLong ? positions.longPosition : positions.shortPosition;

        int256 effectiveCollateral = _getEffectiveCollateral(position);

        // re-calculate target collateral instead of using "position.collateral"
        // just in case our collateral is off.
        int256 targetCollateral = _getTargetCollateral(position.size).toInt256();

        collateralDelta = targetCollateral - effectiveCollateral;

        leverage = position.size.divideDecimal(effectiveCollateral.toUint256());

        needUpdate = true;

        if (position.size == position.collateral && collateralDelta > 0) {
            // don't need to update if collateral is same as size already, and delta is positive
            needUpdate = false;
        } else if (_hasPendingPositionRequest(asset)) {
            // set needUpdate to false if there's a pending order (either to hedge or to updateCollateral)
            needUpdate = false;
        } else if (collateralDelta == 0) {
            needUpdate = false;
        }
    }

    /**
     * @dev get what is the collateral for the position, considering losses
     */
    function _getEffectiveCollateral(PositionDetails memory position)
        internal
        pure
        returns (int256 effectiveCollateral)
    {
        effectiveCollateral = int256(position.collateral);
        if (position.unrealisedPnl < 0) {
            effectiveCollateral += position.unrealisedPnl;
        }
    }

    function _getTargetCollateral(uint256 size) internal view returns (uint256) {
        return size.divideDecimal(HedgerParams.targetLeverage);
    }

    ///////////////////
    /// GMX Adapters //
    ///////////////////

    /**
     * @dev create increase position order on GMX router
     * @dev trading fee is taken care of
     */
    function _increasePosition(
        address asset,
        PositionDetails memory currentPos,
        bool isLong,
        uint256 sizeDelta,
        uint256 collateralDelta
    ) internal {
        // console.log("INCREASE POSITION");
        // console.log("currentPos.entryFundingRate: %s", currentPos.entryFundingRate);
        // console.log("currentPos.size: %s", currentPos.size);
        // console.log("sizeDelta: %s", sizeDelta);
        // console.log("collateralDelta: %s", collateralDelta);
        // console.log("currentPos.collateral: %s", currentPos.collateral);
        if (isLong) {
            uint256 swapFeeBP = getSwapFeeBP(isLong, true, collateralDelta, asset);
            collateralDelta = (collateralDelta * (BASIS_POINTS_DIVISOR + swapFeeBP)) / BASIS_POINTS_DIVISOR;
        }

        // add margin fee
        // when we increase position, fee always got deducted from collateral
        collateralDelta += _getPositionFee(currentPos.size, sizeDelta, currentPos.entryFundingRate, asset);

        address[] memory path;
        uint256 acceptableSpot;
        IERC20 collateralToken = IERC20(address(liquidityPool.collateral()));

        if (isLong) {
            uint256 spot = oracle.getSpotPrice(asset);
            path = new address[](2);
            path[0] = address(collateralToken);
            path[1] = asset;
            acceptableSpot = _convertToGMXPrecision(spot.multiplyDecimal(HedgerParams.acceptableSpotSlippage));
        } else {
            uint256 spot = oracle.getSpotPrice(asset);
            path = new address[](1);
            path[0] = address(collateralToken);
            acceptableSpot = _convertToGMXPrecision(spot.divideDecimalRound(HedgerParams.acceptableSpotSlippage));
        }

        // if the trade ends up with collateral > size, adjust collateral.
        // gmx restrict position to have size >= collateral, so we cap the collateral to be same as size.
        if (currentPos.collateral + collateralDelta > currentPos.size + sizeDelta) {
            collateralDelta = (currentPos.size + sizeDelta) - currentPos.collateral;
        }

        // if we get less than we want, we will just continue with the same position, but take on more leverage
        collateralDelta = liquidityPool.transferQuoteToHedge(collateralDelta);

        if (collateralDelta == 0) {
            revert NoQuoteReceivedFromLP(address(this));
        }

        if (!collateralToken.approve(address(router), collateralDelta)) {
            revert QuoteApprovalFailure(address(this), address(router), collateralDelta);
        }

        uint256 executionFee = _getExecutionFee();
        // console.log("sizeDelta: %s", _convertToGMXPrecision(sizeDelta));
        // console.log("collateralDelta: %s", collateralDelta);
        bytes32 key = positionRouter.createIncreasePosition{value: executionFee}(
            path,
            asset, // index token
            collateralDelta, // amount in via router is in the native currency decimals
            0, // min out
            _convertToGMXPrecision(sizeDelta),
            isLong,
            acceptableSpot,
            executionFee,
            referralCode,
            address(this)
        );

        pendingOrderKey[asset] = key;
        lastOrderTimestamp[asset] = block.timestamp;

        emit OrderPosted(address(this), pendingOrderKey[asset], collateralDelta, sizeDelta, isLong, true);
    }

    /**
     * @dev create increase position order on GMX router
     * @param sizeDelta is the change in current delta required to get to the desired hedge. in USD term
     */
    function _decreasePosition(
        address asset,
        PositionDetails memory currentPos,
        bool isLong,
        uint256 sizeDelta,
        uint256 collateralDelta,
        bool isClose
    ) internal {
        // if realised pnl is negative, fee will be paid in collateral
        // so we can reduce less
        if (currentPos.unrealisedPnl < 0) {
            uint256 adjustedDelta =
                Math.abs(currentPos.unrealisedPnl).multiplyDecimal(sizeDelta).divideDecimal(currentPos.size);
            if (adjustedDelta > collateralDelta) {
                collateralDelta = 0;
            } else {
                collateralDelta -= adjustedDelta;
            }
        }

        address[] memory path;
        uint256 acceptableSpot;

        if (isLong) {
            uint256 spot = oracle.getSpotPrice(asset);
            path = new address[](2);
            path[0] = address(asset);
            path[1] = address(liquidityPool.collateral());
            acceptableSpot = _convertToGMXPrecision(spot.divideDecimalRound(HedgerParams.acceptableSpotSlippage));
        } else {
            uint256 spot = oracle.getSpotPrice(asset);
            path = new address[](1);
            path[0] = address(liquidityPool.collateral());
            acceptableSpot = _convertToGMXPrecision(spot.multiplyDecimal(HedgerParams.acceptableSpotSlippage));
        }

        if (collateralDelta > currentPos.collateral) {
            collateralDelta = currentPos.collateral;
        }

        uint256 executionFee = _getExecutionFee();
        bytes32 key = positionRouter.createDecreasePosition{value: executionFee}(
            path,
            asset,
            // CollateralDelta for decreases is in PRICE_PRECISION rather than asset decimals like for opens...
            // In the case of closes, 0 must be passed in
            isClose ? 0 : _convertToGMXPrecision(collateralDelta),
            _convertToGMXPrecision(sizeDelta),
            isLong,
            address(liquidityPool),
            acceptableSpot,
            0,
            executionFee,
            false,
            address(this)
        );

        pendingOrderKey[asset] = key;
        lastOrderTimestamp[asset] = block.timestamp;

        emit OrderPosted(address(this), pendingOrderKey[asset], collateralDelta, sizeDelta, isLong, false);
    }
    /**
     * @dev returns the execution fee plus the cost of the gas callback
     */

    function _getExecutionFee() internal view returns (uint256) {
        return positionRouter.minExecutionFee();
    }

    function _convertToGMXPrecision(uint256 amt) internal pure returns (uint256) {
        return ConvertDecimals.normaliseFrom18(amt, GMX_PRICE_PRECISION);
    }

    function getTotalHedgingLiquidity(address asset) external view returns (uint256) {
        uint256 spot = oracle.getSpotPrice(asset);
        (uint256 pendingDeltaLiquidity, uint256 usedDeltaLiquidity) = getHedgingLiquidity(spot, asset);
        return pendingDeltaLiquidity + usedDeltaLiquidity;
    }

    /**
     * @notice Returns pending delta hedge liquidity and used delta hedge liquidity
     * @dev include funds potentially transferred to the contract
     * @return pendingDeltaLiquidity amount USD needed to hedge. outstanding order is NOT included
     * @return usedDeltaLiquidity amount USD already used to hedge. outstanding order is NOT included
     *
     */
    function getHedgingLiquidity(uint256 spotPrice, address asset)
        public
        view
        returns (uint256 pendingDeltaLiquidity, uint256 usedDeltaLiquidity)
    {
        CurrentPositions memory currentPositions = _getPositions(asset);

        usedDeltaLiquidity = _getAllPositionsValue(currentPositions);
        // pass in estimate spot price
        uint256 absCurrentHedgedDelta = Math.abs(_getCurrentHedgedNetDeltaWithSpot(currentPositions, spotPrice));
        uint256 absExpectedHedge = Math.abs(_getCappedExpectedHedge(asset));

        if (absCurrentHedgedDelta > absExpectedHedge) {
            return (0, usedDeltaLiquidity);
        }

        pendingDeltaLiquidity = (absExpectedHedge - absCurrentHedgedDelta).multiplyDecimal(spotPrice).divideDecimal(
            HedgerParams.targetLeverage
        );

        return (pendingDeltaLiquidity, usedDeltaLiquidity);
    }

    /**
     * @dev get total value from long and short GMX positions.
     * @return total value in USD term.
     */
    function getAllPositionsValue(address asset) external view returns (uint256) {
        CurrentPositions memory positions = _getPositions(asset);
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

    function getSwapFeeBP(bool isLong, bool isIncrease, uint256 amountIn, address asset)
        public
        view
        returns (uint256 feeBP)
    {
        if (!isLong) {
            // only relevant for longs as shorts use the stable asset as collateral
            return 0;
        }
        address collateral = address(liquidityPool.collateral());
        address inToken = isIncrease ? collateral : asset;
        address outToken = isIncrease ? asset : collateral;
        uint256 priceIn = vault.getMinPrice(inToken);

        // adjust usdgAmounts by the same usdgAmount as debt is shifted between the assets
        uint256 usdgAmount = _convertFromGMXPrecision(
            ConvertDecimals.convertTo18(amountIn, IERC20(collateral).decimals()).multiplyDecimal(priceIn)
        );

        uint256 baseBps = vault.swapFeeBasisPoints();
        uint256 taxBps = vault.taxBasisPoints();
        uint256 feesBasisPoints0 = vault.getFeeBasisPoints(inToken, usdgAmount, baseBps, taxBps, true);
        uint256 feesBasisPoints1 = vault.getFeeBasisPoints(outToken, usdgAmount, baseBps, taxBps, false);
        // use the higher of the two fee basis points
        return feesBasisPoints0 > feesBasisPoints1 ? feesBasisPoints0 : feesBasisPoints1;
    }

    /**
     * @dev returns the additional collat required for fee
     * @dev fee is charged on the notional value of the position.
     *      notional value = position size * leverage
     * @param size size with 18 decimals. used to calculate funding fee
     * @param sizeDelta size delta with 18 decimals. used to calculate position fee
     * @param entryFundingRate original funding rate, with GMX's original precision
     * @return fee in usd term, 18 decimals
     */
    function _getPositionFee(uint256 size, uint256 sizeDelta, uint256 entryFundingRate, address asset)
        internal
        view
        returns (uint256)
    {
        // pass in sizes in 18 decimals, will return funding fee and position fee in 18 decimals
        uint256 fundingFee = vault.getFundingFee(asset, size, entryFundingRate);
        return fundingFee + vault.getPositionFee(sizeDelta);
    }

    function gmxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external onlyGMXKeeper {
        // emit GMXPositionCallback(address(this), positionKey, isExecuted, isIncrease, _getPositions(asset));
    }

    ///////////
    // Admin //
    ///////////

    /**
     * @dev updates the futures hedger parameters
     */
    function setHedgerParams(HedgerParameters memory _HedgerParams) external onlyOwner {
        HedgerParams = _HedgerParams;
    }

    function setPositionRouter(IPositionRouter _positionRouter) external onlyOwner {
        positionRouter = _positionRouter;
    }

    function setReferralCode(bytes32 _referralCode) external onlyOwner {
        referralCode = _referralCode;
    }

    /**
     * @dev Sends all quote and base asset in this contract to the `LiquidityPool`. Helps in case of trapped funds.
     */
    function sendAllFundsToLP() external onlyOwner {
        IERC20 collateral = IERC20(address(liquidityPool.collateral()));
        uint256 balance = liquidityPool.collateral().balanceOf(address(this));
        if (balance > 0) {
            if (!collateral.transfer(address(liquidityPool), balance)) {
                revert CollateralTransferFailed(address(this), balance, address(liquidityPool));
            }
            emit CollateralTransferFailedEvent(address(this), balance);
        }
    }

    function resetInteractionDelay() external onlyOwner {
        lastInteraction = 0;
    }
}
