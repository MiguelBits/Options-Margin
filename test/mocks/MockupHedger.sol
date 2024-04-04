// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/interface/exchange/IIVXHedger.sol";

contract MockupHedger is IIVXHedger {
    function getTotalHedgingLiquidity(address asset) external view returns (uint256) {
        return 0;
    }
}
