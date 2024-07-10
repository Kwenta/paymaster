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

    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32,
        uint256
    ) external returns (bytes memory context, uint256 validationData) {
        if (msg.sender != entryPoint) revert InvalidEntryPoint();
        context = abi.encode(userOp.sender); // passed to the postOp method
        validationData = 0; // 0 means accept sponsorship, 1 means reject
    }

    function postOp(
        PostOpMode,
        bytes calldata context,
        uint256 actualGasCostInWei
    ) external {
        if (msg.sender != entryPoint) revert InvalidEntryPoint();

        (, int24 tick, , , , , ) = IUniswapV3Pool(
            0xd0b53D9277642d899DF5C87A3966A349A798F224
        ).slot0();

        uint256 costOfGasInUSDC = OracleLibrary.getQuoteAtTick(
            tick, // int24 tick
            uint128(actualGasCostInWei), // uint128 baseAmount TODO: account for gas costs of postOp func
            address(weth), // address baseToken
            address(_USDC) // address quoteToken
        );
        uint256 costOfGasInsUSD = costOfGasInUSDC * 1e12;

        address sender = abi.decode(context, (address));
        uint128 accountId = Account(sender).accountId();
        // TODO: also support pulling USDC from the wallet directly
        perpsMarketSNXV3.modifyCollateral(
            accountId,
            sUSDId,
            -int256(costOfGasInsUSD)
        );
        uint256 usdcWithdrawn = _zapOut(costOfGasInsUSD);
        console.log("actualGasCostInWei", actualGasCostInWei); // 43381320000000 = 0.00004338132 ETH = 0.13 USD

        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter
            .ExactInputSingleParams({
                tokenIn: address(_USDC),
                tokenOut: address(weth),
                // note: aerdrome actually has higher liquidity https://www.geckoterminal.com/base/pools/0xb2cc224c1c9fee385f8ad6a55b4d94e92359dc59
                fee: 500, // 0.05%, top uni pool for USDC/WETH liquidity based on https://www.geckoterminal.com/base/uniswap-v3-base/pools
                recipient: address(this),
                // TODO: add on postOp cost
                amountIn: usdcWithdrawn,
                amountOutMinimum: 0, // change to: actualGasCostInWei
                sqrtPriceLimitX96: 0
            });
        uint256 amountOut = uniV3Router.exactInputSingle(params);
        weth.withdraw(amountOut);

        // // uint256 thing = OracleLibrary.checkFullMathMulDiv(100, 30, 3);
        // // console.log('thing :', thing);
        // uint256 quoteAmountA = OracleLibrary.getQuoteAtTick(
        //     tick, // int24 tick
        //     1 ether, // uint128 baseAmount
        //     0x4200000000000000000000000000000000000006, // address baseToken
        //     0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 // address quoteToken
        // );
        // console.log('quoteAmountA :', quoteAmountA); // this tells me how much USDC for 1 WETH
        // uint256 quoteAmountB = OracleLibrary.getQuoteAtTick(
        //     tick, // int24 tick
        //     1e6, // uint128 baseAmount
        //     0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // address baseToken
        //     0x4200000000000000000000000000000000000006 // address quoteToken
        // );
        // console.log('quoteAmountB :', quoteAmountB); // this tells me how much WETH for 1 USDC
    }

    receive() external payable {}
}
