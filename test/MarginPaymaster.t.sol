// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Bootstrap} from "test/utils/Bootstrap.sol";
import {EntryPoint, UserOperation} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {AccountFactory, Account} from "src/Account.sol";
import {MarginPaymaster, IPaymaster} from "src/MarginPaymaster.sol";
import {console} from "forge-std/console.sol";

contract MarginPaymasterTest is Bootstrap {
    uint256 constant BASE_BLOCK_NUMBER = 16915026;
    UserOperation internal userOp;
    bytes32 internal constant ADMIN_PERMISSION = "ADMIN";
    address constant USDC_MASTER_MINTER =
        0x2230393EDAD0299b7E7B59F20AA856cD1bEd52e1;
    uint128 constant sUSDId = 0;

    function setUp() public {
        /// @dev uncomment the following line to test in a forked environment
        /// at a specific block number
        vm.rollFork(BASE_BLOCK_NUMBER);

        initializeBase();

        accountFactory = new AccountFactory(
            perpsMarketProxyAddress,
            marginPaymasterAddress,
            smartMarginV3Address,
            usdcAddress
        );
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
        userOp = UserOperation({
            sender: sender,
            nonce: nonce,
            initCode: initCode,
            callData: abi.encodeWithSelector(Account.setupAccount.selector),
            callGasLimit: 2_000_000,
            verificationGasLimit: 2_000_000,
            preVerificationGas: 200_000,
            maxFeePerGas: 0.02 gwei,
            maxPriorityFeePerGas: 0.02 gwei,
            paymasterAndData: abi.encodePacked(address(marginPaymaster)),
            signature: signature
        });
    }

    function testAccountDeployed() public {
        ops.push(userOp);

        assertEq(sender.code.length, 0);
        assertEq(sender.balance, 0);
        uint256 balanceOfPaymasterBefore = entryPoint.balanceOf(
            address(marginPaymaster)
        );
        assertEq(balanceOfPaymasterBefore, initialPaymasterBalance);

        mintUSDC(address(this), 1000 * 1e6);
        usdc.approve(sender, type(uint256).max);

        vm.prank(bundler);
        entryPoint.handleOps(ops, bundler);

        uint256 balanceOfPaymasterAfter = entryPoint.balanceOf(
            address(marginPaymaster)
        );
        assertLt(balanceOfPaymasterAfter, balanceOfPaymasterBefore);
        assertGt(sender.code.length, 0);
    }

    function testAccountSetup() public {
        ops.push(userOp);

        mintUSDC(address(this), 1000 * 1e6);
        usdc.approve(sender, type(uint256).max);

        vm.prank(bundler);
        entryPoint.handleOps(ops, bundler);

        uint128 accountId = account.accountId();
        assertGt(accountId, 0);
        assertTrue(
            perpsMarketProxy.hasPermission(
                accountId,
                ADMIN_PERMISSION,
                marginPaymasterAddress
            )
        );
        assertEq(usdc.balanceOf(address(this)), 995 * 1e6);
        assertEq(usdc.balanceOf(sender), 0);
        assertLt(usdc.balanceOf(marginPaymasterAddress), 1e6);
        assertEq(usdc.balanceOf(marginPaymasterAddress), 0);
        uint256 colAmount = perpsMarketProxy.getCollateralAmount(
            accountId,
            sUSDId
        );
        assertGt(colAmount, 4 ether);
        assertLt(colAmount, 5 ether);
    }

    function testTransferToWalletAndApprove() public {
        bytes memory approvalCalldata = abi.encodeWithSelector(
            usdc.approve.selector,
            marginPaymasterAddress,
            type(uint256).max
        );
        userOp.callData = abi.encodeWithSelector(
            Account.execute.selector,
            address(usdc),
            0,
            approvalCalldata
        );
        ops.push(userOp);

        mintUSDC(sender, 1000 * 1e6);

        vm.prank(bundler);
        entryPoint.handleOps(ops, bundler);

        assertGt(usdc.allowance(sender, marginPaymasterAddress), 0);
        uint256 usdcLeftInWallet = usdc.balanceOf(sender);
        assertLt(usdcLeftInWallet, 1000 * 1e6);
        assertGt(usdcLeftInWallet, 0);
    }

    function testOnlyEntryPointCanCallValidatePaymasterUserOp() public {
        // Create a dummy UserOperation
        UserOperation memory op = getDummyUserOp();

        // Try to call validatePaymasterUserOp from a non-entry point address
        vm.prank(address(0x1234)); // Use a random address
        vm.expectRevert(MarginPaymaster.InvalidEntryPoint.selector);
        marginPaymaster.validatePaymasterUserOp(op, bytes32(0), 0);
    }

    function testOnlyEntryPointCanCallPostOp() public {
        // Create a dummy PostOpMode and context
        IPaymaster.PostOpMode mode = IPaymaster.PostOpMode(0);
        bytes memory context = "";

        // Try to call postOp from a non-entry point address
        vm.prank(address(0x1234)); // Use a random address
        vm.expectRevert(MarginPaymaster.InvalidEntryPoint.selector);
        marginPaymaster.postOp(mode, context, 0);
    }

    function bytesToAddress(
        bytes memory bys
    ) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 20))
        }
    }

    function mintUSDC(address to, uint256 amount) private {
        vm.prank(USDC_MASTER_MINTER);
        usdc.configureMinter(address(this), amount);
        usdc.mint(to, amount);
    }

    function getDummyUserOp() private pure returns (UserOperation memory) {
        return
            UserOperation({
                sender: address(0),
                nonce: 0,
                initCode: "",
                callData: "",
                callGasLimit: 0,
                verificationGasLimit: 0,
                preVerificationGas: 0,
                maxFeePerGas: 0,
                maxPriorityFeePerGas: 0,
                paymasterAndData: "",
                signature: ""
            });
    }
}
