// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Bootstrap} from "test/utils/Bootstrap.sol";
import {EntryPoint, UserOperation} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {AccountFactory, MockAccount} from "src/MockAccount.sol";
import {MarginPaymaster, IPaymaster} from "src/MarginPaymaster.sol";
import {IStakeManager} from "lib/account-abstraction/contracts/interfaces/IStakeManager.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {console} from "forge-std/console.sol";

contract MarginPaymasterTest is Bootstrap {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    uint256 constant BASE_BLOCK_NUMBER = 16915026;
    UserOperation internal userOp;
    bytes32 internal constant ADMIN_PERMISSION = "ADMIN";
    address constant USDC_MASTER_MINTER =
        0x2230393EDAD0299b7E7B59F20AA856cD1bEd52e1;
    uint128 constant sUSDId = 0;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

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
        account = MockAccount(sender);

        uint256 nonce = entryPoint.getNonce(sender, 0);
        bytes memory signature;
        userOp = UserOperation({
            sender: sender,
            nonce: nonce,
            initCode: initCode,
            callData: abi.encodeWithSelector(MockAccount.setupAccount.selector),
            callGasLimit: 2_000_000,
            verificationGasLimit: 2_000_000,
            preVerificationGas: 200_000,
            maxFeePerGas: 0.02 gwei,
            maxPriorityFeePerGas: 0.02 gwei,
            paymasterAndData: abi.encodePacked(address(marginPaymaster)),
            signature: signature
        });

        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        bytes32 ethSignedMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backEndPk, ethSignedMessage);
        signature = bytes.concat(r, s, bytes1(v));
        userOp.signature = signature;

        marginPaymaster.setAuthorizer(backEnd, true);
    }

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testOwner() public {
        assertEq(marginPaymaster.owner(), address(this));
    }

    function testSetAuthorizer() public {
        address authorizer = address(0x123456);
        bool status = true;

        // Set the authorizer
        marginPaymaster.setAuthorizer(authorizer, status);

        // Verify the authorizer status
        assertTrue(marginPaymaster.authorizers(authorizer));

        // Change the authorizer status
        status = false;
        marginPaymaster.setAuthorizer(authorizer, status);

        // Verify the updated authorizer status
        assertFalse(marginPaymaster.authorizers(authorizer));
    }

    function testSetAuthorizerOnlyOwner() public {
        address authorizer = address(0x123456);
        bool status = true;

        // Try to set the authorizer from a non-owner account
        vm.prank(address(0x789));
        vm.expectRevert("Ownable: caller is not the owner");
        marginPaymaster.setAuthorizer(authorizer, status);

        // Set the authorizer from the owner account
        marginPaymaster.setAuthorizer(authorizer, status);

        // Verify the authorizer status
        assertTrue(marginPaymaster.authorizers(authorizer));
    }

    function testSwapUSDCToETH() public {
        uint256 initialETHBalance = marginPaymasterAddress.balance;
        uint256 amountOutMinimum = 1e18; // 1 ETH minimum output

        // Mint USDC to the contract
        mintUSDC(address(marginPaymaster), 5000 * 1e6);

        // Swap USDC to ETH
        marginPaymaster.swapUSDCToETH(amountOutMinimum);

        // Check if ETH balance has increased
        uint256 finalETHBalance = marginPaymasterAddress.balance;
        assertGt(finalETHBalance, initialETHBalance);
    }

    function testSwapUSDCToETH_onlyOwner() public {
        uint256 amountOutMinimum = 1e18; // 1 ETH minimum output

        vm.prank(address(0x123)); // some non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        marginPaymaster.swapUSDCToETH(amountOutMinimum);
    }

    function testDepositToEntryPoint() public {
        uint256 depositAmount = 1e18; // 1 ETH
        vm.deal(marginPaymasterAddress, depositAmount);

        // Deposit ETH to EntryPoint
        marginPaymaster.depositToEntryPoint(depositAmount);

        // Check if the deposit was successful
        uint256 entryPointBalance = entryPoint.balanceOf(
            address(marginPaymaster)
        );
        assertEq(entryPointBalance, depositAmount + initialPaymasterBalance);
    }

    function testDepositToEntryPoint_onlyOwner() public {
        uint256 depositAmount = 1e18; // 1 ETH

        vm.prank(address(0x123)); // some non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        marginPaymaster.depositToEntryPoint(depositAmount);
    }

    function testStake() public {
        uint256 stakeAmount = 1e18; // 1 ETH
        uint32 unstakeDelaySec = 3600; // 1 hour

        vm.deal(marginPaymasterAddress, stakeAmount);

        // Stake ETH in EntryPoint
        marginPaymaster.stake(stakeAmount, unstakeDelaySec);

        // Check if the stake was successful
        IStakeManager.DepositInfo memory depositInfo = entryPoint
            .getDepositInfo(address(marginPaymaster));
        assertEq(depositInfo.stake, stakeAmount);
        assertEq(depositInfo.unstakeDelaySec, unstakeDelaySec);
    }

    function testStake_onlyOwner() public {
        uint256 stakeAmount = 1e18; // 1 ETH
        uint32 unstakeDelaySec = 3600; // 1 hour

        vm.prank(address(0x123)); // some non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        marginPaymaster.stake(stakeAmount, unstakeDelaySec);
    }

    function testUnlockStake() public {
        uint256 stakeAmount = 1e18; // 1 ETH
        uint32 unstakeDelaySec = 3600; // 1 hour

        vm.deal(marginPaymasterAddress, stakeAmount);

        // Stake ETH in EntryPoint
        marginPaymaster.stake(stakeAmount, unstakeDelaySec);

        // Unlock the stake
        marginPaymaster.unlockStake();

        // Check if the stake is unlocked
        IStakeManager.DepositInfo memory depositInfo = entryPoint
            .getDepositInfo(address(marginPaymaster));
        assertEq(depositInfo.stake, stakeAmount);
        assertEq(depositInfo.unstakeDelaySec, unstakeDelaySec);
        assertGt(depositInfo.withdrawTime, 0);
    }

    function testUnlockStake_onlyOwner() public {
        vm.prank(address(0x123)); // some non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        marginPaymaster.unlockStake();
    }

    function testWithdrawStake() public {
        uint256 stakeAmount = 1e18; // 1 ETH
        uint32 unstakeDelaySec = 3600; // 1 hour
        address payable withdrawAddress = payable(address(0x321));

        vm.deal(marginPaymasterAddress, stakeAmount);

        // Stake ETH in EntryPoint
        marginPaymaster.stake(stakeAmount, unstakeDelaySec);

        // Unlock the stake
        marginPaymaster.unlockStake();

        // Fast forward time to allow withdrawal
        vm.warp(block.timestamp + unstakeDelaySec);

        // Withdraw the stake
        marginPaymaster.withdrawStake(withdrawAddress);

        // Check if the stake was withdrawn
        IStakeManager.DepositInfo memory depositInfo = entryPoint
            .getDepositInfo(address(marginPaymaster));
        assertEq(depositInfo.stake, 0);
        assertEq(depositInfo.unstakeDelaySec, 0);
    }

    function testWithdrawStake_onlyOwner() public {
        address payable withdrawAddress = payable(address(0x321));
        vm.prank(withdrawAddress); // some non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        marginPaymaster.withdrawStake(withdrawAddress);
    }

    function testWithdrawTo() public {
        uint256 depositAmount = 1e18; // 1 ETH
        address payable withdrawAddress = payable(address(0x321));

        vm.deal(marginPaymasterAddress, depositAmount);

        // Deposit ETH to EntryPoint
        marginPaymaster.depositToEntryPoint(depositAmount);

        // // // Withdraw from EntryPoint
        marginPaymaster.withdrawTo(withdrawAddress, depositAmount);

        // // // Check if the withdrawal was successful
        uint256 entryPointBalance = entryPoint.balanceOf(
            address(marginPaymaster)
        );
        assertEq(entryPointBalance, initialPaymasterBalance);

        // Check if the funds were transferred to the withdrawAddress
        uint256 withdrawAddressBalance = withdrawAddress.balance;
        assertEq(withdrawAddressBalance, depositAmount);
    }

    function testWithdrawTo_onlyOwner() public {
        uint256 depositAmount = 1e18; // 1 ETH
        address payable withdrawAddress = payable(address(0x321));
        // Attempt to withdraw from EntryPoint as a non-owner
        vm.prank(withdrawAddress); // some non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        marginPaymaster.withdrawTo(withdrawAddress, depositAmount);
    }

    function testWithdrawETH() public {
        uint256 depositAmount = 1e18; // 1 ETH
        address payable withdrawAddress = payable(address(0x321));

        vm.deal(marginPaymasterAddress, depositAmount);

        // Withdraw ETH from the contract
        marginPaymaster.withdrawETH(withdrawAddress, depositAmount);

        // Check if the funds were transferred to the withdrawAddress
        uint256 withdrawAddressBalance = withdrawAddress.balance;
        assertEq(withdrawAddressBalance, depositAmount);
    }

    function testWithdrawETH_onlyOwner() public {
        uint256 depositAmount = 1e18; // 1 ETH
        address payable withdrawAddress = payable(address(0x321));
        // Attempt to withdraw ETH as a non-owner
        vm.prank(withdrawAddress); // some non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        marginPaymaster.withdrawETH(withdrawAddress, depositAmount);
    }

    function testWithdrawUSDC() public {
        uint256 depositAmount = 1000 * 1e6; // 1000 USDC
        address withdrawAddress = address(0x321);

        // Mint USDC to the contract
        mintUSDC(address(marginPaymaster), depositAmount);

        // Withdraw USDC from the contract
        marginPaymaster.withdrawUSDC(withdrawAddress, depositAmount);

        // Check if the funds were transferred to the withdrawAddress
        uint256 withdrawAddressBalance = usdc.balanceOf(withdrawAddress);
        assertEq(withdrawAddressBalance, depositAmount);
    }

    function testWithdrawUSDC_onlyOwner() public {
        uint256 depositAmount = 1000 * 1e6; // 1000 USDC
        address withdrawAddress = address(0x321);
        // Attempt to withdraw USDC as a non-owner
        vm.prank(withdrawAddress); // some non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        marginPaymaster.withdrawUSDC(withdrawAddress, depositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                             USER OP TESTS
    //////////////////////////////////////////////////////////////*/

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

    function testUserOpRejectedIfBackEndIsUnauthorized() public {
        ops.push(userOp);

        // Ensure backEnd is unauthorized
        marginPaymaster.setAuthorizer(backEnd, false);

        vm.prank(bundler);
        vm.expectRevert();
        entryPoint.handleOps(ops, backEnd);
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
        assertGt(usdc.balanceOf(marginPaymasterAddress), 0);
        uint256 colAmount = perpsMarketProxy.getCollateralAmount(
            accountId,
            sUSDId
        );
        assertGt(colAmount, 4 ether);
        assertLt(colAmount, 5 ether);
    }

    function testPayFromWalletAndMargin() public {
        ops.push(userOp);

        mintUSDC(address(sender), 1 * 1e4); // send 0.01 USD to wallet
        mintUSDC(address(this), 1000 * 1e6);
        usdc.approve(sender, type(uint256).max);

        vm.prank(bundler);
        entryPoint.handleOps(ops, bundler);

        assertEq(usdc.balanceOf(address(this)), 995 * 1e6);
        assertEq(usdc.balanceOf(sender), 0);
        assertGt(usdc.balanceOf(marginPaymasterAddress), 0);
        uint256 colAmount = perpsMarketProxy.getCollateralAmount(
            account.accountId(),
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
            MockAccount.execute.selector,
            address(usdc),
            0,
            approvalCalldata
        );
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        bytes32 ethSignedMessage = ECDSA.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(backEndPk, ethSignedMessage);
        userOp.signature = bytes.concat(r, s, bytes1(v));

        ops.push(userOp);

        mintUSDC(sender, 1000 * 1e6);

        vm.prank(bundler);
        entryPoint.handleOps(ops, bundler);

        assertGt(usdc.allowance(sender, marginPaymasterAddress), 0);
        uint256 usdcLeftInWallet = usdc.balanceOf(sender);
        assertLt(usdcLeftInWallet, 1000 * 1e6);
        assertGt(usdcLeftInWallet, 0);
    }

    /*//////////////////////////////////////////////////////////////
                             ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                              TEST HELPERS
    //////////////////////////////////////////////////////////////*/

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
