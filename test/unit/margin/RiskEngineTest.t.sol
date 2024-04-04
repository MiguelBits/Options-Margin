pragma solidity ^0.8.18;

//HELPERS
import "forge-std/Test.sol";
import "../../helpers/Helper.sol";

//INTERFACES
import {IIVXPortfolio} from "../../../src/interface/margin/IIVXPortfolio.sol";
import {IIVXLP} from "../../../src/interface/liquidity/IIVXLP.sol";
import {IIVXOracle} from "../../../src/interface/periphery/IIVXOracle.sol";
import {IWETH} from "../../interface/IWETH.sol";
import {IIVXRiskEngine} from "../../../src/interface/margin/IIVXRiskEngine.sol";
import {IERC20} from "../../../src/interface/IERC20.sol";
//PROTOCOL CONTRACTS
import {IVXRiskEngine} from "../../../src/margin/IVXRiskEngine.sol";

contract RiskEngineTest is Helper {
    address ethereum;
    address stable;

    function setUp() public {
        deployTestDiem();
    }

    function test_AddAsset() public {
        // address priceFeed = address(oracle.assetPriceFeed(ethereum));
        // console.log("priceFeed: ", address(oracle));
        MockupERC20 erc20 = new MockupERC20("IVX",18);
        MockupAggregatorV3 erc20MockupAggregatorV3 = new MockupAggregatorV3(
            18,
            "sss", //description
            1, //version
            0, //roundId
            1 ether, //answer
            0, //startedAt
            0, //updatedAt
            0 //answeredInRound
        );
        oracle.addAssetPriceFeed(address(erc20), address(erc20MockupAggregatorV3));
        IIVXRiskEngine.AssetAttributes memory attributes = IIVXRiskEngine.AssetAttributes({
            collateralFactor: 1000,
            marginFactors: IIVXRiskEngine.MarginFactors({
                marginFactorA: 0.3 ether,
                marginFactorB: 0.032 ether,
                marginFactorC: 1.03 ether,
                marginFactorD: 0.002 ether,
                marginFactorE: 1.03 ether
            }),
            shockLossFactors: IIVXRiskEngine.ShockLossFactors(0.3 ether, 0.2 ether)
        });
        RiskEngine.addAsset(address(erc20), attributes, true);
    }

    function test_CantAddAsset() public {
        MockupERC20 erc20 = new MockupERC20("IVX",18);
        IIVXRiskEngine.AssetAttributes memory attributes = IIVXRiskEngine.AssetAttributes({
            collateralFactor: 1000,
            marginFactors: IIVXRiskEngine.MarginFactors({
                marginFactorA: 0.3 ether,
                marginFactorB: 0.032 ether,
                marginFactorC: 1.03 ether,
                marginFactorD: 0.002 ether,
                marginFactorE: 1.03 ether
            }),
            shockLossFactors: IIVXRiskEngine.ShockLossFactors(0.3 ether, 0.2 ether)
        });
        vm.expectRevert(abi.encodeWithSelector(IIVXOracle.UnsupportedOracleAsset.selector, address(erc20)));
        RiskEngine.addAsset(address(erc20), attributes, true);
    }

    function test_RemoveAsset() public {
        test_AddAsset();
        RiskEngine.removeAsset(address(mockupWETH));
        address[] memory assets = RiskEngine.getSupportedAssets();
        bool found = false;
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == address(mockupWETH)) {
                found = true;
                break;
            }
        }

        assertTrue(!found, "Asset not removed");
    }

    function test_AddAssetNotToSupportedAssets() public {
        MockupERC20 erc20 = new MockupERC20("IVX",18);
        IIVXRiskEngine.AssetAttributes memory attributes = IIVXRiskEngine.AssetAttributes({
            collateralFactor: 1000,
            marginFactors: IIVXRiskEngine.MarginFactors({
                marginFactorA: 0.3 ether,
                marginFactorB: 0.032 ether,
                marginFactorC: 1.03 ether,
                marginFactorD: 0.002 ether,
                marginFactorE: 1.03 ether
            }),
            shockLossFactors: IIVXRiskEngine.ShockLossFactors(0.3 ether, 0.2 ether)
        });
        RiskEngine.addAsset(address(erc20), attributes, false);

        address[] memory assets = RiskEngine.getSupportedAssets();
        bool found = false;
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == address(erc20)) {
                found = true;
                break;
            }
        }

        assertTrue(!found, "Asset inserted, not expected");
    }

    function test_positionMaintenanceMargin() public view {
        RiskEngine.positionMaintenanceMargin(1500 ether, 2 ether, address(mockupERC20));
    }

    function test_calculateBorrowFee() public view {
        RiskEngine.calculateBorrowFee(15 ether, 0.04 ether, 4);
    }

    function test_maintenanceMarginRate() public view {
        uint256 main = RiskEngine.positionMaintenanceMargin(1500 ether, 2 ether, address(mockupERC20));
        uint256 borrow = RiskEngine.calculateBorrowFee(15 ether, 0.04 ether, 4);
        uint256 _maintenanceMarginRate = RiskEngine.maintenanceMarginRate(main + borrow, 2000 ether, 100 ether, 0);
        console.log("maintenanceMarginRate: ", _maintenanceMarginRate);
    }

    function test_isEligibleForLiquidation_2Positions() public {
        address user = ALICE;
        vm.prank(ALICE);
        IIVXPortfolio portfolio = RiskEngine.createMarginAccount();
        uint256 _amount = 1000 ether;
        vm.startPrank(user);
        mockupERC20.mint(user, _amount);

        IERC20(address(mockupERC20)).approve(address(portfolio), _amount);
        portfolio.increaseMargin(address(mockupERC20), _amount);
        // uint256 weth_marginBalance = portfolio.userMarginBalance(address(mockupERC20));
        // console.log("weth_marginBalance", weth_marginBalance);
        vm.stopPrank();

        oracle.setStrikeVolatility(address(mockupERC20), 1500 ether, 0.6 ether);
        oracle.setStrikeVolatility(address(mockupERC20), 2000 ether, 0.6 ether);
        oracle.setValues(address(mockupERC20), IIVXOracle.EncodedData({beta: 300, alpha: 400}));
        oracle.setRiskFreeRate(address(mockupERC20), 500000000000000000);

        uint256[] memory unitsTraded = new uint256[](2);
        unitsTraded[0] = 5 ether;
        unitsTraded[1] = 5 ether;
        uint256[] memory xParams = new uint256[](2);
        xParams[0] = 1500 ether;
        xParams[1] = 2000 ether;
        uint256[] memory yParams = new uint256[](2);
        yParams[0] = 2 ether;
        yParams[1] = 3 ether;
        address[] memory assets = new address[](2);
        assets[0] = address(mockupERC20);
        assets[1] = address(mockupERC20);
        uint256[] memory strikes = new uint256[](2);
        strikes[0] = 1500 ether;
        strikes[1] = 2000 ether;
        uint256[] memory borrowAmounts = new uint[](2);
        borrowAmounts[0] = 100 ether;
        borrowAmounts[1] = 100 ether;
        uint256[] memory timeOpen = new uint256[](2);
        timeOpen[0] = 5 hours;
        timeOpen[1] = 5 hours;
        int256[] memory _deltas = new int256[](2);
        _deltas[0] = 0.1 ether;
        _deltas[1] = 0.1 ether;
        int256[] memory _vegas = new int256[](2);
        _vegas[0] = 0.5 ether;
        _vegas[1] = 0.5 ether;

        IIVXRiskEngine.MarginParams memory params = IIVXRiskEngine.MarginParams({
            contractsTraded: unitsTraded,
            X: xParams,
            Y: yParams,
            asset: assets,
            strikes: strikes,
            borrowAmount: borrowAmounts,
            interestRate: 0.04 ether,
            timeOpen: timeOpen,
            orderLoss: 1000 ether,
            deltas: _deltas,
            vegas: _vegas
        });
        bool _isEligibleForLiquidation = RiskEngine.isEligibleForLiquidation(portfolio, params);
        console.log("isEligibleForLiquidation: ", _isEligibleForLiquidation);
    }

    function test_isEligibleForLiquidation_1Position() public {
        address user = ALICE;
        vm.prank(ALICE);
        IIVXPortfolio portfolio = RiskEngine.createMarginAccount();
        uint256 _amount = oracle.getAmountPriced(1 ether, address(mockupERC20)); //100$
        vm.startPrank(user);
        mockupERC20.mint(user, _amount);

        IERC20(address(mockupERC20)).approve(address(portfolio), _amount);
        portfolio.increaseMargin(address(mockupERC20), _amount);
        // uint256 weth_marginBalance = portfolio.userMarginBalance(address(mockupERC20));
        // console.log("weth_marginBalance", weth_marginBalance);
        vm.stopPrank();

        oracle.setStrikeVolatility(address(mockupERC20), 1500 ether, 0.6 ether);
        oracle.setValues(address(mockupERC20), IIVXOracle.EncodedData({beta: 300, alpha: 400}));
        oracle.setRiskFreeRate(address(mockupERC20), 500000000000000000);

        uint256[] memory unitsTraded = new uint256[](2);
        unitsTraded[0] = 5 ether;
        uint256[] memory xParams = new uint256[](1);
        xParams[0] = 1885220000000000000000;
        uint256[] memory yParams = new uint256[](1);
        yParams[0] = 2532036004766855961;
        address[] memory assets = new address[](1);
        assets[0] = address(mockupERC20);
        uint256[] memory strikes = new uint256[](1);
        strikes[0] = 1500 ether;
        uint256[] memory borrowAmounts = new uint[](1);
        borrowAmounts[0] = 2532036004766855961;
        uint256[] memory timeOpen = new uint256[](1);
        timeOpen[0] = 0;
        int256[] memory _deltas = new int256[](1);
        _deltas[0] = 0.1 ether;
        int256[] memory _vegas = new int256[](1);
        _vegas[0] = 0.5 ether;

        IIVXRiskEngine.MarginParams memory params = IIVXRiskEngine.MarginParams({
            contractsTraded: unitsTraded,
            X: xParams,
            Y: yParams,
            asset: assets,
            strikes: strikes,
            borrowAmount: borrowAmounts,
            interestRate: 0.04 ether,
            timeOpen: timeOpen,
            orderLoss: 1 ether,
            deltas: _deltas,
            vegas: _vegas
        });
        bool _isEligibleForLiquidation = RiskEngine.isEligibleForLiquidation(portfolio, params);

        console.log("isEligibleForLiquidation: ", _isEligibleForLiquidation);
    }
}
