pragma solidity ^0.8.18;

//HELPERS
import "forge-std/Test.sol";
import "../../helpers/Helper.sol";

//INTERFACES
import {IIVXDiem} from "../../../src/interface/options/IIVXDiem.sol";
import {IIVXRiskEngine} from "../../../src/interface/margin/IIVXRiskEngine.sol";
import {IIVXOracle} from "../../../src/interface/periphery/IIVXOracle.sol";
import {IIVXExchange} from "../../../src/interface/exchange/IIVXExchange.sol";
import {IIVXPortfolio} from "../../../src/interface/margin/IIVXPortfolio.sol";
import {IIVXLP} from "../../../src/interface/liquidity/IIVXLP.sol";
import {IWETH} from "../../interface/IWETH.sol";

//PROTOCOL CONTRACTS
import {IVXPortfolio} from "../../../src/margin/IVXPortfolio.sol";

contract PortfolioTest is Helper {
    IIVXPortfolio portfolio;
    address _diem = address(69);

    address eth_oracle;
    address ethereum;
    address btc_oracle;
    address bitcoin;
    address stable_oracle;
    address stable;
    uint256 satoshi = 1e8; // 1 bitcoin == 1e8 satoshi

    function setUpTest() public {
        deployTestDiem();

        //create new third asset
        (address _oracle, address _token) = deployMockTokenOracle("bitcoin", 8, int256(20000 * satoshi)); // 20000$ per bitcoin
        setMocksOracle(_oracle, _token);

        ethereum = address(mockupWETH);
        stable = address(mockupERC20);
        bitcoin = address(_token);

        vm.startPrank(ALICE);
        RiskEngine.createMarginAccount();
        portfolio = RiskEngine.userIVXPortfolio(ALICE);
        // console.log("portfolio: ", address(portfolio));
        vm.stopPrank();
    }

    function setUpReal() public {
        deployRealDiem();
        eth_oracle = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        ethereum = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        btc_oracle = 0x6ce185860a4963106506C203335A2910413708e9;
        bitcoin = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
        stable_oracle = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        stable = collateral;

        //create new third asset
        setMocksOracle(eth_oracle, ethereum);
        console.log("eth_oracle: ", eth_oracle);
        setMocksOracle(btc_oracle, bitcoin);
        console.log("btc_oracle: ", btc_oracle);
        setMocksOracle(stable_oracle, stable);
        console.log("stable_oracle: ", stable_oracle);

        vm.startPrank(ALICE);
        RiskEngine.createMarginAccount();
        portfolio = RiskEngine.userIVXPortfolio(ALICE);
        // console.log("portfolio: ", address(portfolio));
        vm.stopPrank();
    }

    function test_IncreaseMargin() public {
        setUpTest();
        IIVXRiskEngine.AssetAttributes memory attributes = IIVXRiskEngine.AssetAttributes({
            collateralFactor: 500,
            marginFactors: IIVXRiskEngine.MarginFactors({
                marginFactorA: 0.3 ether,
                marginFactorB: 0.032 ether,
                marginFactorC: 1.03 ether,
                marginFactorD: 0.002 ether,
                marginFactorE: 1.03 ether
            }),
            shockLossFactors: IIVXRiskEngine.ShockLossFactors(0.3 ether, 0.2 ether)
        });
        RiskEngine.addAsset(ethereum, attributes, true);

        //add 1 eth margin
        vm.startPrank(ALICE);
        ERC20(ethereum).approve(address(portfolio), 1 ether);
        portfolio.increaseMargin(ethereum, 1 ether);
        vm.stopPrank();

        assertTrue(portfolio.userMarginBalance(ethereum) == 1 ether);
        assertTrue(ERC20(ethereum).balanceOf(address(portfolio)) == 1 ether);
    }

    function test_decreaseMargin() public {
        test_IncreaseMargin();
        uint256 _amount = 1 ether;
        address weth = ethereum;

        address[] memory _assets = new address[](1);
        _assets[0] = weth;
        uint256[] memory _amounts = new uint[](1);
        _amounts[0] = _amount;
        vm.startPrank(ALICE);
        portfolio.decreaseMargin(_assets, _amounts);
        vm.stopPrank();

        uint256 _marginBalance2 = portfolio.userMarginBalance(weth);
        console.log("_marginBalance2: %s", _marginBalance2);
        assertTrue(_marginBalance2 == 0, "not expected balance");
    }

    function test_AddTrade() public {
        setUpTest();
        //TODO
    }

    function test_getTrades() public {
        setUpTest();
        //TODO
    }

    function test_WithdrawAssets() public {
        test_IncreaseMargin();

        RiskEngine.removeAsset(ethereum);
        portfolio.withdrawAssets(ethereum);

        assertTrue(portfolio.userMarginBalance(ethereum) == 0);
    }

    function test_RemoveMargin_Swap() public {
        setUpReal();
        IIVXRiskEngine.AssetAttributes memory attributes = IIVXRiskEngine.AssetAttributes({
            collateralFactor: 500,
            marginFactors: IIVXRiskEngine.MarginFactors({
                marginFactorA: 0.3 ether,
                marginFactorB: 0.032 ether,
                marginFactorC: 1.03 ether,
                marginFactorD: 0.002 ether,
                marginFactorE: 1.03 ether
            }),
            shockLossFactors: IIVXRiskEngine.ShockLossFactors(0.3 ether, 0.2 ether)
        });
        RiskEngine.addAsset(ethereum, attributes, true); //100%

        //add 1 eth margin
        vm.deal(ALICE, 1 ether);
        vm.startPrank(ALICE);
            IWETH(ethereum).deposit{value: 1 ether}();
            ERC20(ethereum).approve(address(portfolio), 1 ether);
            portfolio.increaseMargin(ethereum, 1 ether);
            uint256 marginBalance = portfolio.userMarginBalance(ethereum);
            assertTrue(marginBalance == 1 ether);
            console.log("marginBalance: ", marginBalance);
        vm.stopPrank();

        //remove 500 dollars from margin
        uint256 amount = 500 ether;
        vm.prank(address(diem));
        portfolio.removeMargin(ALICE, amount);

        uint256 removed = oracle.getAmountInAsset(amount, ethereum);
        console.log("ethereum rm * spot   ", removed);
        uint256 marginBalance_after = portfolio.userMarginBalance(ethereum);
        console.log("marginBalance_after: ", marginBalance_after);
        assertTrue(marginBalance_after == marginBalance - removed, "margin balance not what was expected");
    }

    function test_ViewDollarMargin() public {
        setUpTest();
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
        RiskEngine.addAsset(ethereum, attributes, true);
        // RiskEngine.addAsset(stable, 500);

        //add 1 eth margin
        MockupERC20(ethereum).mint(address(portfolio), 1 ether);

        //add 1 dollars margin
        MockupERC20(stable).mint(address(portfolio), 1 * dollar);

        //view dollar margin
        uint256 AliceDollarMargin = RiskEngine.portfolioDollarMargin(portfolio);
        // console.log("AliceDollarMargin: ", AliceDollarMargin);
        assertTrue(AliceDollarMargin == 1501 ether);
    }

    function test_ViewEffectiveMargin() public {
        setUpTest();
        RiskEngine.removeAsset(stable);
        uint16 collateralFactor = 330; //33%
        IIVXRiskEngine.AssetAttributes memory attributes = IIVXRiskEngine.AssetAttributes({
            collateralFactor: collateralFactor,
            marginFactors: IIVXRiskEngine.MarginFactors({
                marginFactorA: 0.3 ether,
                marginFactorB: 0.032 ether,
                marginFactorC: 1.03 ether,
                marginFactorD: 0.002 ether,
                marginFactorE: 1.03 ether
            }),
            shockLossFactors: IIVXRiskEngine.ShockLossFactors(0.3 ether, 0.2 ether)
        });
        RiskEngine.addAsset(stable, attributes, true);
        RiskEngine.addAsset(ethereum, attributes, true);

        //add 1 eth margin
        MockupERC20(ethereum).mint(address(portfolio), 1 ether);

        //add 1 dollars margin
        MockupERC20(stable).mint(address(portfolio), 1 * dollar);

        uint256 effectiveMargin = RiskEngine.getEffectiveMargin(portfolio);
        uint256 dollarMargin = RiskEngine.portfolioDollarMargin(portfolio);
        // console.log("effective margin", effectiveMargin);
        // console.log("dollar margin", dollarMargin * collateralFactor / 1000);
        assertTrue(effectiveMargin == dollarMargin * collateralFactor / 1000, "effective margin not what was expected");
    }

    function test_ViewEffectiveMargin2() public {
        setUpTest();
        RiskEngine.removeAsset(stable);
        uint16 collateralFactor = 500; //50%
        IIVXRiskEngine.AssetAttributes memory attributes = IIVXRiskEngine.AssetAttributes({
            collateralFactor: collateralFactor,
            marginFactors: IIVXRiskEngine.MarginFactors({
                marginFactorA: 0.3 ether,
                marginFactorB: 0.032 ether,
                marginFactorC: 1.03 ether,
                marginFactorD: 0.002 ether,
                marginFactorE: 1.03 ether
            }),
            shockLossFactors: IIVXRiskEngine.ShockLossFactors(0.3 ether, 0.2 ether)
        });
        RiskEngine.addAsset(stable, attributes, true);
        RiskEngine.addAsset(ethereum, attributes, true);

        uint256 ethAmount = 2 ether;
        uint256 dollarAmount = 1000 * dollar;

        //add 1 eth margin
        MockupERC20(ethereum).mint(address(portfolio), ethAmount);
        assertTrue(portfolio.userMarginBalance(ethereum) == ethAmount);
        // console.log("Eth userMarginBalance   ", margin.userMarginBalance(ALICE, ethereum));

        //add 1 dollars margin
        MockupERC20(stable).mint(address(portfolio), dollarAmount);
        assertTrue(portfolio.userMarginBalance(stable) == dollarAmount);
        // console.log("Dollar userMarginBalance", margin.userMarginBalance(ALICE, stable));

        uint256 effectiveMargin = RiskEngine.getEffectiveMargin(portfolio);
        uint256 dollarMargin = RiskEngine.portfolioDollarMargin(portfolio);
        // console.log("effective margin", effectiveMargin);
        // console.log("dollar margin   ", dollarMargin);
        assertTrue(effectiveMargin == dollarMargin * collateralFactor / 1000);
    }

}
