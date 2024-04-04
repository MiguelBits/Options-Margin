// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

//HELPER
import {Helper, MockupERC20, MockupAggregatorV3} from "../../helpers/Helper.sol";
import "forge-std/Test.sol";

//PROTOCOL CONTRACTS
import {IVXLP} from "../../../src/liquidity/IVXLP.sol";
import {IVXQueue} from "../../../src/liquidity/IVXQueue.sol";
import {IIVXQueue} from "../../../src/interface/liquidity/IIVXQueue.sol";

contract LPTest is Helper {
    function setUp() public {
        deployTestDiem();
        //burn collateral tokens that were minted for diem to have liq to withdraw from
        mockupERC20.burn(address(lp), 10000 * dollar);
        assertTrue(lp.NAV() == 0, "assert we start with empty lp");
    }

    function test_Deposit() public {
        console.log(">>> Testing Deposit");
        uint32 epochId = 1;

        //ALICE DEPOSIT 100 DOLLARS
        uint256 amount = 100 * dollar;
        address user = ALICE;

        //Deposit
        Deposit(epochId, amount, user);
        console.log("Alice queue deposit", queue.depositUserQueue(epochId, user));

        //BOB DEPOSIT 200 DOLLARS
        user = BOB;
        amount = 200 * dollar;

        //Deposit
        Deposit(epochId, amount, user);
        console.log("Bob queue deposit", queue.depositUserQueue(epochId, user));

        //Consecutive Alice deposit
        //ALICE DEPOSIT 300 DOLLARS
        user = ALICE;
        amount = 300 * dollar;

        //Deposit
        Deposit(epochId, amount, user);
        console.log("Alice queue deposit", queue.depositUserQueue(epochId, user));

        //Chad deposit 300 dollars + 50 dollars, consecutive deposit
        user = CHAD;
        amount = 300 * dollar;
        Deposit(epochId, amount, user);
        amount = 50 * dollar;
        Deposit(epochId, amount, user);
        console.log("Chad queue deposit", queue.depositUserQueue(epochId, user));

        //Degen deposit 100 dollars
        user = DEGEN;
        amount = 100 * dollar;
        Deposit(epochId, amount, user);

        //Degen deposit another 100 dollars
        Deposit(epochId, amount, user);

        //TOTAL DEPOSIT OF 1050 DOLLARS
        console.log(">>> Testing Deposit Finished");
    }

    function test_DepositAfterStart() public {
        uint32 _epochId = 1;
        (uint32 start,,,) = queue.epochData(_epochId);
        vm.warp(start + 1);

        vm.startPrank(ALICE);
        collateralToken.approve(address(queue), 100);
        vm.expectRevert(abi.encodeWithSelector(IIVXQueue.CannotDeposit.selector, _epochId, start));
        queue.addLiquidity(_epochId, 100);
        vm.stopPrank();
    }

    function test_FuzzDeposit(uint256 _amount, address _user) public {
        vm.assume(_amount < lp.vaultMaximumCapacity() && _amount > 0);
        mockupERC20.mint(_user, _amount);
        Deposit(1, _amount, _user);
    }

    function test_ReduceDeposit() public {
        uint32 epochId = 1;

        //Deposit Alice 100 dollars, index 0
        uint256 amountAlice = 100 * dollar;
        address user = ALICE;
        Deposit(epochId, amountAlice, user);

        //Deposit Bob 200 dollars, index 1
        uint256 amountBob = 200 * dollar;
        user = BOB;
        Deposit(epochId, amountBob, user);
        //TOTAL IN QUEUE = 300
        assertTrue(collateralToken.balanceOf(address(queue)) == 300 * dollar);

        //Reduce Alice deposit by 100 dollars, left 0
        user = ALICE;
        ReduceDeposit(epochId, amountAlice, user);
        uint256 index = 0;
        uint256 arrayAmount = queue.depositEpochQueueAmounts(epochId, index);
        assertTrue(arrayAmount == 0);
        //TOTAL IN QUEUE = 200
        assertTrue(collateralToken.balanceOf(address(queue)) == 200 * dollar);

        //Reduce Bob deposit 100, left 100
        user = BOB;
        ReduceDeposit(epochId, 100 * dollar, user);
        index = 1;
        arrayAmount = queue.depositEpochQueueAmounts(epochId, index);
        assertTrue(arrayAmount == 100 * dollar);
        //TOTAL IN QUEUE = 100
        assertTrue(collateralToken.balanceOf(address(queue)) == 100 * dollar);

        //Consecutive Chad deposit
        //Deposit Chad 300 dollars TOTAL IN QUEUE = 400
        uint256 amountChad1 = 300 * dollar;
        user = CHAD;
        Deposit(epochId, amountChad1, user);
        // //Deposit Chad 100 dollars TOTAL IN QUEUE = 500
        uint256 amountChad2 = 100 * dollar;
        Deposit(epochId, amountChad2, user);

        //Total Chad deposit 400 dollars
        //Reduce Chad deposit by 200 so it reduces on the two deposits of the queue
        ReduceDeposit(epochId, 200 * dollar, user); //TOTAL IN QUEUE = 300
        index = 2;
        arrayAmount = queue.depositEpochQueueAmounts(epochId, index);
        assertTrue(arrayAmount == 200 * dollar);
        index = 3;
        arrayAmount = queue.depositEpochQueueAmounts(epochId, index);
        assertTrue(arrayAmount == 0);

        assertTrue(collateralToken.balanceOf(address(queue)) == 300 * dollar);
    }

    function test_ProcessDeposit() public {
        uint32 epochId = 1;
        DepositHelper(epochId); //TOTAL IN QUEUE = 500

        //warp to epoch start
        (uint32 start, uint32 end,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processDepositQueue(epochId);

        //check collateral token balance is 500 in lp and 0 in queue
        console.log("Queue balance", collateralToken.balanceOf(address(queue)));
        assertTrue(collateralToken.balanceOf(address(queue)) == 0, "Queue balance not 0");
        console.log("LP balance", collateralToken.balanceOf(address(lp)));
        assertTrue(collateralToken.balanceOf(address(lp)) == 500 * dollar, "LP balance not 1000");
        console.log("NAV", lp.NAV());
        //check NAV is 500
        assertTrue(lp.NAV() == 500 * dollar, "NAV");
        //check all users got their share minted
        assertTrue(lp.balanceOf(ALICE) == 50 * dollar, "Alice balance");
        assertTrue(lp.balanceOf(BOB) == 100 * dollar, "Bob balance");
        assertTrue(lp.balanceOf(CHAD) == 150 * dollar, "Chad balance");
        assertTrue(lp.balanceOf(DEGEN) == 200 * dollar, "Degen balance");
        //check total supply is 500
        console.log("Total supply", lp.totalSupply());
        assertTrue(lp.totalSupply() == 500 * dollar, "Total supply");
        //TOTAL IN QUEUE = 0
        //check if epoch updated
        assertTrue(queue.currentEpochId() == 2, "Epoch count");
        assertTrue(queue.depositEpochQueueLength(2) == 0, "Epoch queue length");
        //check if epoch data updated
        (uint32 _start, uint32 _end,,) = queue.epochData(epochId + 1);
        assertTrue(_start == end, "Epoch start");
        assertTrue(_end == end + 1 days, "Epoch end");

        epochId = 2;
        DepositHelper(epochId); //TOTAL IN QUEUE = 500 + 500 = 1000

        //warp to epoch start
        (start,,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue();

        //check collateral token balance is 1000 in lp and 0 in queue
        console.log("Queue balance", collateralToken.balanceOf(address(queue)));
        assertTrue(collateralToken.balanceOf(address(queue)) == 0, "Queue balance not 0");
        console.log("LP balance", collateralToken.balanceOf(address(lp)));
        assertTrue(collateralToken.balanceOf(address(lp)) == 1000 * dollar, "LP balance not 1000");
        console.log("NAV", lp.NAV());
        //check NAV is 1000
        assertTrue(lp.NAV() == 1000 * dollar, "NAV");
        //check all users got their share minted
        assertTrue(lp.balanceOf(ALICE) == 100 * dollar, "Alice balance");
        assertTrue(lp.balanceOf(BOB) == 200 * dollar, "Bob balance");
        assertTrue(lp.balanceOf(CHAD) == 300 * dollar, "Chad balance");
        assertTrue(lp.balanceOf(DEGEN) == 400 * dollar, "Degen balance");
        //check total supply is 1000

        console.log("Total supply", lp.totalSupply());
        assertTrue(lp.totalSupply() == 1000 * dollar, "Total supply");
        //TOTAL IN QUEUE = 0
    }

    function test_WithdrawUsers() public {
        uint32 epochId = queue.currentEpochId(); //first epoch
        DepositHelper(epochId); //first epoch
        //warp to epoch start
        (uint32 start, uint32 end,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue();
        assertTrue(queue.currentEpochId() == 2, "Epoch count");
        //log NAV
        console.log("pre withdraw NAV ", lp.NAV());

        //@notice ALICE = 50, BOB = 100, CHAD = 150, DEGEN = 200
        address _user = ALICE; //remove 50
        uint256 _amount = 50 * dollar; //remove 50
        Withdraw(1, _amount, _user);
        assertTrue(lp.balanceOf(address(queue)) == 50 * dollar, "Queue balance has Alice");
        assertTrue(lp.balanceOf(_user) == 0, "Alice balance");
        uint256 prev_AliceCollateralAmount = collateralToken.balanceOf(_user);
        // console.log("Alice collateral amount", prev_AliceCollateralAmount);

        _user = BOB; //remove 50
        _amount = 50 * dollar; //remove 50
        Withdraw(epochId, _amount, _user);
        assertTrue(lp.balanceOf(address(queue)) == 100 * dollar, "Queue balance has Alice and Bob");
        assertTrue(lp.balanceOf(_user) == 50 * dollar, "Bob balance");
        uint256 prev_BobCollateralAmount = collateralToken.balanceOf(_user);
        // console.log("Bob collateral amount", prev_BobCollateralAmount);

        //warp time to end of 1st epoch so that withdraws can be processed
        vm.warp(end + 1);
        queue.processCurrentQueue();
        assertTrue(lp.balanceOf(address(queue)) == 0, "Queue balance is 0");

        console.log("Bob collateral rm", prev_BobCollateralAmount);
        //log NAV assert is 400
        console.log("NAV", lp.NAV());
        assertTrue(lp.NAV() == 400 * dollar, "NAV");
        console.log("bob collateralBal", collateralToken.balanceOf(BOB));
        console.log("post withdraw NAV", lp.NAV());
        //assert that Alice and Bob got their collateral back
        assertTrue(collateralToken.balanceOf(ALICE) == prev_AliceCollateralAmount + 50 * dollar, "Alice collateral");
        assertTrue(collateralToken.balanceOf(BOB) == prev_BobCollateralAmount + 50 * dollar, "Bob collateral");
    }

    function test_WithdrawAllUsers() public {
        WithdrawHelperFull();

        assertTrue(lp.NAV() == 0, "NAV should be 0");
    }

    function test_CantWithdraw() public {
        uint32 epochId = queue.currentEpochId(); //first epoch
        DepositHelper(epochId); //first epoch
        //warp to epoch start
        (uint32 start, uint32 end,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue();

        //@notice ALICE = 50, BOB = 100, CHAD = 150, DEGEN = 200
        address _user = ALICE; //remove 50
        uint256 _amount = 50 * dollar; //remove 50
        vm.startPrank(_user);
        lp.approve(address(queue), _amount);
        //warp to epoch end of second epoch for withdraw failure
        vm.warp(end + 1);
        //revert("Can't withdraw"); because epoch 1 is over end time
        vm.expectRevert(abi.encodeWithSelector(IIVXQueue.CannotWithdraw.selector, epochId, end));
        queue.removeLiquidity(epochId, _amount);
        vm.stopPrank();
    }

    function test_ReduceWithdraw() public {
        uint32 epochId = queue.currentEpochId(); //first epoch
        DepositHelper(epochId); //first epoch
        //warp to epoch start
        (uint32 start, uint32 end,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue();

        //withdraw 1st epoch
        //@notice ALICE = 50, BOB = 100, CHAD = 150, DEGEN = 200
        // console.log("NAV", lp.NAV());
        //NAV = 500

        //Remove Alice 50
        address _user = ALICE; //remove 50
        uint256 _amount = 50 * dollar; //remove 50
        vm.startPrank(_user);
        lp.approve(address(queue), _amount);
        queue.removeLiquidity(epochId, _amount);
        vm.stopPrank();
        uint256 prev_AliceLpBalance = lp.balanceOf(_user);
        //NAV = 450

        //Remove Bob 50
        _user = BOB; //remove 50
        _amount = 50 * dollar; //remove 50
        vm.startPrank(_user);
        lp.approve(address(queue), _amount);
        queue.removeLiquidity(epochId, _amount);
        vm.stopPrank();
        //NAV = 400

        //reduce withdraw of alice to 25
        _user = ALICE; //remove 25
        _amount = 25 * dollar; //remove 25
        vm.prank(_user);
        queue.reduceQueuedWithdrawal(epochId, _amount);
        assertTrue(lp.balanceOf(address(queue)) == 75 * dollar, "Queue balance has Alice and Bob");
        assertTrue(lp.balanceOf(_user) == prev_AliceLpBalance + 25 * dollar, "Alice balance");
        //NAV = 425

        //warp time to end of 1st epoch so that withdraws can be processed
        vm.warp(end + 1);
        queue.processCurrentQueue();
        console.log("NAV", lp.NAV());
        assertTrue(lp.NAV() == 425 * dollar, "NAV");
    }

    function test_SecondEpochEndToEnd() public {
        uint32 epochId = queue.currentEpochId(); //first epoch
        DepositHelper(epochId); //first epoch
        //warp to epoch start
        (uint32 start, uint32 end,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue();

        //withdraw 1st epoch
        //@notice ALICE = 50, BOB = 100, CHAD = 150, DEGEN = 200

        //Remove Alice 50
        address _user = ALICE; //remove 50
        uint256 _amount = 50 * dollar; //remove 50
        vm.startPrank(_user);
        lp.approve(address(queue), _amount);
        queue.removeLiquidity(epochId, _amount);
        vm.stopPrank();

        //Remove Bob 50
        _user = BOB; //remove 50
        _amount = 50 * dollar; //remove 50
        vm.startPrank(_user);
        lp.approve(address(queue), _amount);
        queue.removeLiquidity(epochId, _amount);
        vm.stopPrank();
        //HERE NAV = 400

        epochId = queue.currentEpochId(); //second epoch
        Deposit(epochId, 100 * dollar, CHAD);
        //HERE assets = 500

        epochId = queue.currentEpochId(); //second epoch
        Deposit(epochId, 200 * dollar, DEGEN);
        //HERE assets = 700

        //warp time to end of 1st epoch so that withdraws can be processed
        vm.warp(end + 1);
        queue.processCurrentQueue();
        console.log("NAV", lp.NAV());
        assertTrue(lp.NAV() == 700 * dollar, "NAV");
    }

    function test_QueueChangesNAVDeposit() public {
        uint32 epochId = queue.currentEpochId(); //first epoch

        Deposit(epochId, 250 * dollar, ALICE); //ALICE +250 //owns half of NAV
        Deposit(epochId, 250 * dollar, BOB); //BOB +250 //owns half of NAV
        //NAV = 500;

        //warp to epoch start so that epoch 2 can be processed, and epoch 1 is over on deposits
        (uint32 start, uint32 end,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue(); //process epoch 1 => epoch 2

        //INCREASE NAV +500
        //prank diem to INCREASE NAV
        //mint and increase nav by 500 dollars
        mockupERC20.mint(address(lp), 500 * dollar);
        vm.prank(address(queue));
        lp.updateLaggingNAV();
        assertTrue(lp.NAV() == 1000 * dollar, "NAV"); //NAV = 1000

        epochId = queue.currentEpochId(); //second epoch

        //Deposit Chad 500 on 2nd epoch
        Deposit(epochId, 500 * dollar, CHAD); //CHAD +500

        //withdraw 1st epoch
        //@notice ALICE = 250, BOB = 250, CHAD = 500, VIRTUAL NAV = 1500

        //Remove Alice 250
        address _user = ALICE; //remove 250 //removes half of NAV, because she owns half of LP total supply
        uint256 _amount = 250 * dollar;
        vm.startPrank(_user);
        lp.approve(address(queue), _amount);
        queue.removeLiquidity(1, _amount); //remove liq from epoch 1  //ALICE -250
        vm.stopPrank();

        // console.log("NAV", lp.NAV());
        // console.log("lp total supply", lp.totalSupply());
        uint256 prev_AliceCollateral = collateralToken.balanceOf(_user);
        //warp time to end of 1st epoch so that withdraws can be processed
        vm.warp(end + 1);
        //process CHAD +500, ALICE -250
        queue.processCurrentQueue(); //process epoch 2 => epoch 3
        //NAV = 1000
        assertTrue(lp.NAV() == 1000 * dollar, "NAV"); //NAV = 1000
        //time is currently in epoch 3 start + 1 === epoch 2 end + 1
        uint256 post_AliceCollateral = collateralToken.balanceOf(_user);
        // console.log("Alice diff", post_AliceCollateral - prev_AliceCollateral);
        // console.log("NAV", lp.NAV());
        //assert Alice removes half of NAV
        assertTrue(post_AliceCollateral - prev_AliceCollateral == lp.NAV() / 2, "Alice has half of NAV");
        //even though NAV changed to the double BOB still owns half of the pool

        //NAV = 1000 (ALICE REMOVED 500 FROM 1000, BUT CHAD DEPOSITED 500 CHANGING NAV TO 1000)

        //so CHAD needs to deposit double amount of BOB to get the same amount of LP, the remaining half of the pool
        //since NAV changed CHAD ONLY gets 250, which is half of the pool
        //log chad shares of lp
        uint256 prev_ChadLpBalance = lp.balanceOf(CHAD);
        assertTrue(prev_ChadLpBalance == 250 * dollar, "Chad has half of the pool");
        // console.log("Chad shares", prev_ChadLpBalance);

        epochId = queue.currentEpochId(); //third epoch
        //Remove Bob 250
        _user = BOB; //remove 250
        _amount = 250 * dollar; //remove 500
        vm.startPrank(_user);
        lp.approve(address(queue), _amount);
        queue.removeLiquidity(2, _amount); //remove liq from epoch 2
        vm.stopPrank();

        //warp time to end of 2nd epoch so that withdraws can be processed
        (start, end,,) = queue.epochData(epochId - 1);
        //warp time to end of 2nd epoch so that withdraws can be processed
        vm.warp(end + 1);

        uint256 prev_BobCollateral = collateralToken.balanceOf(_user);
        uint256 prev_NAV = lp.NAV();
        //process BOB -250, will withdraw half of NAV
        queue.processCurrentQueue(); //process epoch 3 => epoch 4
        // console.log("NAV", lp.NAV());
        assertTrue(lp.NAV() == 500 * dollar, "NAV"); //NAV = 500
        uint256 post_BobCollateral = collateralToken.balanceOf(_user);
        // console.log("Bob diff", post_BobCollateral - prev_BobCollateral);
        //assert bob removes half of NAV
        assertTrue(post_BobCollateral - prev_BobCollateral == prev_NAV / 2, "Bob has half of NAV");
    }

    function test_QueueChangesNAVWithdraw() public {
        uint32 epochId = queue.currentEpochId(); //first epoch

        Deposit(epochId, 500 * dollar, ALICE);
        Deposit(epochId, 250 * dollar, BOB);
        Deposit(epochId, 250 * dollar, CHAD);

        //warp to epoch start
        (uint32 start, uint32 end,,) = queue.epochData(epochId);
        vm.warp(start + 1);
        queue.processCurrentQueue();
        //NAV = 1000;

        //mint and increase nav by 100 dollars
        mockupERC20.mint(address(lp), 100 * dollar);
        // console.log("NAV", lp.NAV());
        // console.log("NAV", lp.NAV());
        //NAV = 1100;
        assertTrue(lp.NAV() == 1100 * dollar, "NAV");

        //withdraw 1st epoch
        //@notice ALICE = 500, BOB = 500

        //Remove Alice 500
        address _user = ALICE; //remove 500
        uint256 _amount = 500 * dollar; //remove 500
        vm.startPrank(_user);
        lp.approve(address(queue), _amount);
        queue.removeLiquidity(epochId, _amount);
        vm.stopPrank();
        uint256 prev_AliceCollateralBalance = collateralToken.balanceOf(_user);
        // console.log("prev_AliceCollateralBalance", prev_AliceCollateralBalance);

        //Remove Bob 250
        _user = BOB; //remove 250
        _amount = 250 * dollar; //remove 500
        vm.startPrank(_user);
        lp.approve(address(queue), _amount);
        queue.removeLiquidity(epochId, _amount);
        vm.stopPrank();
        uint256 prev_BobCollateralBalance = collateralToken.balanceOf(_user);
        // console.log("prev_BobCollateralBalance", prev_BobCollateralBalance);

        //Remove Chad 250
        _user = CHAD; //remove 250
        _amount = 250 * dollar; //remove 500
        vm.startPrank(_user);
        lp.approve(address(queue), _amount);
        queue.removeLiquidity(epochId, _amount);
        vm.stopPrank();
        uint256 prev_ChadCollateralBalance = collateralToken.balanceOf(_user);
        // console.log("prev_ChadCollateralBalance", prev_ChadCollateralBalance);

        // console.log("NAV", lp.NAV());
        // console.log("NAV", lp.NAV());
        //warp time to end of 1st epoch so that withdraws can be processed
        vm.warp(end + 1);
        queue.processCurrentQueue();
        console.log("NAV", lp.NAV());
        console.log("NAV", lp.NAV());
        console.log("Alice difference in collateral", collateralToken.balanceOf(ALICE) - prev_AliceCollateralBalance);
        console.log("Bob difference in collateral", collateralToken.balanceOf(BOB) - prev_BobCollateralBalance);
        console.log("Chad difference in collateral", collateralToken.balanceOf(CHAD) - prev_ChadCollateralBalance);
    }

    //TODO: Complicated Fuzz Tests with NAV increasing and decreasing

    function testInterestRate() public {
        MockupERC20 mockupBTC = new MockupERC20("BTC", 8);
        MockupAggregatorV3 btcOracle = new MockupAggregatorV3(
            8, //decimals
            "BTC", //description
            1, //version
            0, //roundId
            int(2500 * 1e8), //answer
            0, //startedAt
            0, //updatedAt
            0 //answeredInRound
        );
        
        oracle.addAssetPriceFeed(address(mockupBTC), address(btcOracle));

        console.log("create option id 1-4: 1550 usdc, 7 days, weth");
        createOption(1550 ether, block.timestamp + 1 days, address(mockupWETH), true); //1-4

        console.log("create option id 5-8: 2600 usdc, 7 days, btc");
        createOption(2600 ether, block.timestamp + 1 days, address(mockupBTC), true);  //5-8

        console.log("create option id 9-12: 1515 usdc, 3 days, weth");
        createOption(1515 ether, block.timestamp + 1 days, address(mockupWETH), false); //9-12

        console.log("create option id 13-16: 2515 usdc, 3 days, btc");
        createOption(2515 ether, block.timestamp + 1 days, address(mockupBTC), false);  //13-16

        mockupERC20.mint(address(lp), 10000 * dollar);

        //log nav
        console.log("NAV", lp.NAV());
        uint ratio = lp.utilizationRatio();
        console.log("utilizationRatio", ratio);

        //log interest rate
        assertTrue(lp.interestRate() == 0.05 ether, "interest rate should be min rate");
    }
}
