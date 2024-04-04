//SPDX-License-Identifier: ISC

pragma solidity ^0.8.18;

interface IPositionRouter {
    struct IncreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 amountIn;
        uint256 minOut;
        uint256 sizeDelta;
        bool isLong;
        uint256 acceptablePrice;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
        bool hasCollateralInETH;
        address callbackTarget;
    }

    struct DecreasePositionRequest {
        address account;
        address[] path;
        address indexToken;
        uint256 collateralDelta;
        uint256 sizeDelta;
        bool isLong;
        address receiver;
        uint256 acceptablePrice;
        uint256 minOut;
        uint256 executionFee;
        uint256 blockNumber;
        uint256 blockTime;
        bool withdrawETH;
        address callbackTarget;
    }

    function increasePositionRequests(bytes32 key)
        external
        view
        returns (
            address account,
            address[] memory,
            address,
            uint256,
            uint256,
            uint256,
            bool,
            uint256,
            uint256,
            uint256,
            uint256,
            bool,
            address
        );

    function decreasePositionRequests(bytes32 key)
        external
        view
        returns (
            address account,
            address[] memory,
            address,
            uint256,
            uint256,
            bool,
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool,
            address
        );

    function admin() external view returns (address);

    function setPositionKeeper(address _positionKeeper, bool active) external;

    function vault() external view returns (address);

    function callbackGasLimit() external view returns (uint256);

    function minExecutionFee() external view returns (uint256);

    function increasePositionRequestKeysStart() external returns (uint256);

    function decreasePositionRequestKeysStart() external returns (uint256);

    function executeIncreasePosition(bytes32 key, address payable _executionFeeReceiver) external;

    function executeDecreasePosition(bytes32 key, address payable _executionFeeReceiver) external;

    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) external payable returns (bytes32);

    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH,
        address _callbackTarget
    ) external payable returns (bytes32);

    function cancelIncreasePosition(bytes32 _key, address _executionFeeReceiver) external returns (bool);

    function cancelDecreasePosition(bytes32 _key, address _executionFeeReceiver) external returns (bool);
}
