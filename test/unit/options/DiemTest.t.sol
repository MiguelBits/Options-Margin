pragma solidity ^0.8.18;

//HELPERS
import "forge-std/Test.sol";
import {Helper} from "../../helpers/Helper.sol";
import {ConvertDecimals} from "../../../src/libraries/ConvertDecimals.sol";
import {Math} from "../../../src/libraries/math/Math.sol";

//PROTOCOL CONTRACTS
import {IVXLP} from "../../../src/liquidity/IVXLP.sol";
import {IVXQueue} from "../../../src/liquidity/IVXQueue.sol";
import {IVXOracle} from "../../../src/periphery/IVXOracle.sol";
import {IVXRiskEngine} from "../../../src/margin/IVXRiskEngine.sol";
import {IVXDiem} from "../../../src/options/IVXDiem.sol";
import {IVXPortfolio} from "../../../src/margin/IVXPortfolio.sol";
import {Binomial} from "../../../src/libraries/Binomial.sol";

//INTERFACES
import {IIVXPortfolio} from "../../../src/interface/margin/IIVXPortfolio.sol";
import {IIVXRiskEngine} from "../../../src/interface/margin/IIVXRiskEngine.sol";
import {IIVXOracle} from "../../../src/interface/periphery/IIVXOracle.sol";
import {IIVXDiem} from "../../../src/interface/options/IIVXDiem.sol";
import {IERC20} from "../../../src/interface/IERC20.sol";
import {IIVXDiemToken} from "../../../src/interface/options/IIVXDiemToken.sol";
import {IWETH} from "../../interface/IWETH.sol";

contract DiemTest is Helper {
    address public weth;
    address public weth_feed = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address public usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public usdc_feed = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address public bitcoin = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address public bitcoin_feed = 0x6ce185860a4963106506C203335A2910413708e9;
    address public link = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;
    address public link_feed = 0x86E53CF1B870786351Da77A57575e79CB55812CB;

    function setUp() public {
        deployTestDiem();

        weth = address(mockupWETH);
        usdc = address(mockupERC20);
    }

    function test_openTrade_BuyCall() public returns(uint256 _fee) {
        address buyer = ALICE;

        //*Start create option 1
        // uint256 spot = oracle.getSpotPrice(weth);
        uint256 strike = 1530 ether; //2% above spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);
        uint256 old_bal = portfolio.userMarginBalance(usdc);

        //open trade
        uint256 optionId = 1; //BUY CALL
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        //check portfolio and assert

        //get fees
        (uint256 fee, uint256 premium,,) = optionToken.calculateCosts(optionId, nContracts, false);
        console.log("fee:     %s", fee);
        console.log("premium: %s", premium);
        _fee = fee;

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);
        console.log("old_bal: %s", old_bal);

        assertTrue(new_bal < old_bal, "should be 10k usdc - fee");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == nContracts, "should be 10 contracts open");
    }

    function test_openTrade_SellCall() public {
        address buyer = ALICE;
        //*Start create option 1
        // uint256 spot = oracle.getSpotPrice(weth);
        uint256 strike = 1530 ether; //2% above spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);
        uint256 old_bal = portfolio.userMarginBalance(usdc);

        //open trade
        uint256 optionId = 2; //SELL CALL
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        //check portfolio and assert

        //get fees
        (uint256 fee, uint256 premium,,) = optionToken.calculateCosts(optionId, nContracts, false);
        console.log("fee:     %s", fee);
        console.log("premium: %s", premium);

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);
        console.log("old_bal: %s", old_bal);

        assertTrue(new_bal > old_bal, "should be bigger because user received premium");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == nContracts, "should be 10 contracts open");
    }

    function test_FailNotEnoughMargin_MakesLiquidatable() public {
        address buyer = ALICE;
        //*Start create option 1
        // uint256 spot = oracle.getSpotPrice(weth);
        uint256 strike = 1530 ether; //2% above spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10 * 1e6);
        newMarginAccountFund(buyer, usdc, 10 * 1e6); //10 usdc

        //open trade
        uint256 optionId = 1; //BUY CALL
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IIVXPortfolio.IVXPortfolio_PortfolioLiquidatable.selector));
        diem.openTrades(tradeInfos);
        vm.stopPrank();
    }

    function test_closeTrade_BuyCall_Profit() public returns(uint256 _fee){
        test_openTrade_BuyCall();

        uint256 nContracts = 10 ether;
        uint256 optionId = 1; //BUY CALL

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(ALICE);
        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        uint256 hf1 = diem.calculateHealthFactor(portfolio);
        console.log("hf1: %s", hf1);

        (uint256 fee, uint256 premium,,) = optionToken.calculateCosts(optionId, nContracts, false);
        console.log("Ofee:     %s", fee);
        console.log("Opremium: %s", premium);

        //warp time & change premium
        vm.warp(block.timestamp + 6 hours);
        mockupAssetAggregatorV3.setPrice(1550 ether);
        // console.log("oracle spot price", oracle.getSpotPrice(weth));

        (/*uint256 nfee*/, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        // console.log("Nfee:     %s", nfee);
        console.log("Npremium: %s", npremium);

        IIVXDiem.Trade memory _trade = portfolio.getOptionIdTrade(optionId);

        console.log("calculate pnl");
        (, _fee) = diem.calculatePnl(_trade, nContracts);

        console.log("Close option");
        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));
        console.log("Closed");
        // uint256 new_amm_bal = mockupERC20.balanceOf(address(lp));

        uint256 hf2 = diem.calculateHealthFactor(portfolio);
        console.log("hf2: %s", hf2);

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        (int256 deltaExposure, int256 vegaExposure) = lp.DeltaAndVegaExposure(weth);
        // console.log("open contracts",portfolio.getOptionIdTrade(optionId).contractsOpen);
        assertTrue(deltaExposure == 0, "should be 0 delta");
        assertTrue(vegaExposure == 0, "should be 0 vega");
        assertTrue(new_bal > old_bal, "profit on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(portfolio.getOptionIdTrade(optionId).borrowedAmount == 0, "borrow == 0");
        assertTrue(hf2 < hf1, "hf should improve");
        assertTrue(npremium > premium, "premium should increase");
        // assertTrue(new_amm_bal < old_amm_bal, "amm should decrease");

        // uint256 portfolioPNL = new_bal - old_bal;
        // uint256 premiumPNL = npremium - premium;
        // console.log("portfolioPNL: %s", portfolioPNL);
        // console.log("premiumPNL:   %s", premiumPNL);
    }

    function test_closeTrade_BuyCall_Loss() public {
        test_openTrade_BuyCall();

        uint256 nContracts = 10 ether;
        uint256 optionId = 1; //BUY CALL

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(ALICE);
        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        uint256 hf1 = diem.calculateHealthFactor(portfolio);
        console.log("hf1: %s", hf1);

        (uint256 fee, uint256 premium,,) = optionToken.calculateCosts(optionId, nContracts, false);
        console.log("Ofee:     %s", fee);
        console.log("Opremium: %s", premium);

        //warp time & change premium
        vm.warp(block.timestamp + 6 hours);

        (uint256 nfee, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        console.log("Nfee:     %s", nfee);
        console.log("Npremium: %s", npremium);

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 hf2 = diem.calculateHealthFactor(portfolio);
        console.log("hf2: %s", hf2);

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        (int256 deltaExposure, int256 vegaExposure) = lp.DeltaAndVegaExposure(weth);
        // console.log("open contracts",portfolio.getOptionIdTrade(optionId).contractsOpen);

        assertTrue(deltaExposure == 0, "should be 0");
        assertTrue(vegaExposure == 0, "should be 0");
        assertTrue(new_bal < old_bal, "loss on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(portfolio.getOptionIdTrade(optionId).borrowedAmount == 0, "borrow == 0");
        assertTrue(hf2 < hf1, "hf should improve");
        assertTrue(npremium < premium, "premium should decrease");

        uint256 portfolioPNL = old_bal - new_bal;
        uint256 premiumPNL = premium - npremium;
        console.log("portfolioPNL: %s", portfolioPNL);
        console.log("premiumPNL:   %s", premiumPNL);
    }

    function test_closeTrade_SellCall_Profit() public {
        address buyer = ALICE;

        uint256 strike = 1530 ether; //2% above spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 2; //SELL CALL
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        (uint256 fee, uint256 premium,,) = optionToken.calculateCosts(optionId, nContracts, false);
        console.log("Ofee:     %s", fee);
        console.log("Opremium: %s", premium);

        //warp time & change premium
        vm.warp(block.timestamp + 6 hours);

        (uint256 nfee, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        console.log("Nfee:     %s", nfee);
        console.log("Npremium: %s", npremium);

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        (int256 deltaExposure, int256 vegaExposure) = lp.DeltaAndVegaExposure(weth);
        // console.log("open contracts",portfolio.getOptionIdTrade(optionId).contractsOpen);

        assertTrue(deltaExposure == 0, "should be 0");
        assertTrue(vegaExposure == 0, "should be 0");
        assertTrue(new_bal > old_bal, "profit on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(portfolio.getOptionIdTrade(optionId).borrowedAmount == 0, "borrow == 0");
        assertTrue(npremium < premium, "premium should decrease");

        uint256 portfolioPNL = new_bal - old_bal;
        uint256 premiumPNL = premium - npremium;
        console.log("portfolioPNL: %s", portfolioPNL);
        console.log("premiumPNL:   %s", premiumPNL);
    }

    function test_closeTrade_SellCall_Loss() public {
        address buyer = ALICE;

        uint256 strike = 1530 ether; //2% above spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 2; //SELL CALL
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        (uint256 fee, uint256 premium,,) = optionToken.calculateCosts(optionId, nContracts, false);
        console.log("Ofee:     %s", fee);
        console.log("Opremium: %s", premium);
        //warp time & change premium
        vm.warp(block.timestamp + 6 hours);
        mockupAssetAggregatorV3.setPrice(1550 ether);
        // console.log("oracle spot price", oracle.getSpotPrice(weth));

        (uint256 nfee, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        console.log("Nfee:     %s", nfee);
        console.log("Npremium: %s", npremium);

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 hf2 = diem.calculateHealthFactor(portfolio);

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        (int256 deltaExposure, int256 vegaExposure) = lp.DeltaAndVegaExposure(weth);
        // console.log("open contracts",portfolio.getOptionIdTrade(optionId).contractsOpen);

        assertTrue(deltaExposure == 0, "should be 0 delta");
        assertTrue(vegaExposure == 0, "should be 0 vega");
        assertTrue(new_bal < old_bal, "loss on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(portfolio.getOptionIdTrade(optionId).borrowedAmount == 0, "borrow == 0");
        assertTrue(hf2 == 0, "hf should go to 0");
        assertTrue(npremium > premium, "premium should increase");

        uint256 portfolioPNL = old_bal - new_bal;
        uint256 premiumPNL = npremium - premium;
        console.log("portfolioPNL: %s", portfolioPNL);
        console.log("premiumPNL:   %s", premiumPNL);
    }

    function test_closeTrade_BuyPut_Profit() public {
        address buyer = ALICE;

        uint256 strike = 1470 ether; //2% below spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 3; //BUY PUT
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        (uint256 fee, uint256 premium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        console.log("Ofee:     %s", fee);
        console.log("Opremium: %s", premium);

        vm.warp(block.timestamp + 6 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike - 70 ether));

        (uint256 nfee, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        console.log("Nfee:     %s", nfee);
        console.log("Npremium: %s", npremium);

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 hf2 = diem.calculateHealthFactor(portfolio);

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        (int256 deltaExposure, int256 vegaExposure) = lp.DeltaAndVegaExposure(weth);
        assertTrue(deltaExposure == 0, "should be 0 delta");
        assertTrue(vegaExposure == 0, "should be 0 vega");
        assertTrue(new_bal > old_bal, "profit on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(portfolio.getOptionIdTrade(optionId).borrowedAmount == 0, "borrow == 0");
        assertTrue(hf2 == 0, "hf should go to 0");
        assertTrue(npremium > premium, "premium should increase");
    }

    function test_closeTrade_BuyPut_Loss() public {
        address buyer = ALICE;

        uint256 strike = 1470 ether; //2% below spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 3; //BUY PUT
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        (uint256 fee, uint256 premium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        console.log("Ofee:     %s", fee);
        console.log("Opremium: %s", premium);

        vm.warp(block.timestamp + 6 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike + 70 ether));

        (uint256 nfee, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        console.log("Nfee:     %s", nfee);
        console.log("Npremium: %s", npremium);

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 hf2 = diem.calculateHealthFactor(portfolio);

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        (int256 deltaExposure, int256 vegaExposure) = lp.DeltaAndVegaExposure(weth);
        assertTrue(deltaExposure == 0, "should be 0 delta");
        assertTrue(vegaExposure == 0, "should be 0 vega");
        assertTrue(new_bal < old_bal, "loss on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(portfolio.getOptionIdTrade(optionId).borrowedAmount == 0, "borrow == 0");
        assertTrue(hf2 == 0, "hf should go to 0");
        assertTrue(npremium < premium, "premium should decrease");
    }

    function test_closeTrade_SellPut_Profit() public {
        address buyer = ALICE;

        uint256 strike = 1470 ether; //2% below spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 4; //SELL PUT
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        (uint256 fee, uint256 premium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        console.log("Ofee:     %s", fee);
        console.log("Opremium: %s", premium);

        vm.warp(block.timestamp + 6 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike + 70 ether));

        (uint256 nfee, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        console.log("Nfee:     %s", nfee);
        console.log("Npremium: %s", npremium);

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 hf2 = diem.calculateHealthFactor(portfolio);

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        (int256 deltaExposure, int256 vegaExposure) = lp.DeltaAndVegaExposure(weth);
        assertTrue(deltaExposure == 0, "should be 0 delta");
        assertTrue(vegaExposure == 0, "should be 0 vega");
        assertTrue(new_bal > old_bal, "profit on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(portfolio.getOptionIdTrade(optionId).borrowedAmount == 0, "borrow == 0");
        assertTrue(hf2 == 0, "hf should go to 0");
        assertTrue(npremium < premium, "premium should decrease");
    }

    function test_closeTrade_SellPut_Loss() public {
        address buyer = ALICE;

        uint256 strike = 1470 ether; //2% below spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 4; //SELL PUT
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        (uint256 fee, uint256 premium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        console.log("Ofee:     %s", fee);
        console.log("Opremium: %s", premium);

        vm.warp(block.timestamp + 6 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike - 70 ether));

        (uint256 nfee, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        console.log("Nfee:     %s", nfee);
        console.log("Npremium: %s", npremium);

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 hf2 = diem.calculateHealthFactor(portfolio);

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        (int256 deltaExposure, int256 vegaExposure) = lp.DeltaAndVegaExposure(weth);
        assertTrue(deltaExposure == 0, "should be 0 delta");
        assertTrue(vegaExposure == 0, "should be 0 vega");
        assertTrue(new_bal < old_bal, "loss on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(portfolio.getOptionIdTrade(optionId).borrowedAmount == 0, "borrow == 0");
        assertTrue(hf2 == 0, "hf should go to 0");
        assertTrue(npremium > premium, "premium should increase");
    }

    function test_closeExpiredTrade_BuyCall_Profit() public {
        address buyer = ALICE;

        uint256 strike = 1550 ether;
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 1; //BUY CALL
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        vm.warp(block.timestamp + 25 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike + 100 ether));

        (, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        // console.log("Npremium: %s", npremium);
        assertTrue(npremium == 100 ether, "payoff should be 100"); // as this is the value of settlement payoff

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        assertTrue(new_bal > old_bal, "profit on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(
            optionToken.getOptionIDAttributes(optionId).status.settlementPayoff == 100 ether,
            "should be settlement payoff"
        );
        assertTrue(optionToken.getOptionIDAttributes(optionId).status.isSettled == true, "should be settled");
    }

    function test_closeExpiredTrade_BuyCall_Loss() public {
        address buyer = ALICE;

        uint256 strike = 1550 ether;
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 1; //BUY CALL
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        vm.warp(block.timestamp + 25 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike - 100 ether));

        (, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        // console.log("Npremium: %s", npremium);
        assertTrue(npremium == 0 ether, "payoff should be 0"); // as this is the value of settlement payoff

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        assertTrue(new_bal < old_bal, "loss on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(
            optionToken.getOptionIDAttributes(optionId).status.settlementPayoff == 0, "should be settlement payoff"
        );
        assertTrue(optionToken.getOptionIDAttributes(optionId).status.isSettled == true, "should be settled");
    }

    function test_closeExpiredTrade_SellCall_Profit() public {
        address buyer = ALICE;

        uint256 strike = 1550 ether;
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 2; //SELL CALL
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        vm.warp(block.timestamp + 25 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike - 100 ether));

        (, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        // console.log("Npremium: %s", npremium);
        assertTrue(npremium == 0, "payoff should be 0"); // as this is the value of settlement payoff

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        assertTrue(new_bal > old_bal, "profit on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(
            optionToken.getOptionIDAttributes(optionId).status.settlementPayoff == 0, "should be settlement payoff"
        );
        assertTrue(optionToken.getOptionIDAttributes(optionId).status.isSettled == true, "should be settled");
    }

    function test_closeExpiredTrade_SellCall_Loss() public {
        address buyer = ALICE;

        uint256 strike = 1550 ether;
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 2; //SELL CALL
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        vm.warp(block.timestamp + 25 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike + 100 ether));

        (, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        // console.log("Npremium: %s", npremium);
        assertTrue(npremium == 100 ether, "payoff should be 100 ether"); // as this is the value of settlement payoff

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        assertTrue(new_bal < old_bal, "loss on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(
            optionToken.getOptionIDAttributes(optionId).status.settlementPayoff == 100 ether,
            "should be settlement payoff"
        );
        assertTrue(optionToken.getOptionIDAttributes(optionId).status.isSettled == true, "should be settled");
    }

    function test_closeExpiredTrade_BuyPut_Profit() public {
        address buyer = ALICE;

        uint256 strike = 1550 ether;
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 3; //BUY PUT
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        vm.warp(block.timestamp + 25 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike - 100 ether));

        (, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        // console.log("Npremium: %s", npremium);
        assertTrue(npremium == 100 ether, "payoff should be 100 ether"); // as this is the value of settlement payoff

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        assertTrue(new_bal > old_bal, "profit on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(
            optionToken.getOptionIDAttributes(optionId).status.settlementPayoff == 100 ether,
            "should be settlement payoff"
        );
        assertTrue(optionToken.getOptionIDAttributes(optionId).status.isSettled == true, "should be settled");
    }

    function test_closeExpiredTrade_BuyPut_Loss() public {
        address buyer = ALICE;

        uint256 strike = 1550 ether;
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 3; //BUY PUT
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        vm.warp(block.timestamp + 25 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike + 100 ether));

        (, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        // console.log("Npremium: %s", npremium);
        assertTrue(npremium == 0, "payoff should be 0"); // as this is the value of settlement payoff

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        assertTrue(new_bal < old_bal, "loss on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(
            optionToken.getOptionIDAttributes(optionId).status.settlementPayoff == 0, "should be settlement payoff"
        );
        assertTrue(optionToken.getOptionIDAttributes(optionId).status.isSettled == true, "should be settled");
    }

    function test_closeExpiredTrade_SellPut_Profit() public {
        address buyer = ALICE;

        uint256 strike = 1550 ether;
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 4; //SELL PUT
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        vm.warp(block.timestamp + 25 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike + 100 ether));

        (, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        // console.log("Npremium: %s", npremium);
        assertTrue(npremium == 0, "payoff should be 0"); // as this is the value of settlement payoff

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        assertTrue(new_bal > old_bal, "profit on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(
            optionToken.getOptionIDAttributes(optionId).status.settlementPayoff == 0, "should be settlement payoff"
        );
        assertTrue(optionToken.getOptionIDAttributes(optionId).status.isSettled == true, "should be settled");
    }

    function test_closeMakesOptionSettle_Untradeable() public {
        test_closeExpiredTrade_SellPut_Profit();

        uint256 optionId = 4;
        uint256 nContracts = 10 ether;
        address buyer = ALICE;
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        //check contracts open of trade
        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IIVXDiemToken.IVXOptionExpired.selector, 4));
        diem.openTrades(tradeInfos);
        vm.stopPrank();

        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
    }

    function test_closeExpiredTrade_SellPut_Loss() public {
        address buyer = ALICE;

        uint256 strike = 1550 ether;
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 4; //SELL PUT
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        uint256 old_bal = portfolio.userMarginBalance(usdc);
        console.log("old_bal: %s", old_bal);

        vm.warp(block.timestamp + 25 hours);
        mockupAssetAggregatorV3.setPrice(int256(strike - 100 ether));

        (, uint256 npremium,,) = optionToken.calculateCosts(optionId, nContracts, true);
        // console.log("Npremium: %s", npremium);
        assertTrue(npremium == 100 ether, "payoff should be 100 ether"); // as this is the value of settlement payoff

        vm.prank(ALICE);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);

        assertTrue(new_bal < old_bal, "loss on balance");
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == 0, "should be 0 contracts open");
        assertTrue(
            optionToken.getOptionIDAttributes(optionId).status.settlementPayoff == 100 ether,
            "should be settlement payoff"
        );
        assertTrue(optionToken.getOptionIDAttributes(optionId).status.isSettled == true, "should be settled");
    }

    function test_FullLiquidateAbovePortfolioCollateralValue() public {
        //*Start create option 1
        // uint256 spot = oracle.getSpotPrice(weth); //1500
        uint256 strike = 1530 ether; //2% above spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(ALICE, 10000 * 1e6);
        newMarginAccountFund(ALICE, usdc, 150 * 1e6); //150 usdc => margin account

        //open trade
        uint256 amountContracts = 4 ether;
        uint256 optionId = 3;
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, amountContracts); //2 contracts

        vm.prank(ALICE);
        diem.openTrades(tradeInfos);

        //check portfolio
        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(ALICE);
        // console.log("user margin balance", RiskEngine.userIVXPortfolio(ALICE).userMarginBalance(usdc));
        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s", new_bal);
        // assertTrue(new_bal == 100 * 1e6 - fee);
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == amountContracts);

        bool isEligible = diem.isPortfolioLiquidatable(portfolio);
        console.log("isEligible: %s", isEligible);

        uint256 hf1 = diem.calculateHealthFactor(portfolio);
        console.log("HF1: %s", hf1);

        console.log("oracle spot price1", oracle.getSpotPrice(weth));
        console.log("option 1 strike   ", optionToken.getOptionIDAttributes(optionId).option.strikePrice);

        //time passed 10hours (2h before expiry) and spot price went up X times
        vm.warp(block.timestamp + 10 hours);
        mockupAssetAggregatorV3.setPrice(int256(oracle.getSpotPrice(weth) * 6));
        console.log("oracle spot price2", oracle.getSpotPrice(weth));

        uint256 hf2 = diem.calculateHealthFactor(portfolio);
        assertTrue(hf2 == type(uint256).max, "hf2 not max uint");
        isEligible = diem.isPortfolioLiquidatable(portfolio);
        console.log("isEligible: %s", isEligible);
        assertTrue(isEligible == true, "should be eligible for liquidation");

        //liquidate
        vm.prank(ALICE);
        diem.liquidate(ALICE);
        console.log("liquidated");

        assertTrue(diem.calculateHealthFactor(portfolio) == 0, "health factor should decrease");
        //assert all assets were liquidated
        assertTrue(RiskEngine.portfolioDollarMargin(portfolio) == 0, "user still has assets");
    }

    function test_liquidate() public {
        //*Start create option 1
        // uint256 spot = oracle.getSpotPrice(weth); //1500
        uint256 strike = 1530 ether; //2% above spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(ALICE, 10000 * 1e6);
        newMarginAccountFund(ALICE, usdc, 150 * 1e6); //150 usdc => margin account

        //open trade
        uint256 amountContracts = 2 ether;
        uint256 optionId = 3;
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, amountContracts); //2 contracts

        vm.prank(ALICE);
        diem.openTrades(tradeInfos);

        //check portfolio
        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(ALICE);
        // console.log("user margin balance", RiskEngine.userIVXPortfolio(ALICE).userMarginBalance(usdc));
        uint256 new_bal = portfolio.userMarginBalance(usdc);

        console.log("new_bal: %s", new_bal);
        // assertTrue(new_bal == 100 * 1e6 - fee);
        assertTrue(portfolio.getOptionIdTrade(optionId).contractsOpen == amountContracts);

        bool isEligible = diem.isPortfolioLiquidatable(portfolio);
        console.log("isEligible: %s", isEligible);

        uint256 hf1 = diem.calculateHealthFactor(portfolio);

        console.log("HF1: %s", hf1);

        console.log("oracle spot price1", oracle.getSpotPrice(weth));
        console.log("option 1 strike   ", optionToken.getOptionIDAttributes(optionId).option.strikePrice);

        //time passed 10hours (2h before expiry) and spot price went up X times
        vm.warp(block.timestamp + 10 hours);
        mockupAssetAggregatorV3.setPrice(int256(oracle.getSpotPrice(weth) * 6));
        console.log("oracle spot price2", oracle.getSpotPrice(weth));

        uint256 hf2 = diem.calculateHealthFactor(portfolio);

        console.log("HF2: %s", hf2);
        isEligible = diem.isPortfolioLiquidatable(portfolio);
        console.log("isEligible: %s", isEligible);
        assertTrue(isEligible == true, "should be eligible for liquidation");

        //liquidate
        console.log("liquidating");
        vm.prank(ALICE);
        diem.liquidate(ALICE);
        console.log("liquidated");

        assertTrue(diem.calculateHealthFactor(portfolio) == 0, "health factor should decrease");
        // console.log("hf3", diem.calculateHealthFactor(portfolio));
    }

    function test_forceClose() public {
        test_openTrade_BuyCall();

        //force close requires option to be settled
        vm.warp(block.timestamp + 25 hours);
        mockupAssetAggregatorV3.setPrice(1550 ether);

        optionToken.settleOptionsExpired(4);
    }

    function test_TradeMultipleOptionsOfSameId() public {
        address buyer = ALICE;

        //*Start create option 1
        // uint256 spot = oracle.getSpotPrice(weth);
        uint256 strike = 1530 ether; //2% above spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);

        //open trade
        uint256 optionId = 1; //BUY CALL
        uint256 nContracts = 1 ether;
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);
        //log premium
        (, uint256 premium,,) = optionToken.calculateCosts(optionId, nContracts, false);
        console.log("premium", premium);
        //get trade premium
        uint256 avgPremium = portfolio.getOptionIdTrade(optionId).averageEntry;
        console.log("avgPrem", avgPremium);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);
        //log premium
        (, premium,,) = optionToken.calculateCosts(optionId, nContracts, false);
        console.log("premium", premium);
        //get trade premium
        avgPremium = portfolio.getOptionIdTrade(optionId).averageEntry;
        console.log("avgPrem", avgPremium);
        assertTrue(avgPremium == premium, "avg premium and premium should be equal");

        vm.warp(block.timestamp + 6 hours);

        IIVXDiem.TradeInfo[] memory new_tradeInfos = new IIVXDiem.TradeInfo[](1);
        new_tradeInfos[0] = IIVXDiem.TradeInfo(optionId, 10 ether);

        vm.prank(buyer);
        diem.openTrades(new_tradeInfos);
        //log premium
        (, premium,,) = optionToken.calculateCosts(optionId, nContracts, false);
        console.log("premium", premium);
        //get trade premium
        avgPremium = portfolio.getOptionIdTrade(optionId).averageEntry;
        console.log("avgPrem", avgPremium);
        assertTrue(avgPremium != premium, "this time premium should not be equal to the avg");
    }

    function test_ClosePartialTradeSameId() public {
        test_TradeMultipleOptionsOfSameId(); //total traded 12 contracts

        address buyer = ALICE;
        uint256 optionId = 1; //BUY CALL
        uint256 nContracts = 10 ether;

        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.closeTrades(tradeInfos);

        //get trade from portfolio
        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);
        IIVXDiem.Trade memory trade = portfolio.getOptionIdTrade(optionId);
        assertTrue(trade.contractsOpen == 2 ether, "invalid closed amount");
    }

    function test_open_close_open_close_sameOption() public {
        test_openTrade_BuyCall();

        address buyer = ALICE;
        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);
        uint256 old_bal = portfolio.userMarginBalance(usdc);

        //open trade
        uint256 optionId = 1; //BUY CALL
        uint256 nContracts = 10 ether; //10 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.warp(block.timestamp + 10 hours);
        mockupAssetAggregatorV3.setPrice(1550 ether); //strike = 1550

        vm.prank(buyer);
        diem.closeTrade(tradeInfos[0]);

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        assertTrue(new_bal > old_bal, "should be profit");

        vm.warp(block.timestamp + 1 hours);
        mockupAssetAggregatorV3.setPrice(1560 ether); //strike = 1560

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        old_bal = portfolio.userMarginBalance(usdc);

        vm.warp(block.timestamp + 1 hours);
        mockupAssetAggregatorV3.setPrice(1570 ether); //strike = 1570

        vm.prank(buyer);
        diem.closeTrade(tradeInfos[0]);

        new_bal = portfolio.userMarginBalance(usdc);

        assertTrue(new_bal > old_bal, "should be profit");
    }

    function testFeeDistributionOpen() public {

        uint256 old_lp_bal = lp.collateral().balanceOf(address(lp));
        
        uint256 fee = test_openTrade_BuyCall();
        fee = ConvertDecimals.convertFrom18AndRoundDown(fee, lp.collateral().decimals());

        uint256 leftOverBal = lp.collateral().balanceOf(address(diem));
        console.log("leftOverBal", leftOverBal);

        uint256 new_treasury_bal = lp.collateral().balanceOf(TREASURY);
        uint256 new_lp_bal = lp.collateral().balanceOf(address(lp));
        uint256 new_staker_bal = lp.collateral().balanceOf(address(STAKER));

        uint256 treasury_fee = 5294031;
        uint256 staker_fee = 2647015;
        uint256 lp_fee = 882338;
        uint256 sum_fees = (treasury_fee + staker_fee + lp_fee);
        console.log("sum_fees", sum_fees);

        //assert new balances - old ones are equal to the above fees
        assertTrue(new_treasury_bal == treasury_fee, "treasury fee");
        assertTrue(new_lp_bal - old_lp_bal == lp_fee, "lp fee");
        assertTrue(new_staker_bal == staker_fee, "staker fee");
        console.log("fee     ", fee - leftOverBal);
        console.log("sum_fees", sum_fees);
    }

    function testFeeDistributionClose() public {
        
        uint256 fee = test_closeTrade_BuyCall_Profit();
        fee = ConvertDecimals.convertFrom18AndRoundDown(fee, lp.collateral().decimals());
        console.log("fee", fee);

        uint256 leftOverBal = lp.collateral().balanceOf(address(diem));
        console.log("leftOverBal", leftOverBal);

        uint256 treasury_fee = 6454974;
        uint256 staker_fee = 3227487;
        uint256 lp_fee = 1075829;
        uint256 sum_fees = (treasury_fee + staker_fee + lp_fee);
        console.log("sum_fees", sum_fees);

        console.log("fee     ", fee - leftOverBal);
        console.log("sum_fees", sum_fees);
    }

    function testRevertOpen0Contracts() public {
        address buyer = ALICE;

        //*Start create option 1
        // uint256 spot = oracle.getSpotPrice(weth);
        uint256 strike = 1530 ether; //2% above spot
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        //open trade
        uint256 optionId = 1; //BUY CALL
        uint256 nContracts = 0 ether; //0 contracts
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IIVXDiem.InvalidTrade.selector));
        diem.openTrades(tradeInfos);
    }
    
    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Proofs of concept ///////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////

    // closing / settling after expiry needs to query the closest price to the expiry timestamp instead of the price at when it was settled
    function test_poc_buy_profit_call_afterExpiry() public {
        address buyer = ALICE;

        //*Start create option 1
        // uint256 spot = oracle.getSpotPrice(weth);
        uint256 strike = 1530 ether;
        createOption(strike, /*expiry:*/ 1 days + block.timestamp, weth);
        mockupERC20.mint(buyer, 10000 * 1e6);
        newMarginAccountFund(buyer, usdc, 10000 * 1e6); //10k usdc

        uint256 nContracts = 10 ether;
        uint256 optionId = 1; //BUY CALL
        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);
        uint256 old_bal = portfolio.userMarginBalance(usdc);
        IIVXDiem.TradeInfo[] memory tradeInfos = new IIVXDiem.TradeInfo[](1);
        tradeInfos[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(buyer);
        diem.openTrades(tradeInfos);

        separate();

        console.log("old_bal: %s %s", old_bal, old_bal / 1e6);

        mockupAssetAggregatorV3.setPrice(1545 ether);
        vm.warp(block.timestamp + 23 hours);

        // vm.prank(buyer);
        // diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));
        // if the trade is closed after 23 hours (option is not expired yet),
        // Balance before: 10017 usdc

        vm.warp(block.timestamp + 2 hours);
        mockupAssetAggregatorV3.setPrice(1550 ether);

        IIVXDiemToken.OptionAttributes memory attrs = optionToken.getOptionIDAttributes(optionId);

        console.log("-----------Option.expiry: %s", attrs.option.expiry);
        console.log("-----------Now: %s", block.timestamp);

        vm.prank(buyer);
        diem.closeTrade(IIVXDiem.TradeInfo(optionId, nContracts));
        // if the trade is closed after 35 hours (option is expired),
        // Balance before: 10089 usdc (making an extra profit)

        uint256 new_bal = portfolio.userMarginBalance(usdc);
        console.log("new_bal: %s %s", new_bal, new_bal / 1e6);
    }

    function createOptionAndFundBuyers() public {
        // Initially at 1500
        uint256 strike = 1580 ether;
        createOption(strike, block.timestamp + 1 days, weth);

        // Fund buyer 1
        mockupERC20.mint(ALICE, 10000 * 1e6);
        newMarginAccountFund(ALICE, usdc, 10000 * 1e6); //10k usdc

        // Fund buyer 2
        mockupERC20.mint(BOB, 10000 * 1e6);
        newMarginAccountFund(BOB, usdc, 10000 * 1e6); //10k usdc
    }

    function separate() public view {
        console.log("--------------------------------------------------");
    }

    function buyerCreateTrade() public {
        createOptionAndFundBuyers();

        uint256 optionId = 1;
        uint256 nContracts = 5 ether;

        // Buyer 1 opens trade
        IIVXPortfolio portfolio_1 = RiskEngine.userIVXPortfolio(ALICE);
        uint256 old_bal_1 = portfolio_1.userMarginBalance(usdc);

        IIVXDiem.TradeInfo[] memory tradeInfos_1 = new IIVXDiem.TradeInfo[](1);
        tradeInfos_1[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(ALICE);
        diem.openTrades(tradeInfos_1);

        uint256 new_bal_1 = portfolio_1.userMarginBalance(usdc);

        console.log("Buyer 1 old balance: %s %s", old_bal_1, old_bal_1 / 1e6);
        console.log("Buyer 1 new balance: %s %s", new_bal_1, new_bal_1 / 1e6);

        // Buyer 2 opens trade
        IIVXPortfolio portfolio_2 = RiskEngine.userIVXPortfolio(BOB);
        uint256 old_bal_2 = portfolio_2.userMarginBalance(usdc);

        IIVXDiem.TradeInfo[] memory tradeInfos_2 = new IIVXDiem.TradeInfo[](1);
        tradeInfos_2[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(BOB);
        diem.openTrades(tradeInfos_2);

        uint256 new_bal_2 = portfolio_2.userMarginBalance(usdc);

        console.log("Buyer 2 old balance: %s %s", old_bal_2, old_bal_2 / 1e6);
        console.log("Buyer 2 new balance: %s %s", new_bal_2, new_bal_2 / 1e6);

        separate();
    }

    //This test shows that fees will work as intended and premium is displaying correct values, returning correct pnls
    function test_openCloseProfitALICE_openCloseProfitBOB() public {
        buyerCreateTrade();

        uint256 optionId = 1;
        uint256 nContracts = 5 ether;

        mockupAssetAggregatorV3.setPrice(1575 ether);
        vm.warp(block.timestamp + 10 hours);

        // Buyer 1 closes trade
        IIVXPortfolio portfolio_1 = RiskEngine.userIVXPortfolio(ALICE);
        uint256 old_bal_1 = portfolio_1.userMarginBalance(usdc);

        IIVXDiem.TradeInfo[] memory tradeInfos_1 = new IIVXDiem.TradeInfo[](1);
        tradeInfos_1[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        // Buyer 1 opens trade
        uint256 new_bal_1 = portfolio_1.userMarginBalance(usdc);
        old_bal_1 = portfolio_1.userMarginBalance(usdc);

        separate();
        //log delta fees
        (uint256 fee, uint256 premium, int256 delta, uint256 vega) = optionToken.calculateCosts(1, nContracts, true);
        console.log("fee", fee);
        console.log("premium", premium);
        console.log("delta");
        console.logInt(delta);
        separate();

        // Uncomment below to force buyer 2 to lose profit
        for (uint256 i = 0; i < 10; i++) {
            tradeInfos_1 = new IIVXDiem.TradeInfo[](1);
            tradeInfos_1[0] = IIVXDiem.TradeInfo(optionId, nContracts / 10);

            vm.prank(ALICE);
            diem.closeTrades(tradeInfos_1);

            vm.warp(block.timestamp + 10 minutes);

            vm.prank(ALICE);
            diem.openTrades(tradeInfos_1);

            separate();
            //log delta fees
            (fee, premium, delta, vega) = optionToken.calculateCosts(1, nContracts, true);
            console.log("fee", fee);
            console.log("premium", premium);
            console.log("delta");
            console.logInt(delta);
            separate();
        }

        mockupAssetAggregatorV3.setPrice(1580 ether);
        vm.warp(block.timestamp + 12 hours);

        separate();
        //log delta fees
        (fee, premium, delta, vega) = optionToken.calculateCosts(1, nContracts, true);
        console.log("fee", fee);
        console.log("premium", premium);
        console.log("delta");
        console.logInt(delta);
        separate();

        vm.prank(ALICE);
        diem.closeTrades(tradeInfos_1);

        uint256 contractBal = portfolio_1.getOptionIdTrade(1).contractsOpen;
        console.log("contractBal", contractBal);

        new_bal_1 = portfolio_1.userMarginBalance(usdc);

        console.log("Buyer 1 old balance: %s %s", old_bal_1, old_bal_1 / 1e6);
        console.log("Buyer 1 new balance: %s %s", new_bal_1, new_bal_1 / 1e6);

        // Buyer 2 closes trade
        IIVXPortfolio portfolio_2 = RiskEngine.userIVXPortfolio(BOB);
        uint256 old_bal_2 = portfolio_2.userMarginBalance(usdc);

        IIVXDiem.TradeInfo[] memory tradeInfos_2 = new IIVXDiem.TradeInfo[](1);
        tradeInfos_2[0] = IIVXDiem.TradeInfo(optionId, nContracts);

        vm.prank(BOB);
        diem.closeTrades(tradeInfos_2);

        contractBal = portfolio_2.getOptionIdTrade(1).contractsOpen;
        console.log("contractBal", contractBal);

        uint256 new_bal_2 = portfolio_2.userMarginBalance(usdc);

        console.log("Buyer 2 old balance: %s %s", old_bal_2, old_bal_2 / 1e6);
        console.log("Buyer 2 new balance: %s %s", new_bal_2, new_bal_2 / 1e6);

        bool isSettled = optionToken.getOptionIDAttributes(1).status.isSettled;
        console.log("settled", isSettled);

        separate();
    }

    function test_BearSpreadPut() public {
        address buyer = ALICE;

        //create weth option 1535 strike, expiry 1 days
        uint256 strikeLong = 1535 ether; 
        createOption(strikeLong, /*expiry:*/ 1 days + block.timestamp, weth, true);

        //create weth option 1450 strike, expiry 1 days
        uint256 strikeBear = 1450 ether; 
        createOption(strikeBear, /*expiry:*/ 1 days + block.timestamp, weth, false);

        //buy put on both strikes
        IIVXDiem.TradeInfo[] memory trades = new IIVXDiem.TradeInfo[](2);
        trades[0] = IIVXDiem.TradeInfo(3, 1 ether); //buy put
        trades[1] = IIVXDiem.TradeInfo(7, 1 ether); //buy put

        newMarginAccountFund(buyer, usdc, 100 * 1e6); //10k usdc

        vm.prank(buyer);
        diem.openTrades(trades);

        IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);
        uint256 hf1 = diem.calculateHealthFactor(portfolio);
        console.log("hf1", hf1);

        //make price go to strikeLong
        vm.warp(block.timestamp + 23 hours);
        mockupAssetAggregatorV3.setPrice(int(strikeLong + 10 ether));

        uint256 hf2 = diem.calculateHealthFactor(portfolio);
        console.log("hf2", hf2);

        vm.prank(buyer);
        diem.closeTrade(trades[1]);

        uint256 hf3 = diem.calculateHealthFactor(portfolio);
        console.log("hf3", hf3);
        assertTrue(hf3 < hf2, "closing a trade never makes you increase health factor");
    }

    /* KNOW ISSUE = TODO must be fixed, user is liquidatable even when his PNL is positive*/
    // function test_BuySellPut() public {
    //     address buyer = ALICE;

    //     uint256 strikeLong = 1535 ether; 
    //     createOption(strikeLong, /*expiry:*/ 1 days + block.timestamp, weth, true);

    //     uint256 strikeBear = 1500 ether; 
    //     createOption(strikeBear, /*expiry:*/ 1 days + block.timestamp, weth, false);
    //     oracle.setStrikeVolatility(weth, strikeBear, 0.50 ether);

    //     //buy put on both strikes
    //     IIVXDiem.TradeInfo[] memory trades = new IIVXDiem.TradeInfo[](2);
    //     trades[0] = IIVXDiem.TradeInfo(3, 1 ether); //buy put
    //     trades[1] = IIVXDiem.TradeInfo(8, 1 ether); //sell put

    //     newMarginAccountFund(buyer, usdc, 100 * 1e6);
    //     IIVXPortfolio portfolio = RiskEngine.userIVXPortfolio(buyer);
    //     console.log("user effective margin", RiskEngine.getEffectiveMargin(portfolio));

    //     separate();
    //     console.log("Open Trade");
    //     // console.log("option id 3");
    //     // console.logBool(optionToken.getOptionIDAttributes(3).isBuy);
    //     // console.logBool(optionToken.getOptionIDAttributes(3).isCall);
    //     // console.log("option id 8");
    //     // console.logBool(optionToken.getOptionIDAttributes(8).isBuy);
    //     // console.logBool(optionToken.getOptionIDAttributes(8).isCall);

    //     vm.prank(buyer);
    //     diem.openTrades(trades);

    //     uint256 hf1 = diem.calculateHealthFactor(portfolio);
    //     console.log("hf1", hf1);

    //     console.log("net value");
    //     console.logInt(diem.calculatePortfolioNetValue(portfolio));

    //     separate();
    //     console.log("price goes 1000$");

    //     //make price go to strikeLong
    //     mockupAssetAggregatorV3.setPrice(1000 ether);
    //     vm.warp(block.timestamp + 1 hours);

    //     console.log("net value");
    //     console.logInt(diem.calculatePortfolioNetValue(portfolio));

    //     uint256 hf2 = diem.calculateHealthFactor(portfolio);
    //     console.log("hf2", hf2);

    //     separate();

    //     // console.log("liquidate trade");
    //     // vm.prank(BOB);
    //     // diem.liquidate(buyer);

    //     // uint256 hf3 = diem.calculateHealthFactor(portfolio);
    //     // console.log("hf3", hf3);
    //     // // assertTrue(hf3 < hf2, "closing a trade never makes you increase health factor");

    //     console.log("net value");
    //     console.logInt(diem.calculatePortfolioNetValue(portfolio));
    // }
}
