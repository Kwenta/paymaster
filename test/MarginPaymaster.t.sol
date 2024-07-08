// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Bootstrap} from "test/utils/Bootstrap.sol";

contract MarginPaymasterTest is Bootstrap {
    uint256 constant BASE_BLOCK_NUMBER = 16841532;
    function setUp() public {
        /// @dev uncomment the following line to test in a forked environment
        /// at a specific block number
        vm.rollFork(BASE_BLOCK_NUMBER);

        initializeLocal();
    }

    function testSetupWorks() public {}
}
