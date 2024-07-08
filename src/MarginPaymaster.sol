// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IPaymaster, UserOperation} from "lib/account-abstraction/contracts/interfaces/IPaymaster.sol";
import {console} from "forge-std/console.sol";

/// @title Kwenta Paymaster Contract
/// @notice Responsible for paying tx gas fees using trader margin
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
contract MarginPaymaster is IPaymaster {
    function validatePaymasterUserOp(
        UserOperation calldata,
        bytes32,
        uint256
    ) external returns (bytes memory context, uint256 validationData) {
        // todo:
        // assert(msg.sender == entryPoint)
        console.log("validatePaymasterUserOp");
        // context = new bytes(0); // passed to the postOp method
        context = "yo"; // passed to the postOp method
        validationData = 0; // special value means no validation
    }

    function postOp(PostOpMode, bytes calldata, uint256) external {
        // assert(msg.sender == entryPoint)
        console.log("postOp");
    }
}
