// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IPaymaster, UserOperation} from "lib/account-abstraction/contracts/interfaces/IPaymaster.sol";
import {IPerpsMarketProxy} from "src/interfaces/external/IPerpsMarketProxy.sol";
import {IV3SwapRouter} from "src/interfaces/external/IV3SwapRouter.sol";
import {IWETH9} from "src/interfaces/external/IWETH9.sol";
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
    IV3SwapRouter public immutable uniV3Router;
    IWETH9 public immutable weth;
    uint128 public constant sUSDId = 0;

    error InvalidEntryPoint();

    constructor(
        address _entryPoint,
        address _smartMarginV3,
        address _perpsMarketSNXV3,
        address _usdc,
        address _sUSDProxy,
        address _spotMarketProxy,
        uint128 _sUSDCId,
        address _uniV3Router,
        address _weth
    ) Zap(_usdc, _sUSDProxy, _spotMarketProxy, _sUSDCId) {
        entryPoint = _entryPoint;
        smartMarginV3 = IEngine(_smartMarginV3);
        perpsMarketSNXV3 = IPerpsMarketProxy(_perpsMarketSNXV3);
        uniV3Router = IV3SwapRouter(_uniV3Router);
        weth = IWETH9(_weth);
        _USDC.approve(_uniV3Router, type(uint256).max);
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

    function postOp(PostOpMode, bytes calldata context, uint256 actualGasCost) external {
        if (msg.sender != entryPoint) revert InvalidEntryPoint();
        address sender = abi.decode(context, (address));
        uint128 accountId = Account(sender).accountId();
        int256 take = -4 ether;
        perpsMarketSNXV3.modifyCollateral(accountId, sUSDId, take);
        uint256 takeAbs = uint256(take*-1);
        uint256 usdcAmount = _zapOut(takeAbs);
        console.log("actualGasCost", actualGasCost); // 21690660000000000 = 0.02169 ETH

        IV3SwapRouter.ExactOutputSingleParams memory params = IV3SwapRouter.ExactOutputSingleParams({
            tokenIn: address(_USDC),
            tokenOut: address(weth),
            // note: aerdrome actually has higher liquidity https://www.geckoterminal.com/base/pools/0xb2cc224c1c9fee385f8ad6a55b4d94e92359dc59
            fee: 500, // 0.05%, top uni pool for USDC/WETH liquidity based on https://www.geckoterminal.com/base/uniswap-v3-base/pools
            recipient: address(this),
            // amountOut: actualGasCost,
            amountOut: 10,
            amountInMaximum: usdcAmount,
            sqrtPriceLimitX96: 0
        });
        uniV3Router.exactOutputSingle(params);
    }
}
