// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {LightAccountFactory} from "lib/light-account/src/LightAccountFactory.sol";

import {console2} from "lib/forge-std/src/console2.sol";
import {
    MarginPaymaster,
    OptimismGoerliParameters,
    OptimismParameters,
    Setup
} from "script/Deploy.s.sol";
import {Test} from "lib/forge-std/src/Test.sol";

contract Bootstrap is Test {
    using console2 for *;

    MarginPaymaster internal marginPaymaster;
    EntryPoint internal entryPoint;
    LightAccountFactory internal lightAccountFactory;

    function initializeLocal() internal {
        BootstrapLocal bootstrap = new BootstrapLocal();
        (address marginPaymasterAddress) = bootstrap.init();

        marginPaymaster = MarginPaymaster(marginPaymasterAddress);
        entryPoint = new EntryPoint();
        lightAccountFactory = new LightAccountFactory(address(this), entryPoint);
    }

    function initializeOptimismGoerli() internal {
        BootstrapOptimismGoerli bootstrap = new BootstrapOptimismGoerli();
        (address marginPaymasterAddress) = bootstrap.init();

        marginPaymaster = MarginPaymaster(marginPaymasterAddress);
    }

    function initializeOptimism() internal {
        BootstrapOptimismGoerli bootstrap = new BootstrapOptimismGoerli();
        (address marginPaymasterAddress) = bootstrap.init();

        marginPaymaster = MarginPaymaster(marginPaymasterAddress);
    }

    /// @dev add other networks here as needed (ex: Base, BaseGoerli)
}

contract BootstrapLocal is Setup {
    function init() public returns (address) {
        address marginPaymasterAddress = Setup.deploySystem();

        return marginPaymasterAddress;
    }
}

contract BootstrapOptimism is Setup, OptimismParameters {
    function init() public returns (address) {
        address marginPaymasterAddress = Setup.deploySystem();

        return marginPaymasterAddress;
    }
}

contract BootstrapOptimismGoerli is Setup, OptimismGoerliParameters {
    function init() public returns (address) {
        address marginPaymasterAddress = Setup.deploySystem();

        return marginPaymasterAddress;
    }
}

// add other networks here as needed (ex: Base, BaseGoerli)
