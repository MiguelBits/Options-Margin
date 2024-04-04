pragma solidity ^0.8.0;

import "forge-std/Test.sol";

//PROTOCOL CONTRACTS
import {IVXLP} from "../../src/liquidity/IVXLP.sol";
import {IVXQueue} from "../../src/liquidity/IVXQueue.sol";
import {IVXOracle} from "../../src/periphery/IVXOracle.sol";
// import {IVXMarginM} from "../../src/options/IVXMargin.sol";
import {IVXDiem} from "../../src/options/IVXDiem.sol";
import {IVXRiskEngine} from "../../src/margin/IVXRiskEngine.sol";
import {IVXPortfolio} from "../../src/margin/IVXPortfolio.sol";
import {IVXDiemToken} from "../../src/options/IVXDiemToken.sol";
import {IVXExchange} from "../../src/exchange/IVXExchange.sol";

//INTERFACES
import {IIVXOracle, IAggregatorV3} from "../../src/interface/periphery/IIVXOracle.sol";
import {IIVXLP} from "../../src/interface/liquidity/IIVXLP.sol";
import {IIVXRiskEngine} from "../../src/interface/margin/IIVXRiskEngine.sol";
import {IIVXPortfolio} from "../../src/interface/margin/IIVXPortfolio.sol";
import {IIVXDiem} from "../../src/interface/options/IIVXDiem.sol";
import {IIVXDiemToken} from "../../src/interface/options/IIVXDiemToken.sol";
import {IIVXExchange} from "../../src/interface/exchange/IIVXExchange.sol";
//UTILS
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {WETH} from "@solmate/tokens/WETH.sol";
import {MockupERC20} from "../mocks/MockupERC20.sol";
import {MockupAggregatorV3} from "../mocks/MockupAggregatorV3.sol";
import {MockupSequencerV3} from "../mocks/MockupSequencerV3.sol";
import {MockupHedger} from "../mocks/MockupHedger.sol";

contract Helper is Test {
    //USERS ADDRESSES
    address WHALE = 0xf89d7b9c864f589bbF53a82105107622B35EaA40; //bybit hot wallet
    address ALICE = address(1);
    address BOB = address(2);
    address CHAD = address(3);
    address DEGEN = address(4);
    address TREASURY = address(5);
    address STAKER = address(6);
    address trader = 0x82616812FE8f2985316688d1f0f0cC2C87a27b68;
        
    //Oracles
    IAggregatorV3 wethOracle = IAggregatorV3(0x62CAe0FA2da220f43a51F86Db2EDb36DcA9A5A08); //arbitrum goerli
    IAggregatorV3 usdcOracle = IAggregatorV3(0x1692Bdd32F31b831caAc1b0c9fAF68613682813b); //arbitrum goerli
    IAggregatorV3 btcOracle = IAggregatorV3(0x6550bc2301936011c1334555e62A87705A81C12C); //arbitrum goerli

    //CONFIG VARIABLES
    address uniswapV3 = 0xE592427A0AEce92De3Edee1F18E0157C05861564; //arbitrum
    address quoteUniswapV3 = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6; //arbitrum
    //gmx
    address positionRouter = 0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868; //arbitrum
    address router = 0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064; //arbitrum

    address collateral = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; //arbitrum usdc.e
    uint256 dollar = 1e6;
    uint256 mintAmount = 10000 ether;
    uint256 vaultMaximumCapacity = 100000 * dollar; //100k dollars

    //MOCKUPS
    MockupERC20 mockupERC20;
    MockupERC20 mockupWETH;
    MockupAggregatorV3 mockupAssetAggregatorV3;
    MockupAggregatorV3 mockupDollarAggregatorV3;
    MockupSequencerV3 mockupSequencer;

    //PROTOCOL CONTRACTS
    ERC20 collateralToken = ERC20(address(69));
    IVXLP lp = IVXLP(address(69));
    IVXQueue queue = IVXQueue(address(69));
    IVXOracle oracle = IVXOracle(address(69));
    IVXDiem diem = IVXDiem(address(69));
    IVXRiskEngine RiskEngine = IVXRiskEngine(address(69));
    IVXDiemToken optionToken = IVXDiemToken(address(69));
    IVXExchange exchange = IVXExchange(address(69));

    function ForkEnvironment() public {
        vm.createSelectFork(vm.envString("ARB_URL"), 125846745);
    }

    ///@dev always use fork environment when testing exchange
    function deployExchange() public {
        exchange = new IVXExchange();
        exchange.setUniswapV3(uniswapV3, quoteUniswapV3);
        exchange.setGMXContracts(router, positionRouter);

        console.log("exchange", address(exchange));
    }

    function deployMockup() public returns (address _token, address _oracle) {
        MockupERC20 _mockup = new MockupERC20("DOGE",18);
        MockupAggregatorV3 _aggregator = new MockupAggregatorV3(
            18, //decimals
            "DOGE", //description
            1, //version
            0, //roundId
            1 ether, //answer
            0, //startedAt
            0, //updatedAt
            0 //answeredInRound
        );
        _token = address(_mockup);
        console.log("token mock address: ", _token);
        _oracle = address(_aggregator);
        console.log("oracle mock address: ", _oracle);

        oracle.addAssetPriceFeed(_token, _oracle);
    }

    function deployMockTokens() public {
        //mockup for erc20 as dollar stable
        mockupERC20 = new MockupERC20("Dollar",6);
        console.log("mockupERC20 usdc address", address(mockupERC20));
        //mockup for weth
        mockupWETH = new MockupERC20("Eth",18);
        console.log("mockupWETH address", address(mockupWETH));

        mockupWETH.mint(WHALE, mintAmount);
        mockupWETH.mint(ALICE, mintAmount);
        mockupWETH.mint(BOB, mintAmount);
        mockupWETH.mint(CHAD, mintAmount);
        mockupWETH.mint(DEGEN, mintAmount);
    }

    function deployMockTokenOracle(string memory _name, uint8 _decimals, int256 _priceAnswer)
        public
        returns (address token, address __oracle)
    {
        //mockup for erc20
        MockupERC20 _token = new MockupERC20(_name,_decimals);
        //mockup for oracle
        MockupAggregatorV3 _oracle = new MockupAggregatorV3(
            _decimals, //decimals
            _name, //description
            1, //version
            0, //roundId
            _priceAnswer, //answer
            0, //startedAt
            0, //updatedAt
            0 //answeredInRound
        );

        //Minting tokens
        _token.mint(WHALE, mintAmount);
        _token.mint(ALICE, mintAmount);
        _token.mint(BOB, mintAmount);
        _token.mint(CHAD, mintAmount);
        _token.mint(DEGEN, mintAmount);

        return (address(_oracle), address(_token));
    }

    function deployTestLP() public {
        deployMockTokens();

        lp = new IVXLP(
            vaultMaximumCapacity, 
            ERC20(mockupERC20)
            );

        lp.setInterestRateParams(
            IIVXLP.InterestRateParams({
                MaxRate: 0.5 ether,
                InflectionRate: 0.2 ether,
                MinRate: 0.05 ether,
                InflectionUtilization: 0.8 ether,
                MaxUtilization: 0.92 ether
            })
        );

        queue = new IVXQueue(lp, uint32(block.timestamp + 1 days));

        lp.setIVXContract(address(queue), address(diem), address(oracle), address(RiskEngine));

        //Minting tokens
        mockupERC20.mint(WHALE, mintAmount);
        mockupERC20.mint(ALICE, mintAmount);
        mockupERC20.mint(BOB, mintAmount);
        mockupERC20.mint(CHAD, mintAmount);
        mockupERC20.mint(DEGEN, mintAmount);

        collateralToken = ERC20(mockupERC20);

        MockupHedger hedge = new MockupHedger();
        lp.setHedger(address(hedge));
    }

    function deployRealLP() public {
        lp = new IVXLP(
            vaultMaximumCapacity, 
            ERC20(collateral)
            );
        console.log("lp address", address(lp));

        lp.setInterestRateParams(
            IIVXLP.InterestRateParams({
                MaxRate: 0.5 ether,
                InflectionRate: 0.2 ether,
                MinRate: 0.05 ether,
                InflectionUtilization: 0.8 ether,
                MaxUtilization: 0.92 ether
            })
        );

        queue = new IVXQueue(lp, uint32(block.timestamp + 1 days));
        console.log("queue address", address(queue));

        collateralToken = ERC20(collateral);
        console.log("collateral address", address(collateralToken));

        MockupHedger hedge = new MockupHedger();
        lp.setHedger(address(hedge));
    }

    function deployMockToken(string memory _name, uint8 _decimals, int256 _price) public returns (address token) {
        //mockup for erc20
        MockupERC20 _token = new MockupERC20(_name,_decimals);

        //Minting tokens
        _token.mint(WHALE, mintAmount);
        _token.mint(ALICE, mintAmount);
        _token.mint(BOB, mintAmount);
        _token.mint(CHAD, mintAmount);
        _token.mint(DEGEN, mintAmount);

        //deploy mockupAggregator for that asset
        MockupAggregatorV3 _oracle = new MockupAggregatorV3(
            _decimals, //decimals
            _name, //description
            1, //version
            0, //roundId
            _price, //answer
            0, //startedAt
            0, //updatedAt
            0 //answeredInRound
        );

        //add to asset price feed
        oracle.addAssetPriceFeed(address(_token), address(_oracle));

        return address(_token);
    }

    function deployTestOracle() public {
        deployMockTokens();

        //mockup for layer2 sequencer
        mockupSequencer = new MockupSequencerV3(
            0, //roundId
            0, //answer needs to be 0
            0, //startedAt needs to fulfill (block.timestamp - startedAt) > 3600
            0, //updatedAt
            0  //answeredInRound
        );

        oracle = new IVXOracle(address(0)); //sequencer address 0 for now
        console.log("oracle address", address(oracle));

        //mockup for price feed of eth
        mockupAssetAggregatorV3 = new MockupAggregatorV3(
            18, //decimals
            "Ethereum", //description
            1, //version
            0, //roundId
            1500 ether, //answer
            0, //startedAt
            0, //updatedAt
            0 //answeredInRound
        );
        console.log("mockupAssetAggregatorV3 weth address", address(mockupAssetAggregatorV3));

        mockupDollarAggregatorV3 = new MockupAggregatorV3(
            6, //decimals
            "USD", //description
            1, //version
            0, //roundId
            int(1 * dollar), //answer
            0, //startedAt
            0, //updatedAt
            0 //answeredInRound
        );
        console.log("mockupDollarAggregatorV3 usdc address", address(mockupDollarAggregatorV3));

        //add price feed for mockup eth
        oracle.addAssetPriceFeed(address(mockupWETH), address(mockupAssetAggregatorV3));
        //add price feed for mockup dollar
        oracle.addAssetPriceFeed(address(mockupERC20), address(mockupDollarAggregatorV3));
    }

    function deployRealOracle() public {
        ForkEnvironment();
        oracle = new IVXOracle(0xFdB631F5EE196F0ed6FAa767959853A9F217697D); //arbitrum sequencer
        address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        address weth_feed = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        address usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        address usdc_feed = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        address bitcoin = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
        address bitcoin_feed = 0x6ce185860a4963106506C203335A2910413708e9;
        address link = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;
        address link_feed = 0x86E53CF1B870786351Da77A57575e79CB55812CB;

        console.log("oracle address", address(oracle));

        oracle.addAssetPriceFeed(weth, weth_feed);
        oracle.addAssetPriceFeed(usdc, usdc_feed);
        oracle.addAssetPriceFeed(bitcoin, bitcoin_feed);
        oracle.addAssetPriceFeed(link, link_feed);
    }

    /// @notice do after deployTestOracle()
    function setMocksOracle(address _oracle, address _token) public {
        oracle.addAssetPriceFeed(_token, _oracle);
    }

    function deployRiskEngine() public {
        RiskEngine = new IVXRiskEngine();
        console.log("RiskEngine address", address(RiskEngine));
    }

    /// @notice deploys all contracts needed for mainnet
    /// assigns weth to addresses, Oracle, LP, Queue, LP.setQueue(), Diem (with Portfolio inside), LP.setDiem(), Margin, Diem.initalizer(Margin)
    /// in this order
    function deployRealDiem() public {
        deployRealOracle();
        deployRealLP();
        deployExchange();

        diem = new IVXDiem(
            IIVXLP(address(lp)),
            TREASURY,
            STAKER,
            IIVXDiem.FeeDistribution({
                treasuryFee: 0.6 ether,
                stakerFee: 0.3 ether,
                lpFee: 0.1 ether
            })
        );
        console.log("diem address", address(diem));

        RiskEngine = new IVXRiskEngine();

        console.log("margin address", address(RiskEngine));

        optionToken = new IVXDiemToken(
        );
        optionToken.initialize(address(RiskEngine), address(lp), address(oracle), address(diem));
        console.log("optionToken address", address(optionToken));

        diem.initialize(
            IIVXRiskEngine(address(RiskEngine)), IIVXDiemToken(address(optionToken)), address(exchange), address(oracle)
        );

        lp.setIVXContract(address(queue), address(diem), address(oracle), address(RiskEngine));

        RiskEngine.initialize(address(diem), address(lp), address(optionToken), address(exchange), address(oracle));
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
        RiskEngine.addAsset(collateral, attributes, true); //100%
    }

    /// @notice deploys all contracts needed for testing
    /// Mockup tokens, Oracle, LP, Queue, LP.setQueue(), Diem (with Portfolio inside), LP.setDiem(), Margin, Diem.initalizer(Margin)
    /// in this order
    function deployTestDiem() public {
        deployTestDiem(1 days);
    }

    function deployTestDiem(uint256 queueTime) public {
        deployTestOracle();

        mockupERC20.mint(WHALE, mintAmount);
        mockupERC20.mint(ALICE, mintAmount);
        mockupERC20.mint(BOB, mintAmount);
        mockupERC20.mint(CHAD, mintAmount);
        mockupERC20.mint(DEGEN, mintAmount);

        lp = new IVXLP(
            vaultMaximumCapacity, 
            ERC20(mockupERC20)
            );

        collateralToken = lp.collateral();

        MockupHedger hedge = new MockupHedger();
        lp.setHedger(address(hedge));

        console.log("lp address", address(lp));

        queue = new IVXQueue(lp, uint32(block.timestamp + queueTime));
        console.log("queue address", address(queue));

        lp.setInterestRateParams(
            IIVXLP.InterestRateParams({
                MaxRate: 0.5 ether,
                InflectionRate: 0.2 ether,
                MinRate: 0.05 ether,
                InflectionUtilization: 0.8 ether,
                MaxUtilization: 0.92 ether
            })
        );

        diem = new IVXDiem(
            IIVXLP(address(lp)),
            TREASURY,
            STAKER,
            IIVXDiem.FeeDistribution({
                treasuryFee: 0.6 ether,
                stakerFee: 0.3 ether,
                lpFee: 0.1 ether
            })
        );

        exchange = new IVXExchange();

        RiskEngine = new IVXRiskEngine();
        console.log("RiskEngine address", address(RiskEngine));

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

        optionToken = new IVXDiemToken();
        optionToken.initialize(address(RiskEngine), address(lp), address(oracle), address(diem));

        console.log("option token", address(optionToken));
        RiskEngine.initialize(address(diem), address(lp), address(optionToken), address(exchange), address(oracle));
        RiskEngine.addAsset(address(mockupERC20), attributes, true); //100%

        diem.initialize(
            IIVXRiskEngine(address(RiskEngine)), IIVXDiemToken(address(optionToken)), address(exchange), address(oracle)
        );
        console.log("diem address", address(diem));

        lp.setIVXContract(address(queue), address(diem), address(oracle), address(RiskEngine));

        //Minting tokens
        mockupERC20.mint(address(lp), 10000 * dollar);
        // uint256 balanceLP = mockupERC20.balanceOf(address(lp));
        // console.log("balanceLP", balanceLP);

        oracle.setGMXSpotSlippage(address(mockupWETH), 0.03 ether);
        optionToken.setParams(IIVXDiemToken.OptionTradingParams(0.05 ether, 3600, 1 days, 4 days, 0.01 ether)); //binomial: 1 day, blackScholes: 4 days
    }

    function Deposit(uint32 _epochId, uint256 _amount, address _user) public {
        // console.log(">>> Depositing", _epochId, _amount, _user);

        //get previous balances
        uint256 prev_collateralBalance = collateralToken.balanceOf(_user);
        // console.log("prev_collateralBalance", prev_collateralBalance);
        uint256 prev_queueLength = queue.depositEpochQueueLength(_epochId);
        // console.log("prev_queueLength", prev_queueLength);
        uint256 prev_queueUser = queue.depositUserQueue(_epochId, _user);
        // console.log("prev_queueUser", prev_queueUser);

        vm.startPrank(_user);
        collateralToken.approve(address(queue), _amount);
        queue.addLiquidity(_epochId, _amount);
        vm.stopPrank();

        //get post balances
        uint256 post_collateralBalance = collateralToken.balanceOf(_user);
        // console.log("post_collateralBalance", post_collateralBalance);
        uint256 post_queueLength = queue.depositEpochQueueLength(_epochId);
        // console.log("post_queueLength", post_queueLength);
        uint256 post_queueUser = queue.depositUserQueue(_epochId, _user);
        // console.log("post_queueUser", post_queueUser);

        //check if balances are correct
        assertTrue(post_collateralBalance == prev_collateralBalance - _amount, "Collateral amount is not correct");
        //check if deposit epoch queue length incremented
        assertTrue(post_queueLength == prev_queueLength + 1, "Deposit epoch queue length is not correct");
        //check if deposit epoch queue user amounts incremented
        assertTrue(post_queueUser == prev_queueUser + _amount, "Deposit epoch queue user amount is not correct");
        //check last index of deposit epoch queue is user
        assertTrue(
            queue.depositEpochQueue(_epochId, post_queueLength - 1) == _user,
            "Deposit epoch queue last index is not correct"
        );
        //check last index of deposit queue amounts is amount
        assertTrue(
            queue.depositEpochQueueAmounts(_epochId, post_queueLength - 1) == _amount,
            "Deposit epoch queue last index amount is not correct"
        );

        // console.log("Deposit queue state", collateralToken.balanceOf(address(queue)), post_queueLength);
    }

    function ReduceDeposit(uint32 _epochId, uint256 _amount, address _user) public {
        // console.log(">>> Reducing deposit", _epochId, _amount, _user);

        uint256 prev_collateralBalance = collateralToken.balanceOf(_user);

        vm.startPrank(_user);
        queue.reduceQueuedDeposit(_epochId, _amount);
        vm.stopPrank();

        uint256 post_collateralBalance = collateralToken.balanceOf(_user);
        assertTrue(post_collateralBalance > prev_collateralBalance);

        // uint256 newUserAmount = queue.depositUserQueue(_epochId, _user);
        // console.log("Deposit queue state", collateralToken.balanceOf(address(queue)), "user new amount" ,newUserAmount);
    }

    function DepositHelper(uint32 _epochId) public {
        vm.startPrank(ALICE);
        collateralToken.approve(address(queue), 50 * dollar);
        queue.addLiquidity(_epochId, 50 * dollar);
        vm.stopPrank();

        vm.startPrank(BOB);
        collateralToken.approve(address(queue), 100 * dollar);
        queue.addLiquidity(_epochId, 100 * dollar);
        vm.stopPrank();

        vm.startPrank(CHAD);
        collateralToken.approve(address(queue), 150 * dollar);
        queue.addLiquidity(_epochId, 150 * dollar);
        vm.stopPrank();

        vm.startPrank(DEGEN);
        collateralToken.approve(address(queue), 200 * dollar);
        queue.addLiquidity(_epochId, 200 * dollar);
        vm.stopPrank();

        //TOTAL DEPOSITED: 500
    }

    //@notice deposits first epoch, processes, withdraws on second epoch amounts of first epoch
    function WithdrawHelperFull() public {
        console.log("NAV", lp.NAV());
        uint32 epochId = queue.currentEpochId(); //first epoch
        DepositHelper(epochId); //first epoch
        //warp to epoch start
        (uint32 start,,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue();

        console.log("NAV", lp.NAV());

        epochId = queue.currentEpochId(); //second epoch
        Withdraw(epochId, 50 * dollar, ALICE);
        Withdraw(epochId, 100 * dollar, BOB);
        Withdraw(epochId, 150 * dollar, CHAD);
        Withdraw(epochId, 200 * dollar, DEGEN);

        //warp to epoch start of second epoch
        (start,,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue();

        console.log("NAV", lp.NAV());

        epochId = queue.currentEpochId();
        (start,,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue();

        console.log("NAV", lp.NAV());
    }

    //@notice deposits first epoch, processes, withdraws on second epoch amounts of first epoch
    function WithdrawHelper() public {
        uint32 epochId = queue.currentEpochId(); //first epoch
        DepositHelper(epochId); //first epoch
        //warp to epoch start
        (uint32 start,,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue();

        epochId = queue.currentEpochId(); //second epoch
        DepositHelper(epochId); //second epoch
        //@notice ALICE = 100, BOB = 200, CHAD = 300, DEGEN = 400
        Withdraw(epochId, 100 * dollar, ALICE);
        Withdraw(epochId, 200 * dollar, BOB);
        Withdraw(epochId, 300 * dollar, CHAD);
        Withdraw(epochId, 400 * dollar, DEGEN);

        //warp to epoch start of second epoch
        (start,,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue();
    }

    function Withdraw(uint32 _epochId, uint256 _amount, address _user) public {
        // console.log(">>> Withdrawing", _epochId, _amount, _user);

        uint256 prev_lpUserBalance = lp.balanceOf(_user);
        uint256 prev_lpQueueBalance = lp.balanceOf(address(queue));

        vm.startPrank(_user);
        lp.approve(address(queue), _amount);
        queue.removeLiquidity(_epochId, _amount);
        vm.stopPrank();

        uint256 post_lpUserBalance = lp.balanceOf(_user);
        uint256 post_lpQueueBalance = lp.balanceOf(address(queue));

        assertTrue(post_lpUserBalance < prev_lpUserBalance);
        assertTrue(post_lpQueueBalance > prev_lpQueueBalance);

        // console.log("Withdraw queue state", lp.balanceOf(address(queue)), queue.withdrawEpochQueueLength(_epochId));
    }

    function createOption(uint256 strikePrice, uint256 expiry, address asset)
        public
        returns (IIVXDiemToken.OptionAttributes memory p)
    {
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
        oracle.setValues(asset, IIVXOracle.EncodedData({beta: 1 ether, alpha: 30000000000000000}));
        //set vol
        oracle.setStrikeVolatility(asset, strikePrice, 0.6 ether);
        oracle.setRiskFreeRate(asset, 0.5 ether);
        IIVXDiemToken.Option memory optionAttributes =
            IIVXDiemToken.Option({strikePrice: strikePrice, expiry: expiry, underlyingAsset: asset});

        uint256 counterId = optionToken.createOption(optionAttributes);
        p = optionToken.getOptionIDAttributes(counterId);
    }

    function createOption(uint256 strikePrice, uint256 expiry, address asset, bool _newAsset)
        public
        returns (IIVXDiemToken.OptionAttributes memory p)
    {
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
            }), _newAsset
        );
        
        oracle.setValues(asset, IIVXOracle.EncodedData({beta: 1 ether, alpha: 30000000000000000}));
        //set vol
        oracle.setStrikeVolatility(asset, strikePrice, 0.6 ether);
        oracle.setRiskFreeRate(asset, 0.5 ether);
        IIVXDiemToken.Option memory optionAttributes =
            IIVXDiemToken.Option({strikePrice: strikePrice, expiry: expiry, underlyingAsset: asset});

        uint256 counterId = optionToken.createOption(optionAttributes);
        p = optionToken.getOptionIDAttributes(counterId);
    }

    function newMarginAccountFund(address _user, address _asset, uint256 _amount) public returns (IIVXPortfolio _new) {
        vm.startPrank(_user);
        _new = RiskEngine.createMarginAccount();
        ERC20(_asset).approve(address(_new), _amount);
        addMargin(_new, _asset, _amount);
        vm.stopPrank();
    }

    function addMargin(IIVXPortfolio _account, address _asset, uint256 _amount) public {
        _account.increaseMargin(_asset, _amount);
    }

    function createOptionScript() public{
        optionToken.setParams(IIVXDiemToken.OptionTradingParams(0.05 ether, 3600, 1 days, 4 days, 0.01 ether)); //binomial: 1 day, blackScholes: 4 days

        MockupERC20 mockupBTC = new MockupERC20("BTC", 8);

        oracle.addAssetPriceFeed(address(mockupBTC), address(btcOracle));

        console.log("Btc asset", address(mockupBTC));
        
        uint256 _amount = 10000 * 1e6;
        mockupERC20.mint(address(lp), 20000 * 1e6);
        mockupERC20.mint(trader, _amount);
        console.log("Trader: %s", trader);

        console.log("create option id 1-4: 1550 usdc, 7 days, weth");
        createOption(1550 ether, block.timestamp + 7 days, address(mockupWETH), true); //1-4
        console.log("create option id 5-8: 2600 usdc, 7 days, btc");
        createOption(2600 ether, block.timestamp + 7 days, address(mockupBTC), true);  //5-8
        console.log("create option id 9-12: 1515 usdc, 15 days, weth");
        createOption(1515 ether, block.timestamp + 15 days, address(mockupWETH), false); //9-12
        console.log("create option id 13-16: 2515 usdc, 15 days, btc");
        createOption(2515 ether, block.timestamp + 15 days, address(mockupBTC), false);  //13-16

        IIVXPortfolio _new = RiskEngine.createMarginAccount();
        mockupERC20.approve(address(_new), _amount);
        addMargin(_new, address(mockupERC20), _amount);

    }

    function createTrade(address user, uint256[] memory _ids, uint256[] memory _contracts) public {

    }
}
