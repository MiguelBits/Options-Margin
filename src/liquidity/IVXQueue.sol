// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

// Interfaces
import {IIVXLP} from "../interface/liquidity/IIVXLP.sol";
import {IIVXQueue} from "../interface/liquidity/IIVXQueue.sol";

// Libraries
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IVXQueue
 * @notice The Queue contract for the IVX LP contract, performs deposits and withdraws on a FIFO basis for the LP contract
 * @author gradient (@gradientIVX), MiguelBits (@MiguelBits)
 */
contract IVXQueue is ReentrancyGuard, IIVXQueue, Pausable, Ownable {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                 VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev The address of the collateral for the market LP
    ERC20 public collateral;

    /// @dev The address of the LP contract
    IIVXLP public LP;

    /// @dev The length of an epoch in seconds
    uint32 public epochDuration;

    /// @dev The number of epochs that have passed
    uint32 public currentEpochId;

    // @dev The timestamp of the first epoch, we add epoch count * epoch duration to get the next epochs timestamp
    uint32 firstEpochTimestamp;

    /*//////////////////////////////////////////////////////////////
                                 MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(uint32 epochId => epochMetadata epoch) public epochData;

    //deposits
    mapping(uint32 epochId => uint256 depositQueueLength) public depositEpochQueueLength;
    mapping(uint32 epochId => address[] users) public depositEpochQueue;
    //because fifo and maxCap we need to keep track of the amount of each deposit ordered by the queue users
    mapping(uint32 epochId => uint256[] depositAmounts) public depositEpochQueueAmounts;
    mapping(uint32 epochId => mapping(address user => uint256 amount)) public depositUserQueue;

    //withdraws
    mapping(uint32 epochId => uint256 withdrawQueueLength) public withdrawEpochQueueLength;
    mapping(uint32 epochId => address[] users) public withdrawEpochQueue;
    //since there is no maxCap we dont need to keep track of the amount of each withdraw ordered by the queue users
    mapping(uint32 epochId => mapping(address user => uint256 shares)) public withdrawUserQueue;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier canDeposit(uint32 epochId) {
        //require start time is bigger than blocktime
        uint32 blocktimestamp = uint32(block.timestamp);
        uint32 startTimestamp = epochData[epochId].epochStartTimestamp;
        if (blocktimestamp > startTimestamp) revert CannotDeposit(epochId, startTimestamp);
        _;
    }

    modifier cannotDeposit(uint32 epochId) {
        //require blocktime is bigger than start time
        uint32 blocktimestamp = uint32(block.timestamp);
        uint32 startTimestamp = epochData[epochId].epochStartTimestamp;
        if (blocktimestamp <= startTimestamp) revert CanDeposit(epochId, startTimestamp);
        _;
    }

    modifier canWithdraw(uint32 epochId) {
        //require block time is less than end time
        uint32 blocktimestamp = uint32(block.timestamp);
        uint32 endTimestamp = epochData[epochId].epochEndTimestamp;
        if (blocktimestamp > endTimestamp) revert CannotWithdraw(epochId, endTimestamp);
        _;
    }

    modifier cannotWithdraw(uint32 epochId) {
        //require block time is bigger than end time
        uint32 blocktimestamp = uint32(block.timestamp);
        uint32 endTimestamp = epochData[epochId].epochEndTimestamp;
        if (blocktimestamp <= endTimestamp) revert CannotWithdraw(epochId, endTimestamp);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param _lp The address of the LP contract
     * @param _firstEpochTimestamp The start timestamp of the first epoch
     */
    constructor(IIVXLP _lp, uint32 _firstEpochTimestamp) {
        if (address(_lp) == address(0)) revert AddressZero();
        collateral = _lp.collateral();
        LP = _lp;
        epochDuration = 1 days;
        firstEpochTimestamp = _firstEpochTimestamp;
        currentEpochId = 1;

        // Sets the first epoch
        epochData[0] = epochMetadata({
            epochStartTimestamp: 0,
            epochEndTimestamp: 0,
            withdrawalsProcessed: true,
            depositsProcessed: true
        });

        // Sets the first epoch
        epochData[currentEpochId] = epochMetadata({
            epochStartTimestamp: firstEpochTimestamp,
            epochEndTimestamp: firstEpochTimestamp + epochDuration,
            withdrawalsProcessed: false,
            depositsProcessed: false
        });
    }

    function setEpochDuration(uint32 _epochDuration) external onlyOwner {
        epochDuration = _epochDuration;
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    function processCurrentQueue() external {
        if (currentEpochId == 1) {
            processDepositQueue(currentEpochId);
        } else {
            processWithdrawQueue(currentEpochId - 1);
            processDepositQueue(currentEpochId);
        }
    }

    function nextEpochStartTimestamp() external view returns (uint32) {
        return epochData[currentEpochId].epochEndTimestamp;
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds liquidity to the queue for the next epoch
    /// @param _amount The amount of liquidity to add
    function addLiquidity(uint32 epochId, uint256 _amount) external nonReentrant canDeposit(epochId) whenNotPaused {
        if (_amount == 0) revert AmountMustBeGreaterThanZero();

        if (LP.vaultMaximumCapacity() < LP.NAV() + _amount) {
            revert IVXVaultCapacityExceeded(LP.vaultMaximumCapacity(), _amount);
        }

        // Transfers the deposited liquidity to this contract
        collateral.safeTransferFrom(msg.sender, address(this), _amount);

        // Logs the deposit in the depositUserQueue
        _addLiquidity(epochId, _amount, msg.sender);

        emit DepositQueued(msg.sender, _amount, epochId, block.timestamp);
    }

    function reduceQueuedDeposit(uint32 epochId, uint256 _amount) external nonReentrant canDeposit(epochId) {
        // Get the amount of the user's queued deposits
        uint256 queuedDeposits = depositUserQueue[epochId][msg.sender];

        if (_amount == 0 || queuedDeposits == 0) revert AmountMustBeGreaterThanZero();

        uint256 amountToReduce = _amount > queuedDeposits ? queuedDeposits : _amount;
        uint256 amountToTransfer;

        uint256 arraylength = depositEpochQueue[epochId].length;
        // Iterate backwards through the queue to find the user's queued deposits
        for (uint256 i = arraylength - 1; i >= 0; --i) {
            if (depositEpochQueue[epochId][i] == msg.sender) {
                uint256 depositAmountAtIndex = depositEpochQueueAmounts[epochId][i];

                if (depositAmountAtIndex >= amountToReduce) {
                    depositEpochQueueAmounts[epochId][i] = depositAmountAtIndex - amountToReduce;

                    amountToTransfer += amountToReduce;
                    break;
                } else {
                    depositEpochQueueAmounts[epochId][i] = 0;
                    amountToReduce -= depositAmountAtIndex;
                    amountToTransfer += depositAmountAtIndex;
                }
            }
        }
        
        depositUserQueue[epochId][msg.sender] -= amountToTransfer;
        // Transfers the deposited liquidity back to the user
        collateral.safeTransfer(msg.sender, amountToTransfer);
    }

    /// @notice Processes the deposit queue for the current epoch, fulfilled on a dollar basis
    /// @notice Should be called after processing withdrawals for an epoch
    /// @dev Recursively deposits liquidity until hitting the LP NAV threshold
    function processDepositQueue(uint32 epochId) public cannotDeposit(epochId) {
        //check deposit queue length not 0
        if (depositEpochQueueLength[epochId] == 0) {
            epochData[epochId].depositsProcessed = true;
            _rolloverEpoch();
            emit DepositQueueProcessed(epochId, 0);
            return;
        }

        if (!epochData[epochId - 1].withdrawalsProcessed) revert WithdrawalsNotProcessed(epochId - 1);

        uint256 totalDepositsProcessed = 0;

        uint256 depositQueueLength = depositEpochQueueLength[epochId];

        uint256 LPVaultCapacity = LP.vaultMaximumCapacity();
        uint256 LPVaultBalance = LP.laggingNAV();

        uint256 LPVaultCapacityRemaining = LPVaultCapacity - LPVaultBalance;

        uint32 nextEpochId = currentEpochId + 1;

        for (uint256 i = 0; i < depositQueueLength; ++i) {
            address _user = depositEpochQueue[epochId][i];
            uint256 _amount = depositEpochQueueAmounts[epochId][i];
            //delete the deposit from the queue
            delete depositEpochQueue[epochId][i];
            delete depositEpochQueueAmounts[epochId][i];

            //vault still has capacity
            if (LPVaultCapacityRemaining > 0) {
                //deposit the minimum of the amount or the remaining capacity
                uint256 _depositAmount = _amount > LPVaultCapacityRemaining ? LPVaultCapacityRemaining : _amount;
                //mint the user shares
                LP.mint(_user, _depositAmount);
                _depositLiquidity(_depositAmount);
                LPVaultCapacityRemaining -= _depositAmount;

                // Increment total deposits processed
                totalDepositsProcessed += _depositAmount;

                // Roll the residual deposit amount into the queue for the next epoch
                if (_amount > _depositAmount) _addLiquidity(nextEpochId, _amount - _depositAmount, _user);
            } else {
                // Roll the entire amount into the queue for the next epoch
                _addLiquidity(nextEpochId, _amount, _user);
            }
        }

        // Set the depositsProcessed flag to true
        epochData[epochId].depositsProcessed = true;

        // Increment the epoch count
        _rolloverEpoch();

        emit DepositQueueProcessed(epochId, totalDepositsProcessed);
    }

    /*//////////////////////////////////////////////////////////////
                                 WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function removeLiquidity(uint32 epochId, uint256 _shares) external nonReentrant canWithdraw(epochId) {
        if (_shares == 0) revert AmountMustBeGreaterThanZero();

        // Transfers the IVXLP shares to this contract
        ERC20(address(LP)).safeTransferFrom(msg.sender, address(this), _shares);
        //increment epoch length
        withdrawEpochQueueLength[epochId] += 1;
        //add user to queue
        withdrawEpochQueue[epochId].push(msg.sender);
        //add shares to queue
        withdrawUserQueue[epochId][msg.sender] += _shares;
    }

    function reduceQueuedWithdrawal(uint32 epochId, uint256 _shares) external canWithdraw(epochId) nonReentrant {
        if (_shares == 0) revert AmountMustBeGreaterThanZero();

        uint256 reduceAmount =
            (withdrawUserQueue[epochId][msg.sender] < _shares) ? withdrawUserQueue[epochId][msg.sender] : _shares;

        //delete this for a gas rebate if it's subtracting to 0
        if (reduceAmount == withdrawUserQueue[epochId][msg.sender]) delete withdrawUserQueue[epochId][msg.sender];
        else withdrawUserQueue[epochId][msg.sender] -= reduceAmount;

        // Transfers the reduced IVXLP shares back to the sender
        ERC20(address(LP)).safeTransfer(msg.sender, reduceAmount);
    }

    function processWithdrawQueue(uint32 epochId) public cannotWithdraw(epochId) {
        //check withdraw queue length not 0
        if (withdrawEpochQueueLength[epochId] == 0) {
            epochData[epochId].withdrawalsProcessed = true;
            emit WithdrawQueueProcessed(epochId, 0);
            return;
        }
        //require withdrawals have not been processed
        if (epochData[epochId].withdrawalsProcessed) revert WithdrawalsAlreadyProcessed(epochId);

        //TODO: FEE COLLECTION
        uint256 totalWithdrawalsProcessed = 0;

        uint256 withdrawQueueLength = withdrawEpochQueueLength[epochId];

        for (uint256 i = 0; i < withdrawQueueLength; ++i) {
            address _user = withdrawEpochQueue[epochId][i];
            uint256 _shares = withdrawUserQueue[epochId][_user];
            //delete user from mappings
            // delete withdrawUserQueue[epochId][_user];
            // delete withdrawEpochQueue[epochId][i];
            //burn the user shares inside the queue contract
            LP.withdrawLiquidity(_shares, _user);

            // Increment total withdrawals processed
            totalWithdrawalsProcessed += _shares;
        }

        // Set the withdrawalsProcessed flag to true
        epochData[epochId].withdrawalsProcessed = true;
        LP.burn(address(this), totalWithdrawalsProcessed);
        LP.updateLaggingNAV();

        emit WithdrawQueueProcessed(epochId, totalWithdrawalsProcessed);
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/
    function _addLiquidity(uint32 epochId, uint256 _amount, address _user) internal {
        depositEpochQueueLength[epochId] += 1;
        depositEpochQueue[epochId].push(_user);
        depositEpochQueueAmounts[epochId].push(_amount);
        depositUserQueue[epochId][_user] += _amount;
    }

    function _depositLiquidity(uint256 _amount) internal {
        collateral.safeTransfer(address(LP), _amount);
        LP.updateLaggingNAV();
    }

    function _rolloverEpoch() internal {
        // Increment the epoch count
        currentEpochId += 1;
        uint32 currentEpochEndTimestamp = epochData[currentEpochId - 1].epochEndTimestamp;

        // Roll the epoch to the new epoch
        epochData[currentEpochId] = epochMetadata({
            epochStartTimestamp: currentEpochEndTimestamp,
            epochEndTimestamp: currentEpochEndTimestamp + epochDuration,
            depositsProcessed: false,
            withdrawalsProcessed: false
        });
    }
}
