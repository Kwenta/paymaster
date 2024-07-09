// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Bootstrap} from "test/utils/Bootstrap.sol";
import {EntryPoint, UserOperation} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {AccountFactory, Account} from "src/Account.sol";

contract MarginPaymasterTest is Bootstrap {
    uint256 constant BASE_BLOCK_NUMBER = 16841532;

    function setUp() public {
        /// @dev uncomment the following line to test in a forked environment
        /// at a specific block number
        vm.rollFork(BASE_BLOCK_NUMBER);

        initializeBase();

        accountFactory = new AccountFactory();
        vm.deal(address(this), initialPaymasterBalance);
        entryPoint.depositTo{value: initialPaymasterBalance}(
            marginPaymasterAddress
        );

        bytes memory initCode = abi.encodePacked(
            address(accountFactory),
            abi.encodeCall(accountFactory.createAccount, (address(this)))
        );

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
        assertEq(sender.balance, 0);
        uint256 balanceOfPaymasterBefore = entryPoint.balanceOf(
            address(marginPaymaster)
        );
        assertEq(balanceOfPaymasterBefore, initialPaymasterBalance);

        vm.prank(bundler);
        entryPoint.handleOps(ops, bundler);

        uint256 balanceOfPaymasterAfter = entryPoint.balanceOf(
            address(marginPaymaster)
        );
        assertLt(balanceOfPaymasterAfter, balanceOfPaymasterBefore);
    }

    function testAccountDeployed() public {
        assertGt(sender.code.length, 0);
        assertEq(account.count(), 1);
    }

    function bytesToAddress(
        bytes memory bys
    ) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 20))
        }
    }
}
