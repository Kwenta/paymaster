// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IPaymaster, UserOperation} from "lib/account-abstraction/contracts/interfaces/IPaymaster.sol";

/// @title Kwenta Paymaster Contract
/// @notice Responsible for paying tx gas fees using trader margin
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
contract MarginPaymaster is IPaymaster {
    uint256 public number;

    function validatePaymasterUserOp(
        UserOperation calldata,
        bytes32,
        uint256
    ) external returns (bytes memory context, uint256 validationData) {}

    function postOp(PostOpMode, bytes calldata, uint256) external {}

    function increment() public {
        number++;
    }
}
