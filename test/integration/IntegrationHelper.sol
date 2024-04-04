pragma solidity ^0.8.18;

//HELPERS
import "forge-std/Test.sol";
import {Helper} from "../helpers/Helper.sol";

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
import {MockupAggregatorV3} from "../mocks/MockupAggregatorV3.sol";

contract IntegrationHelper is Helper {
    ///@dev arbitrum mainnet configurations
    address public weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public bitcoin = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address public DOGECOIN; //mockup token for testing
    address public DogecoinPriceFeed;
    address user = ALICE;

    /// @notice add margin WETH
    function addMarginWETH(uint256 _amount, address _user) public {
        deal(weth, _user, _amount);
        vm.startPrank(_user);
        IIVXPortfolio margin = RiskEngine.userIVXPortfolio(_user);

        IERC20(weth).approve(address(margin), _amount);
        margin.increaseMargin(weth, _amount);
        // uint256 weth_marginBalance = margin.userMarginBalance(weth);
        // console.log("weth_marginBalance", weth_marginBalance);
        vm.stopPrank();
    }

    /// @notice add margin USDC
    /// @param _amount amount of USDC to add
    function addMarginUSDC(uint256 _amount, address _user) public {
        deal(usdc, _user, _amount);

        vm.startPrank(_user);
        IIVXPortfolio margin = RiskEngine.userIVXPortfolio(_user);
        IERC20(usdc).approve(address(margin), _amount);
        margin.increaseMargin(usdc, _amount);
        // uint256 usdc_marginBalance = margin.userMarginBalance(usdc);
        // console.log("usdc_marginBalance", usdc_marginBalance);
        vm.stopPrank();
    }

    function createOption(address asset, uint256 strike, uint256 expiry) public returns (uint256 counterId) {
        optionToken.setUnderlyingMakerTakerFactors(asset, IIVXDiemToken.MAKER_TAKER_FACTORS({
                    VEGA_MAKER_FACTOR: 0.001 ether,
                    VEGA_TAKER_FACTOR: 0.002 ether,
                    DELTA_MAKER_FACTOR: 0.001 ether,
                    DELTA_TAKER_FACTOR: 0.002 ether
                }));
        RiskEngine.addAsset(
            asset,
            IIVXRiskEngine.AssetAttributes({
                collateralFactor: 1000,
                marginFactors: IIVXRiskEngine.MarginFactors({
                    marginFactorA: 0.3 ether,
                    marginFactorB: 0.032 ether,
                    marginFactorC: 1.03 ether,
                    marginFactorD: 0.002 ether,
                    marginFactorE: 1.03 ether
                }),
                shockLossFactors: IIVXRiskEngine.ShockLossFactors(0.3 ether, 0.2 ether)
            }), true
        );
        oracle.setStrikeVolatility(asset, strike, 0.6 ether);

        //log last option id
        uint256 initialCounterId = optionToken.currentOptionId();
        // console.log("last option id", counterId);

        //*Start create option
        IIVXDiemToken.Option memory options =
            IIVXDiemToken.Option({strikePrice: strike, expiry: expiry, underlyingAsset: asset});
        counterId = optionToken.createOption(options);
        //*End create option

        //log last option id
        // console.log("last option id", counterId);
        //asserts
        assertTrue(counterId > 0, "option id should be greater than 0");
        assertTrue(counterId == initialCounterId + 4);
    }

    function openTrades(uint256[] memory optionIds, uint256[] memory nContracts) public {
        IIVXDiem.TradeInfo[] memory trades = new IIVXDiem.TradeInfo[](optionIds.length);
        for (uint256 i = 0; i < optionIds.length; i++) {
            trades[i] = IIVXDiem.TradeInfo({optionID: optionIds[i], amountContracts: nContracts[i]});
        }
        diem.openTrades(trades);
    }

    function closeTrades(uint256[] memory optionIds, uint256[] memory nContracts) public {
        IIVXDiem.TradeInfo[] memory trades = new IIVXDiem.TradeInfo[](optionIds.length);
        for (uint256 i = 0; i < optionIds.length; i++) {
            trades[i] = IIVXDiem.TradeInfo({optionID: optionIds[i], amountContracts: nContracts[i]});
        }
        diem.closeTrades(trades);
    }

    /// @notice set up one trade to buy a call option, 5% above spot price
    /// @param margin add margin and deal amount in usdc
    /// @param _nContracts number of contracts to buy
    function setUpOneTrade_AddingMargin(uint256 margin, uint256 _nContracts, address _user, uint256 _optionId) public {
        // console.log("OPTION id", _optionId);
        addMarginUSDC(margin * 1e6, _user);
        uint256 balance_prev = RiskEngine.userIVXPortfolio(_user).userMarginBalance(usdc);
        // (, uint256 premia,,) = optionToken.calculateCosts(_optionId, _nContracts, false);
        // uint256 totalCost = _nContracts * premia / 1e18;
        // console.log("total cost", totalCost);
        // console.log("premium", premia);

        uint256[] memory optionIds = new uint[](1);
        optionIds[0] = _optionId;
        uint256[] memory nContracts = new uint256[](1);
        nContracts[0] = _nContracts;

        vm.startPrank(_user);
        openTrades(optionIds, nContracts);
        vm.stopPrank();

        uint256 marginBalance = RiskEngine.userIVXPortfolio(_user).userMarginBalance(usdc);
        // console.log("margin balance", marginBalance);
        assertTrue(marginBalance <= balance_prev);
    }

    function setUpOneTrade(uint256 _nContracts, address _user, uint256 _optionId) public {
        // console.log("OPTION id", _optionId);

        uint256[] memory optionIds = new uint[](1);
        optionIds[0] = _optionId;
        uint256[] memory nContracts = new uint256[](1);
        nContracts[0] = _nContracts;

        vm.startPrank(_user);
        openTrades(optionIds, nContracts);
        vm.stopPrank();
    }

    function closeOneTrade(uint256 _nContracts, address _user, uint256 _optionId) public {
        // console.log("OPTION id", _optionId);

        uint256[] memory optionIds = new uint[](1);
        optionIds[0] = _optionId;
        uint256[] memory nContracts = new uint256[](1);
        nContracts[0] = _nContracts;

        vm.startPrank(_user);
        closeTrades(optionIds, nContracts);
        vm.stopPrank();
    }

    /// @notice Deposit liquidity to the pool, 100k USDC
    function setUpLiquidity_Depositors() public {
        uint32 epochId = queue.currentEpochId();

        //deposit 10k usdc to ALICE
        uint256 amount = 10000 * 1e6;
        deal(usdc, ALICE, amount);
        Deposit(epochId, amount, ALICE);

        //deposit 20k usdc to BOB
        deal(usdc, BOB, amount * 2);
        Deposit(epochId, amount * 2, BOB);

        //deposit 30k usdc to CHAD
        deal(usdc, CHAD, amount * 3);
        Deposit(epochId, amount * 3, CHAD);

        //deposit 40k usdc to DEGEN
        deal(usdc, DEGEN, amount * 4);
        Deposit(epochId, amount * 4, DEGEN);

        vm.warp(block.timestamp + queue.epochDuration() + 1);
        //total liquidity 100k usdc
        queue.processCurrentQueue();
    }
}
