// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {EntryPoint, UserOperation} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {Counter} from "test/utils/Counter.sol";
import {MarginPaymaster, OptimismGoerliParameters, OptimismParameters, Setup} from "script/Deploy.s.sol";
import {AccountFactory, Account} from "src/Account.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";

contract Bootstrap is Test {
    error SenderAddressResult(address sender);

    Counter counter = new Counter();
    MarginPaymaster internal marginPaymaster;
    EntryPoint internal entryPoint;
    AccountFactory internal accountFactory;
    uint256 userPk = 0x1234;
    uint256 bundlerPk = 0x12345;
    address payable user = payable(vm.addr(0x1234));
    address payable bundler = payable(vm.addr(0x12345));

    UserOperation[] ops;

    function initializeLocal() internal {
        BootstrapLocal bootstrap = new BootstrapLocal();
        address marginPaymasterAddress = bootstrap.init();

        marginPaymaster = MarginPaymaster(marginPaymasterAddress);
        vm.deal(marginPaymasterAddress, 10 ether);
        entryPoint = new EntryPoint();
        accountFactory = new AccountFactory();

        bytes memory initCode = abi.encodePacked(
            address(accountFactory),
            abi.encodeCall(accountFactory.createAccount, (address(this)))
        );

        address sender;
        try entryPoint.getSenderAddress(initCode) {
            assert(false);
        } catch (bytes memory reason) {
            bytes memory result = new bytes(20);
            assembly {
                // Copy the last 20 bytes from `reason` to `result`
                mstore(
                    add(result, 32),
                    mload(add(add(reason, 32), sub(mload(reason), 20)))
                )
            }
            sender = bytesToAddress(result);
        }

        uint256 nonce = entryPoint.getNonce(sender, 0);

        // uint256 accountSalt = 1;
        // bytes memory initCode = abi.encodeWithSelector(
        //     AccountFactory.createAccount.selector,
        //     address(this),
        //     accountSalt
        // );
        // address dest = address(counter);
        // uint256 value = 0;
        // bytes memory func = abi.encodeWithSelector(Counter.increment.selector);
        // bytes memory callData = abi.encodeWithSelector(BaseLightAccount.execute.selector, dest, value, func);
        // bytes memory signature;
        // UserOperation memory op = UserOperation({
        //     sender: user,
        //     nonce: 1,
        //     initCode: initCode,
        //     callData: callData,
        //     accountGasLimits: bytes32(uint256(1 ether)),
        //     preVerificationGas: 1 ether,
        //     gasFees: bytes32(uint256(10 gwei)),
        //     paymasterAndData: abi.encode(address(marginPaymaster)),
        //     signature: signature
        // });
        // ops.push(op);

        // assertEq(counter.number(), 0);

        // vm.prank(bundler);
        // entryPoint.handleOps(ops, user);

        // assertEq(counter.number(), 1);
    }

    function bytesToAddress(bytes memory bys) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 20))
        }
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
