pragma solidity ^0.8.18;

//HELPERS
import "forge-std/Test.sol";
import {IntegrationHelper, MockupAggregatorV3} from "./IntegrationHelper.sol";

//PROTOCOL CONTRACTS
import {IVXLP} from "../../src/liquidity/IVXLP.sol";
import {IVXQueue} from "../../src/liquidity/IVXQueue.sol";
import {IVXOracle} from "../../src/periphery/IVXOracle.sol";
import {IVXRiskEngine} from "../../src/margin/IVXRiskEngine.sol";
import {IVXDiem} from "../../src/options/IVXDiem.sol";
import {Binomial} from "../../src/libraries/Binomial.sol";
import {IVXExchange} from "../../src/exchange/IVXExchange.sol";

//INTERFACES
import {IIVXOracle} from "../../src/interface/periphery/IIVXOracle.sol";
import {IIVXDiem} from "../../src/interface/options/IIVXDiem.sol";
import {IERC20} from "../../src/interface/IERC20.sol";
import {IWETH} from "../interface/IWETH.sol";
import {IIVXDiemToken} from "../../src/interface/options/IIVXDiemToken.sol";
import {IIVXPortfolio} from "../../src/interface/margin/IIVXPortfolio.sol";
import {IIVXRiskEngine} from "../../src/interface/margin/IIVXRiskEngine.sol";

contract DiemTradingTest is IntegrationHelper {
    address buyer_winner = address(10);
    address buyer_loser = address(11);
    address seller_winner = address(12);
    address seller_loser = address(13);
    address user_liquidated = address(14);

    function setUp() public {
        deployRealDiem();

        //set up mockup token to manipulate price
        (DOGECOIN, DogecoinPriceFeed) = deployMockup(); //1 ether spot price

        oracle.setValues(DOGECOIN, IIVXOracle.EncodedData({beta: 1 ether, alpha: 30000000000000000}));

        oracle.setValues(weth, IIVXOracle.EncodedData({beta: 1 ether, alpha: 30000000000000000}));

        optionToken.setParams(IIVXDiemToken.OptionTradingParams(0.05 ether, 3600, 1 days, 4 days, 0.01 ether));

        oracle.setRiskFreeRate(weth, 500000000000000000);
        oracle.setRiskFreeRate(DOGECOIN, 500000000000000000);

        vm.prank(user);
        RiskEngine.createMarginAccount();

        // IIVXPortfolio margin = RiskEngine.userIVXPortfolio(user);
        IIVXRiskEngine.AssetAttributes memory attributes = IIVXRiskEngine.AssetAttributes({
            collateralFactor: 500,
            marginFactors: IIVXRiskEngine.MarginFactors({
                marginFactorA: 0.3 ether,
                marginFactorB: 0.032 ether,
                marginFactorC: 1.03 ether,
                marginFactorD: 0.002 ether,
                marginFactorE: 1.03 ether
            }),
            shockLossFactors: IIVXRiskEngine.ShockLossFactors(0.05 ether, 0.05 ether)
        });

        RiskEngine.addAsset(DOGECOIN, attributes, true);

        setUpLiquidity_Depositors();
    }

    function setUp_Traders_Accounts() public {
        //create margin accounts
        vm.prank(buyer_winner);
        RiskEngine.createMarginAccount();

        // vm.prank(ALICE);
        // RiskEngine.createMarginAccount();

        vm.prank(buyer_loser);
        RiskEngine.createMarginAccount();

        vm.prank(BOB);
        RiskEngine.createMarginAccount();

        vm.prank(seller_winner);
        RiskEngine.createMarginAccount();

        vm.prank(CHAD);
        RiskEngine.createMarginAccount();

        vm.prank(seller_loser);
        RiskEngine.createMarginAccount();

        vm.prank(DEGEN);
        RiskEngine.createMarginAccount();

        vm.prank(user_liquidated);
        RiskEngine.createMarginAccount();

        //set up traders accounts

        addMarginWETH(10 ether, buyer_winner); //10 ether
        addMarginUSDC(1000 * 10 ** 6, buyer_winner); //1000 usdc

        addMarginWETH(10 ether, ALICE); //10 ether

        addMarginWETH(1 ether, buyer_loser); //1 ether
        addMarginUSDC(100 * 10 ** 6, buyer_loser); //100 usdc

        addMarginWETH(1 ether, BOB); //1 ether

        addMarginWETH(10 ether, seller_winner); //10 ether
        addMarginUSDC(1000 * 10 ** 6, seller_winner); //1000 usdc

        addMarginWETH(10 ether, CHAD); //10 ether

        addMarginWETH(1 ether, seller_loser); //1 ether
        addMarginUSDC(100 * 10 ** 6, seller_loser); //100 usdc

        addMarginWETH(1 ether, DEGEN); //1 ether

        addMarginWETH(0.5 ether, user_liquidated); //0.5 ether
        addMarginUSDC(50 * 10 ** 6, user_liquidated); //50 usdc
    }

    function test_Trades() public {
        uint256 spotPrice = oracle.getSpotPrice(weth);
        // console.log("spot price", spotPrice);
        uint256 strike = spotPrice + spotPrice * 50 / 1000;
        // console.log("strike price", strike);
        uint256 expiry = block.timestamp + 1 days;
        //creation option with more 5% than spot price
        createOption(weth, strike, expiry);
        setUpOneTrade_AddingMargin(10000, 1 ether, user, optionToken.currentOptionId() - 1);
    }

    function test_TradesArray() public {
        uint256 spotPrice = oracle.getSpotPrice(weth);
        // console.log("spot price", spotPrice);
        uint256 strike = spotPrice + spotPrice * 50 / 1000;
        // console.log("strike price", strike);
        uint256 expiry = block.timestamp + 1 days;
        //creation option with more 5% than spot price
        createOption(weth, strike, expiry);
        addMarginUSDC(100000 * 1e6, user);
        IIVXDiem.TradeInfo[] memory trades = new IIVXDiem.TradeInfo[](4);
        trades[0] = IIVXDiem.TradeInfo({optionID: optionToken.currentOptionId() - 1, amountContracts: 1 ether});
        trades[1] = IIVXDiem.TradeInfo({optionID: optionToken.currentOptionId() - 2, amountContracts: 2 ether});
        trades[2] = IIVXDiem.TradeInfo({optionID: optionToken.currentOptionId() - 3, amountContracts: 3 ether});
        trades[3] = IIVXDiem.TradeInfo({optionID: optionToken.currentOptionId(), amountContracts: 4 ether});
        vm.prank(user);
        diem.openTrades(trades);

        console.log("lp interest rate", lp.interestRate());
    }

}
