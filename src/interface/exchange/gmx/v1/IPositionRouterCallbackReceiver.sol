//SPDX-License-Identifier: ISC

pragma solidity ^0.8.18;

interface IPositionRouterCallbackReceiver {
    function gmxPositionCallback(bytes32 positionKey, bool isExecuted, bool isIncrease) external;
}
