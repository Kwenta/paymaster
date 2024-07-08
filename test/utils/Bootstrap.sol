// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.25;

import {EntryPoint, UserOperation} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

import {MarginPaymaster, OptimismGoerliParameters, OptimismParameters, Setup} from "script/Deploy.s.sol";
import {AccountFactory, Account} from "src/Account.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";

contract Bootstrap is Test {
    error SenderAddressResult(address sender);

    MarginPaymaster internal marginPaymaster;
    EntryPoint internal entryPoint;
    AccountFactory internal accountFactory;
    Account internal account;
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
        accountFactory = new AccountFactory();
        vm.deal(marginPaymasterAddress, 100 ether);
        vm.deal(address(this), 10 ether);
        entryPoint.depositTo{value: 10 ether}(marginPaymasterAddress);

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
        account = Account(sender);

        uint256 nonce = entryPoint.getNonce(sender, 0);
        bytes memory signature;
        UserOperation memory userOp = UserOperation({
            sender: sender,
            nonce: nonce,
            initCode: initCode,
            callData: abi.encodeWithSelector(Account.execute.selector),
            callGasLimit: 800_000,
            verificationGasLimit: 800_000,
            preVerificationGas: 200_000,
            maxFeePerGas: 10 gwei,
            maxPriorityFeePerGas: 10 gwei,
            paymasterAndData: abi.encodePacked(address(marginPaymaster)),
            signature: signature
        });

        ops.push(userOp);

        assertEq(sender.code.length, 0);

        vm.prank(bundler);
        entryPoint.handleOps(ops, user);

        assertGt(sender.code.length, 0);
        assertEq(account.count(), 1);
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
