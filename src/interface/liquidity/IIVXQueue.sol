pragma solidity ^0.8.18;

interface IIVXQueue {
    struct epochMetadata {
        uint32 epochStartTimestamp;
        uint32 epochEndTimestamp;
        bool withdrawalsProcessed;
        bool depositsProcessed;
    }

    function currentEpochId() external view returns (uint32);
    function epochData(uint32 epoch) external view returns (uint32, uint32, bool, bool);
    function nextEpochStartTimestamp() external view returns (uint32);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event DepositQueued(address indexed account, uint256 amount, uint32 epochId, uint256 timestamp);
    event DepositQueueProcessed(uint32 indexed epochId, uint256 amount);

    event WithdrawQueued(address indexed account, uint256 amount, uint32 epochId, uint256 timestamp);
    event WithdrawQueueProcessed(uint32 indexed epochId, uint256 amount);

    event EpochStarted(uint256 epochStartTime, uint32 epochDuration);
    event EpochConcluded(uint256 epochEndTime, uint256 epochStartTime);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error AddressZero();
    error AmountMustBeGreaterThanZero();
    error DepositsAlreadyProcessed(uint32 epochId);
    error DepositsNotProcessed(uint32 epochId);
    error WithdrawalsAlreadyProcessed(uint32 epochId);
    error WithdrawalsNotProcessed(uint32 epochId);
    error InsufficientDepositAmountInQueue(address _user, uint256 _amount, uint256 _queueAmount);
    error CannotDeposit(uint32 _EpochId, uint32 _startTimestamp);
    error CanDeposit(uint32 _EpochId, uint32 _startTimestamp);
    error CanWithdraw(uint32 _EpochId, uint32 _endTimestamp);
    error CannotWithdraw(uint32 _EpochId, uint32 _endTimestamp);
    error UserNotInCurrentDepositEpochQueue(address _user, uint256 _EpochTimestamp);
    error InsufficientBalance(address _user, uint256 _amount, uint256 _balance);
    error EpochAlreadyProcessed(uint32 _epochId);
    error IVXVaultCapacityExceeded(uint256 capacity, uint256 requestedIncrease);
}
