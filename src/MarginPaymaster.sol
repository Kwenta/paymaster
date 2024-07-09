// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IPaymaster, UserOperation} from "lib/account-abstraction/contracts/interfaces/IPaymaster.sol";
import {IPerpsMarketProxy} from "src/interfaces/synthetix/IPerpsMarketProxy.sol";
import {IEngine} from "src/interfaces/IEngine.sol";
import {Account} from "src/Account.sol";
import {Zap} from "lib/zap/src/Zap.sol";

import {console} from "forge-std/console.sol";

/// @title Kwenta Paymaster Contract
/// @notice Responsible for paying tx gas fees using trader margin
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
contract MarginPaymaster is IPaymaster, Zap {
    address public immutable entryPoint;
    IEngine public immutable smartMarginV3;
    IPerpsMarketProxy public immutable perpsMarketSNXV3;
    uint128 public constant sUSDId = 0;

    error InvalidEntryPoint();

    constructor(
        address _entryPoint,
        address _smartMarginV3,
        address _perpsMarketSNXV3,
        address _usdc,
        address _sUSDProxy,
        address _spotMarketProxy,
        uint128 _sUSDCId
    ) Zap(_usdc, _sUSDProxy, _spotMarketProxy, _sUSDCId) {
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
        context = abi.encode(userOp.sender); // passed to the postOp method
        validationData = 0; // 0 means accept sponsorship, 1 means reject
    }

    function postOp(PostOpMode, bytes calldata context, uint256) external {
        if (msg.sender != entryPoint) revert InvalidEntryPoint();
        address sender = abi.decode(context, (address));
        uint128 accountId = Account(sender).accountId();
        int256 take = -1 ether;
        perpsMarketSNXV3.modifyCollateral(accountId, sUSDId, take);
    }
}
