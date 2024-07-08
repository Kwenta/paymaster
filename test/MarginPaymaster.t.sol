// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Bootstrap} from "test/utils/Bootstrap.sol";

contract MarginPaymasterTest is Bootstrap {
    function setUp() public {
        /// @dev uncomment the following line to test in a forked environment
        /// at a specific block number
        // vm.rollFork(NETWORK_BLOCK_NUMBER);

        initializeLocal();
    }

    function testSetupWorks() public {}
}
