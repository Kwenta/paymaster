// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IPaymaster, UserOperation} from "lib/account-abstraction/contracts/interfaces/IPaymaster.sol";
import {IPerpsMarketProxy} from "src/interfaces/synthetix/IPerpsMarketProxy.sol";
import {IEngine} from "src/interfaces/IEngine.sol";

import {console} from "forge-std/console.sol";

/// @title Kwenta Paymaster Contract
/// @notice Responsible for paying tx gas fees using trader margin
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
contract MarginPaymaster is IPaymaster {
    address public immutable entryPoint;
    IEngine public immutable smartMarginV3;
    IPerpsMarketProxy public immutable perpsMarketSNXV3;

    error InvalidEntryPoint();

    constructor(
        address _entryPoint,
        address _smartMarginV3,
        address _perpsMarketSNXV3
    ) {
        entryPoint = _entryPoint;
        smartMarginV3 = IEngine(_smartMarginV3);
        perpsMarketSNXV3 = IPerpsMarketProxy(_perpsMarketSNXV3);
    }

    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32,
        uint256
    ) external returns (bytes memory context, uint256 validationData) {
        if (msg.sender != entryPoint) revert InvalidEntryPoint();
        console.log("validatePaymasterUserOp");
        // context = new bytes(0); // passed to the postOp method
        context = abi.encode(userOp.sender); // passed to the postOp method
        validationData = 0; // special value means no validation
    }

    function postOp(PostOpMode, bytes calldata context, uint256) external {
        if (msg.sender != entryPoint) revert InvalidEntryPoint();
        address sender = abi.decode(context, (address));
        console.log("postOp", sender);
    }
}
