// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {EntryPoint, UserOperation} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {LightAccountFactory, LightAccount} from "lib/light-account/src/LightAccountFactory.sol";
import {BaseLightAccount} from "lib/light-account/src/common/BaseLightAccount.sol";

import {Counter} from "test/utils/Counter.sol";
import {MarginPaymaster, OptimismGoerliParameters, OptimismParameters, Setup} from "script/Deploy.s.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {console2} from "lib/forge-std/src/console2.sol";

contract Bootstrap is Test {
    using console2 for *;

    Counter counter = new Counter();
    MarginPaymaster internal marginPaymaster;
    EntryPoint internal entryPoint;
    LightAccountFactory internal lightAccountFactory;
    uint256 userPk = 0x1234;
    uint256 bundlerPk = 0x12345;
    address payable user = payable(vm.addr(0x1234));
    address payable bundler = payable(vm.addr(0x12345));

    UserOperation[] ops;

    function initializeLocal() internal {
        BootstrapLocal bootstrap = new BootstrapLocal();
        address marginPaymasterAddress = bootstrap.init();

        marginPaymaster = MarginPaymaster(marginPaymasterAddress);
        entryPoint = new EntryPoint();
        lightAccountFactory = new LightAccountFactory(
            address(this),
            entryPoint
        );

        uint256 accountSalt = 1;
        bytes memory initCode = abi.encodeWithSelector(
            LightAccountFactory.createAccount.selector,
            address(this),
            accountSalt
        );
        address dest = address(counter);
        uint256 value = 0;
        bytes memory func = abi.encodeWithSelector(Counter.increment.selector);
        bytes memory callData = abi.encodeWithSelector(BaseLightAccount.execute.selector, dest, value, func);
        bytes memory signature;
        UserOperation memory op = UserOperation({
            sender: user,
            nonce: 1,
            initCode: initCode,
            callData: callData,
            accountGasLimits: bytes32(uint256(1 ether)),
            preVerificationGas: 1 ether,
            gasFees: bytes32(uint256(10 gwei)),
            paymasterAndData: abi.encode(address(marginPaymaster)),
            signature: signature
        });
        ops.push(op);

        assertEq(counter.number(), 0);

        vm.prank(bundler);
        entryPoint.handleOps(ops, user);

        assertEq(counter.number(), 1);
    }

    function initializeOptimismGoerli() internal {
        BootstrapOptimismGoerli bootstrap = new BootstrapOptimismGoerli();
        address marginPaymasterAddress = bootstrap.init();

        marginPaymaster = MarginPaymaster(marginPaymasterAddress);
    }

    function initializeOptimism() internal {
        BootstrapOptimismGoerli bootstrap = new BootstrapOptimismGoerli();
        address marginPaymasterAddress = bootstrap.init();

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
