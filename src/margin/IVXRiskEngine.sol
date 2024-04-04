// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

// Interfaces
import {IIVXDiem} from "../interface/options/IIVXDiem.sol";
import {IIVXLP} from "../interface/liquidity/IIVXLP.sol";
import {IIVXOracle} from "../interface/periphery/IIVXOracle.sol";
import {IIVXDiemToken} from "../interface/options/IIVXDiemToken.sol";
import {IIVXRiskEngine} from "../interface/margin/IIVXRiskEngine.sol";
import {IIVXPortfolio} from "../interface/margin/IIVXPortfolio.sol";
import {IERC20} from "../interface/IERC20.sol";

// Libraries
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";
import {MathLib} from "../libraries/math/MathLib.sol";
import {Math} from "../libraries/math/Math.sol";

// Protocol contracts
import {IVXPortfolio} from "./IVXPortfolio.sol";
import {IIVXExchange} from "../interface/exchange/IIVXExchange.sol";

/**
 * @title IVXMargin
 * @notice The margin contract for the IVX protocol, where users can deposit and withdraw margin assets used for option positions
 * @author gradient (@gradientIVX), MiguelBits (@MiguelBits)
 */
contract IVXRiskEngine is IIVXRiskEngine, Ownable, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 VARIABLES
    //////////////////////////////////////////////////////////////*/

    address[] private assetsArray;
    address public diem;
    address public lp;
    IIVXOracle public oracle;
    IIVXDiemToken public OptionToken;
    IIVXExchange public Exchange;

    /*//////////////////////////////////////////////////////////////
                                 MAPPINGS
    //////////////////////////////////////////////////////////////*/

    ///@dev Mapping of optionId to the portfolio contract
    mapping(address _user => IIVXPortfolio) public userIVXPortfolio;

    mapping(address asset => bool isAssetSupported) supportedAssets;
    mapping(address asset => AssetAttributes) assetAttributes;

    /*//////////////////////////////////////////////////////////////
                                 MANAGER
    //////////////////////////////////////////////////////////////*/

    function initialize(address _diem, address _lp, address _diemToken, address _exchange, address _oracle)
        external
        onlyOwner
    {
        diem = _diem;
        lp = _lp;
        OptionToken = IIVXDiemToken(_diemToken);
        Exchange = IIVXExchange(_exchange);
        oracle = IIVXOracle(_oracle);
    }

    /// @dev Adds collateral support for an asset
    /// @param _asset The address of the asset
    /// @param _factors Factors for margin; This is the percentage difference between our price and oracle price, and also the percent allowed to use as margin
    /// @notice _collateralFactor example: 20% => 20% of ETH is allowed to use as margin, and the actual effective price will be 80% less than the actual price
    function addAsset(address _asset, AssetAttributes memory _factors, bool _supported) external onlyOwner {
        require(_factors.collateralFactor > 0, "Collateral factor must be greater than 0");
        require(_factors.collateralFactor <= 1000, "Collateral factor must be less than or equal to 100");
        require(IERC20(_asset).decimals() <= uint8(18), "IVX does not support assets with more than 18 decimals");

        assetAttributes[_asset] = _factors;
        
        if(_supported){
            require(!supportedAssets[_asset], "Asset already supported");
            if(address(oracle.assetPriceFeed(_asset)) == address(0)) 
                revert IIVXOracle.UnsupportedOracleAsset(_asset);
            supportedAssets[_asset] = _supported;
            assetsArray.push(_asset);
        }

        emit CollateralAssetAdded(_asset, _factors);
    }

    function changeAssetMarginParams(address _asset, AssetAttributes memory _factors) external onlyOwner {
        require(_factors.collateralFactor > 0, "Collateral factor must be greater than 0");
        require(_factors.collateralFactor <= 1000, "Collateral factor must be less than or equal to 100");
        assetAttributes[_asset] = _factors;
    }

    /// @dev Removes collateral support for an asset
    /// @param _asset The address of the asset
    function removeAsset(address _asset) external onlyOwner {
        assetAttributes[_asset] = AssetAttributes({
            collateralFactor: 0,
            marginFactors: MarginFactors({
                marginFactorA: 0,
                marginFactorB: 0,
                marginFactorC: 0,
                marginFactorD: 0,
                marginFactorE: 0
            }),
            shockLossFactors: ShockLossFactors({
                ivFactor: 0,
                priceFactor: 0
            })
        });
        supportedAssets[_asset] = false;

        //for loop to remove _asset from assetAttributes
        uint256 length = assetsArray.length;
        for (uint256 i; i < length; ++i) {
            if (assetsArray[i] == _asset) {
                assetsArray[i] = assetsArray[length - 1];
                assetsArray.pop();
                break;
            }
        }

        emit CollateralAssetRemoved(_asset);
    }

    function isSupportedAsset(address _asset) external view returns (bool) {
        return supportedAssets[_asset];
    }

    function assetsLength() external view returns (uint256) {
        return assetsArray.length;
    }

    function assetsSupported(uint256 _index) external view returns (address) {
        return assetsArray[_index];
    }

    function assets() external view returns (address[] memory) {
        return assetsArray;
    }

    /*//////////////////////////////////////////////////////////////
                                 MARGIN
    //////////////////////////////////////////////////////////////*/

    function createMarginAccount() external nonReentrant returns (IIVXPortfolio) {
        if (address(userIVXPortfolio[msg.sender]) == address(0)) {
            IVXPortfolio newPortfolio = new IVXPortfolio();
            newPortfolio.initialize(
                diem, lp, this, Exchange, msg.sender
            );
            userIVXPortfolio[msg.sender] = IIVXPortfolio(address(newPortfolio));
        } else {
            revert IVXPortfolioAlreadyExists();
        }
        return userIVXPortfolio[msg.sender];
    }

    ///////////////////////
    /// MARGIN ///////////
    /////////////////////

    /// @notice Position Maintenance Margin = 0.3 × max {0.032 X + 1.00 Y, 0.002 X + 1.03 Y}
    /// @param X underlying price of the asset for which the option represents is given by X
    /// @param Y the current price of the option is given by Y
    /// @return margin required to keep a position open, in dollar value
    function positionMaintenanceMargin(uint256 X, uint256 Y, address _asset) public view returns (uint256 margin) {
        AssetAttributes memory asset = assetAttributes[_asset];
        margin = asset.marginFactors.marginFactorA.mulDivUp(
            Math.max(
                (asset.marginFactors.marginFactorB * X) + (asset.marginFactors.marginFactorC * Y),
                (asset.marginFactors.marginFactorD * X) + (asset.marginFactors.marginFactorE * Y)
            ),
            1e36
        );
    }

    /// @notice Borrowed Amount with Fees = Borrow Amount × e^{Interest Rate × Time Open} ≈ Borrow Amount × (1 + Annualised Interest Rate × Years Open + (Annualised Interest Rate × Years Open)^2 / 2)
    /// @notice Borrow Fees Accumulated = Borrowed Amount with Fees − Borrow Amount ≈ Borrow Amount × (Annualised Interest Rate × Years Open)
    /// @dev When opening a position with leverage, the borrower must pay a continuous interest rate on the borrowed amount. This needs to be accounted for in maintenance margin calculation.
    /// @param borrowAmount amount of money borrowed
    /// @param interestRate annualised interest rate for the borrowed amount
    function calculateBorrowFee(uint256 borrowAmount, uint256 interestRate, uint256 _secondsOpen)
        public
        pure
        returns (uint256 borrowFee)
    {
        borrowFee = borrowAmount.mulDivUp(interestRate.mulDivUp(_secondsOpen, 365 days), 1e18);
    }

    /// @notice Maintenance Margin for Open Positions = Sum of all open (Position Maintenance Margin [i] + Borrow Maintenance Margin [i] )
    function maintenanceMarginForPositions(
        uint256[] memory _positionMaintenanceMargin,
        uint256[] memory _accumulatedBorrowFees
    ) internal pure returns (uint256 sum) {
        uint256 arraylength = _positionMaintenanceMargin.length;

        for (uint256 i; i < arraylength; ++i) {
            sum += _positionMaintenanceMargin[i] + _accumulatedBorrowFees[i];
        }
    }

    /// @notice An account will become eligible for liquidation if its Maintenance Margin Rate crosses 100%.
    /// It will initially be below 100% but as positions become increasingly underwater, will move closer to 100%.
    /// @dev Maintenance Margin Rate = (100% × Maintenance Margin) / (Effective Margin − Order Loss − Shock Loss)
    /// @param _maintenanceMargin is defined above
    /// @param _effectiveMargin is a collateral factor-adjusted margin balance;
    /// @param _orderLoss is equal to the negative net profit and loss of the user’s positions. For example, if the user is in profit, the quantity (−Order Loss) is a positive quantity (+Order Loss));
    /// @param _shockLoss is a shock-scenario portfolio loss under some specific simulation conditions.
    function maintenanceMarginRate(
        uint256 _maintenanceMargin,
        uint256 _effectiveMargin,
        int256 _orderLoss,
        int256 _shockLoss
    ) public pure returns (uint256 _maintenanceMarginRate) {
        if (_orderLoss + _shockLoss < 0) {
            if (-(_orderLoss + _shockLoss) >= int256(_effectiveMargin)) {
                _maintenanceMarginRate = type(uint256).max;
            } //max uint
            else {
                _maintenanceMarginRate =
                    (_maintenanceMargin).mulDivUp(1 ether, (_effectiveMargin - uint256(-_orderLoss - _shockLoss)));
            }
        } else {
            _maintenanceMarginRate =
                (_maintenanceMargin).mulDivUp(1 ether, (_effectiveMargin + uint256(_orderLoss + _shockLoss)));
        }
    }

    //ShockLoss = max{
    // Net Vega * (+-30% * Implied Volatility),
    // Net Delta * (+- 20% * Spot Price)
    // }
    function _calculateShocks(address _asset, uint256 _strike, int256 _delta, int256 _vega)
        internal
        view
        returns (ShockLossVariables memory structured)
    {
        (uint256 ivFactor, uint256 priceFactor) = getShockLossFactors(_asset);
        int256 impliedVol = int256(oracle.getVolatility(_asset, _strike));
        int256 spot = int256(oracle.getSpotPrice(_asset));

        //netVega * ivFactor * iv
        structured.vegaShock_negative = _vega * (-int256(ivFactor) * impliedVol) / 1e36;
        structured.vegaShock_positive = _vega * (int256(ivFactor) * impliedVol) / 1e36;
        //netDelta * priceFactor * price
        structured.deltaShock_negative = _delta * (-int256(priceFactor) * spot) / 1e36;
        structured.deltaShock_positive = _delta * (int256(priceFactor) * spot) / 1e36;

        return structured;
    }

    function _calculateShockLoss(
        address[] memory _assets,
        uint256[] memory _strikes,
        int256[] memory _deltas,
        int256[] memory _vegas
    ) internal view returns (int256) {
        uint256 assetsLenght = _assets.length; //deltas and vegas have same length

        int256 SumDeltaShock_negative;
        int256 SumDeltaShock_positive;
        int256 SumVegaShock_negative;
        int256 SumVegaShock_positive;
        for (uint256 i; i < assetsLenght; ++i) {
            ShockLossVariables memory structured = _calculateShocks(_assets[i], _strikes[i], _deltas[i], _vegas[i]);
            SumDeltaShock_negative += structured.deltaShock_negative;
            SumDeltaShock_positive += structured.deltaShock_positive;
            SumVegaShock_negative += structured.vegaShock_negative;
            SumVegaShock_positive += structured.vegaShock_positive;
        }
    
        int256 Vega_shockLoss;
        int256 Delta_shockLoss;
        //take the minimum(most negative), this is the shock loss
        if (SumDeltaShock_negative < SumDeltaShock_positive) {
            Vega_shockLoss = SumDeltaShock_negative;
        } else {
            Vega_shockLoss = SumDeltaShock_positive;
        }

        if (SumVegaShock_negative < SumVegaShock_positive) {
            Delta_shockLoss = SumVegaShock_negative;
        } else {
            Delta_shockLoss = SumVegaShock_positive;
        }

        return Math.maxSigned(Vega_shockLoss, Delta_shockLoss);
    }

    function healthFactor(IIVXPortfolio portfolio, MarginParams calldata _params)
        public
        view
        returns (uint256 _healthFactor)
    {
        uint256 length = _params.X.length;
        if (length == 0) return 0;

        uint256[] memory _positionMaintenanceMargin = new uint256[](length);
        uint256[] memory _accumulatedBorrowFees = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            if (_params.timeOpen[i] != 0) {
                _accumulatedBorrowFees[i] =
                    calculateBorrowFee(_params.borrowAmount[i], _params.interestRate, _params.timeOpen[i]);
            }
            _positionMaintenanceMargin[i] = positionMaintenanceMargin(_params.X[i], _params.Y[i], _params.asset[i])
                .mulDivUp(_params.contractsTraded[i], 1e18);
        }

        int256 _shockLoss = _calculateShockLoss(_params.asset, _params.strikes, _params.deltas, _params.vegas);
        uint256 _maintenanceMarginForPositions =
            maintenanceMarginForPositions(_positionMaintenanceMargin, _accumulatedBorrowFees);
        uint256 _effectiveMargin = getEffectiveMargin(portfolio);
        _healthFactor =
            maintenanceMarginRate(_maintenanceMarginForPositions, _effectiveMargin, _params.orderLoss, _shockLoss);
    }

    function isEligibleForLiquidation(IIVXPortfolio portfolio, MarginParams calldata _params)
        external
        view
        returns (bool)
    {
        uint256 _hf = healthFactor(portfolio, _params);
        return _hf > 1 ether; //Eligible for liquidation if its Maintenance Margin Rate crosses 100%
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEW
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the total margin balance of a user in 1e18 decimals, including locked collateral
    /// @return The total margin of the user in dollars with 1e18 decimals, 1e18 = $1
    function portfolioDollarMargin(IIVXPortfolio portfolio) external view returns (uint256) {
        uint256 margin = 0;
        uint256 length = assetsArray.length;
        for (uint256 i; i < length; ++i) {
            address asset = assetsArray[i];
            if (supportedAssets[asset]) {
                uint256 userMarginBalance = portfolio.userMarginBalance(asset);
                if (userMarginBalance != 0) {
                    uint256 amountPriced = oracle.getAmountPriced(userMarginBalance, asset);
                    margin += amountPriced;
                }
                // uint gmxPositionValue = exchange.getAllPositionsValue(address(portfolio), usdc, asset); //TODO
                // margin += gmxPositionValue;
            }
        }
        return margin;
    }

    /// @notice Returns the total margin balance of a user in 1e18 decimals, including locked collateral
    /// @return The total margin of the user in dollars with 1e18 decimals, 1e18 = $1
    // function perpsDollarValue(address _user) external view returns (uint256) {
    //     uint256 margin = 0;
    //     IIVXPortfolio portfolio = userIVXPortfolio[_user];
    //     uint256 length = assetsArray.length;
    //     for (uint256 i; i < length; ++i) {
    //         address asset = assetsArray[i];
    //         if (supportedAssets[asset]) {
    //             // uint value =  exchange.getAllPositionsValue(portfolioSender, usdc, weth);
    //         }
    //     }

    //     return margin;
    // }

    /// @notice Calculate margin whilst accounting for collateral factors
    /// @return The effective margin of the user in dollars with 1e18 decimals
    function getEffectiveMargin(IIVXPortfolio portfolio) public view returns (uint256) {
        uint256 margin = 0;

        uint256 length = assetsArray.length;
        for (uint256 i; i < length; ++i) {
            address asset = assetsArray[i];
            if (supportedAssets[asset]) {
                margin += getEffectiveDollarMarginForAsset(portfolio, asset);
            }
        }
        return margin;
    }

    /// @notice Calculate margin in Dollar for a user's asset whilst accounting for collateral factors
    /// @param _asset The asset to calculate margin for
    /// @return The effective margin of the user in dollars with 1e18 decimals, 1e18 = $1
    function getEffectiveDollarMarginForAsset(IIVXPortfolio portfolio, address _asset) public view returns (uint256) {
        uint256 balance = portfolio.userMarginBalance(_asset);
        if (balance == 0) return 0;
        uint256 amountPriced = oracle.getAmountPriced(balance, _asset);
        return calculatePercentage(amountPriced, assetAttributes[_asset].collateralFactor);
    }

    function getEffectiveDollarMarginForAsset(address _asset, uint256 _amount) external view returns (uint256) {
        if (_amount == 0) return 0;
        uint256 amountPriced = oracle.getAmountPriced(_amount, _asset);
        return calculatePercentage(amountPriced, assetAttributes[_asset].collateralFactor);
    }

    /// @notice Calculate margin in Asset amount for a user's asset whilst accounting for collateral factors
    function getEffectiveMarginAmountOfAsset(address _asset, uint256 _amount) public view returns (uint256) {
        return calculatePercentage(_amount, assetAttributes[_asset].collateralFactor);
    }

    /// @notice Calculate the fractional percentage of an amount given a percentage
    /// @param amount The amount to calculate the percentage of
    /// @param percentage The percentage to calculate, must be between 0 and 1000 where 500 represents 50%
    function calculatePercentage(uint256 amount, uint16 percentage) internal pure returns (uint256) {
        require(percentage <= 1000, "Percentage value must be between 0 and 1000");
        return amount.mulDivDown(percentage, 1000);
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return assetsArray;
    }

    function getAssetAttributes(address _asset) public view returns (AssetAttributes memory) {
        return assetAttributes[_asset];
    }

    function getShockLossFactors(address _asset) public view returns (uint256 ivFactor, uint256 priceFactor) {
        AssetAttributes memory attr = getAssetAttributes(_asset);
        ivFactor = attr.shockLossFactors.ivFactor;
        priceFactor = attr.shockLossFactors.priceFactor;
    }
}
