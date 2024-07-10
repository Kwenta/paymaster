// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IPaymaster, UserOperation} from "lib/account-abstraction/contracts/interfaces/IPaymaster.sol";
import {IPerpsMarketProxy} from "src/interfaces/external/IPerpsMarketProxy.sol";
import {IV3SwapRouter} from "src/interfaces/external/IV3SwapRouter.sol";
import {IWETH9} from "src/interfaces/external/IWETH9.sol";
import {IEngine} from "src/interfaces/IEngine.sol";
import {Account} from "src/Account.sol";
import {Zap} from "lib/zap/src/Zap.sol";
import {OracleLibrary} from "src/libraries/OracleLibrary.sol";
import {IUniswapV3Pool} from "src/interfaces/external/IUniswapV3Pool.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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
    IUniswapV3Pool public immutable pool;
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
        address _weth,
        address _pool
    ) Zap(_usdc, _sUSDProxy, _spotMarketProxy, _sUSDCId) {
        entryPoint = _entryPoint;
        smartMarginV3 = IEngine(_smartMarginV3);
        perpsMarketSNXV3 = IPerpsMarketProxy(_perpsMarketSNXV3);
        uniV3Router = IV3SwapRouter(_uniV3Router);
        weth = IWETH9(_weth);
        pool = IUniswapV3Pool(_pool);
        _USDC.approve(_uniV3Router, type(uint256).max);
    }

    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint) revert InvalidEntryPoint();
        _;
    }

    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32,
        uint256
    )
        external
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        context = abi.encode(userOp.sender); // passed to the postOp method
        validationData = 0; // 0 means accept sponsorship, 1 means reject
    }

    function postOp(
        PostOpMode,
        bytes calldata context,
        uint256 actualGasCostInWei
    ) external onlyEntryPoint {
        (, int24 tick, , , , , ) = pool.slot0();

        uint256 costOfGasInUSDC = (OracleLibrary.getQuoteAtTick(
            tick,
            uint128(actualGasCostInWei), // TODO: account for gas costs of postOp func
            address(weth),
            address(_USDC)
        ) * 110) / 100; // 10% slippage

        address sender = abi.decode(context, (address));

        uint256 walletBalance = _USDC.balanceOf(sender);
        uint256 allowance = IERC20(address(_USDC)).allowance(
            sender,
            address(this)
        );

        if (walletBalance >= costOfGasInUSDC && allowance >= costOfGasInUSDC) {
            // pull funds from wallet
            _USDC.transferFrom(sender, address(this), costOfGasInUSDC);
        } else {
            // pull funds from margin
            uint256 costOfGasInsUSD = costOfGasInUSDC * 1e12;
            uint128 accountId = Account(sender).accountId();
            // TODO: also support pulling USDC from the wallet directly
            perpsMarketSNXV3.modifyCollateral(
                accountId,
                sUSDId,
                -int256(costOfGasInsUSD)
            );
            costOfGasInUSDC = _zapOut(costOfGasInsUSD);
        }

        console.log("actualGasCostInWei", actualGasCostInWei); // 43350920000000 = 0.00004335092 ETH = 0.13 USD

        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter
            .ExactInputSingleParams({
                tokenIn: address(_USDC),
                tokenOut: address(weth),
                fee: 500, // 0.05%, top uni pool for USDC/WETH liquidity based on https://www.geckoterminal.com/base/uniswap-v3-base/pools
                recipient: address(this),
                amountIn: costOfGasInUSDC,
                amountOutMinimum: actualGasCostInWei, // TODO: should this be required? -> could cause failures
                sqrtPriceLimitX96: 0
            });
        uint256 amountOut = uniV3Router.exactInputSingle(params);
        weth.withdraw(amountOut);
    }

    receive() external payable {}
}
