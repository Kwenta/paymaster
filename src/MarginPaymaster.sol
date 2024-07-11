// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {IPaymaster, UserOperation} from "lib/account-abstraction/contracts/interfaces/IPaymaster.sol";
import {IPerpsMarketProxy} from "src/interfaces/external/IPerpsMarketProxy.sol";
import {IV3SwapRouter} from "src/interfaces/external/IV3SwapRouter.sol";
import {IWETH9} from "src/interfaces/external/IWETH9.sol";
import {IEngine} from "src/interfaces/IEngine.sol";
import {MockAccount} from "src/MockAccount.sol";
import {Zap} from "lib/zap/src/Zap.sol";
import {OracleLibrary} from "src/libraries/OracleLibrary.sol";
import {IUniswapV3Pool} from "src/interfaces/external/IUniswapV3Pool.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {INftModule} from "src/interfaces/external/INftModule.sol";
import {MockAccount} from "src/MockAccount.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

import {console} from "forge-std/console.sol";

/// @title Kwenta Paymaster Contract
/// @notice Responsible for paying tx gas fees using trader margin
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
contract MarginPaymaster is IPaymaster, Zap, Ownable {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    EntryPoint public immutable entryPoint;
    IEngine public immutable smartMarginV3;
    IPerpsMarketProxy public immutable perpsMarketSNXV3;
    IV3SwapRouter public immutable uniV3Router;
    IWETH9 public immutable weth;
    IUniswapV3Pool public immutable pool;
    uint128 public constant sUSDId = 0;
    INftModule public immutable snxV3AccountsModule;
    uint24 constant POOL_FEE = 500; // 0.05%, top uni pool for USDC/WETH liquidity based on https://www.geckoterminal.com/base/uniswap-v3-base/pools

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    mapping(address => bool) public authorizers;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidEntryPoint();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

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
        entryPoint = EntryPoint(payable(_entryPoint));
        smartMarginV3 = IEngine(_smartMarginV3);
        perpsMarketSNXV3 = IPerpsMarketProxy(_perpsMarketSNXV3);
        uniV3Router = IV3SwapRouter(_uniV3Router);
        weth = IWETH9(_weth);
        pool = IUniswapV3Pool(_pool);
        _USDC.approve(_uniV3Router, type(uint256).max);
        snxV3AccountsModule = INftModule(
            perpsMarketSNXV3.getAccountTokenAddress()
        );
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyEntryPoint() {
        if (msg.sender != address(entryPoint)) revert InvalidEntryPoint();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               VALIDATION
    //////////////////////////////////////////////////////////////*/

    function setAuthorizer(address authorizer, bool status) external onlyOwner {
        authorizers[authorizer] = status;
    }

    /// @notice We rely entirely on the back-end to decide which transactions should be sponsored
    /// @notice if the user has USDC available in their wallet or margin, we will use that
    /// @notice if they do not, the paymaster will pay
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256
    )
        external
        view
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        address recovered = ECDSA.recover(
            ECDSA.toEthSignedMessageHash(userOpHash),
            userOp.signature
        );
        bool isAuthorized = authorizers[recovered];
        validationData = isAuthorized ? 0 : 1;
        context = abi.encode(userOp.sender); // passed to the postOp method
    }

    /*//////////////////////////////////////////////////////////////
                                POST OP
    //////////////////////////////////////////////////////////////*/

    /// @notice attempt to pull funds from user's wallet, if insufficient, pull from margin
    /// @notice if insufficient margin, pull whatever is available
    function postOp(
        PostOpMode,
        bytes calldata context,
        uint256 actualGasCostInWei
    ) external onlyEntryPoint {
        uint256 costOfGasInUSDC = getCostOfGasInUSDC(actualGasCostInWei); // TODO: account for gas costs of postOp func
        address sender = abi.decode(context, (address));
        (uint256 availableUSDCInWallet, , ) = getUSDCAvailableInWallet(sender);

        // draw funds from wallet before accessing margin
        if (availableUSDCInWallet >= costOfGasInUSDC) {
            // pull funds from wallet
            _USDC.transferFrom(sender, address(this), costOfGasInUSDC);
        } else {
            if (availableUSDCInWallet > 0) {
                // pull remaining USDC from wallet
                _USDC.transferFrom(
                    sender,
                    address(this),
                    availableUSDCInWallet
                );
            }

            uint256 sUSDToWithdrawFromMargin = (costOfGasInUSDC -
                availableUSDCInWallet) * 1e12;
            // TODO: handle users who don't have an snx account or margin or enough margin
            uint256 withdrawn = withdrawFromMargin(
                sender,
                sUSDToWithdrawFromMargin
            );
            // zap sUSD into USDC
            _zapOut(withdrawn);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FUND MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function swapUSDCToETH(uint256 amountOutMinimum) external onlyOwner {
        uint256 amountIn = _USDC.balanceOf(address(this));
        // swap USDC for WETH
        uint256 amountOut = swapUSDCForWETH(amountIn, amountOutMinimum);
        // unwrap WETH to ETH
        weth.withdraw(amountOut);
    }

    function depositToEntryPoint(uint256 amount) external onlyOwner {
        entryPoint.depositTo{value: amount}(address(this));
    }

    function stake(uint256 amount, uint32 unstakeDelaySec) external onlyOwner {
        entryPoint.addStake{value: amount}(unstakeDelaySec);
    }

    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
    }

    function withdrawTo(
        address payable withdrawAddress,
        uint256 withdrawAmount
    ) external onlyOwner {
        entryPoint.withdrawTo(withdrawAddress, withdrawAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function getCostOfGasInUSDC(
        uint256 gasCostInWei
    ) internal view returns (uint256) {
        // TODO: use arithmeticMeanTick
        // (int24 arithmeticMeanTick, ) = OracleLibrary.consult(pool, secondsAgo);
        (, int24 tick, , , , , ) = pool.slot0();
        return
            (OracleLibrary.getQuoteAtTick(
                tick,
                uint128(gasCostInWei),
                address(weth),
                address(_USDC)
            ) * 110) / 100; // allow for 10% slippage TODO: think more carefully about this
    }

    function getWalletAccountId(
        address wallet
    ) internal view returns (uint128) {
        /// @dev: note, this impl assumes the user has only one account
        /// @dev: further development efforts would be required to support multiple accounts
        return uint128(snxV3AccountsModule.tokenOfOwnerByIndex(wallet, 0));
    }

    /// @notice withdraws sUSD from margin account
    /// @notice if insufficent margin, pulls out whatever is available
    function withdrawFromMargin(
        address sender,
        uint256 sUSDToWithdrawFromMargin
    ) internal returns (uint256) {
        uint128 accountId = getWalletAccountId(sender);
        int256 withdrawableMargin = perpsMarketSNXV3.getWithdrawableMargin(
            accountId
        );

        if (withdrawableMargin < 0) return 0;
        uint256 withdrawableMarginUint = uint256(withdrawableMargin);

        uint256 amountToPullFromMargin = sUSDToWithdrawFromMargin <
            withdrawableMarginUint
            ? sUSDToWithdrawFromMargin
            : withdrawableMarginUint;

        // pull sUSD from margin
        perpsMarketSNXV3.modifyCollateral(
            accountId,
            sUSDId,
            -int256(amountToPullFromMargin)
        );

        return amountToPullFromMargin;
    }

    function swapUSDCForWETH(
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal returns (uint256) {
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter
            .ExactInputSingleParams({
                tokenIn: address(_USDC),
                tokenOut: address(weth),
                fee: POOL_FEE,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });
        return uniV3Router.exactInputSingle(params);
    }

    function getUSDCAvailableInWallet(
        address wallet
    )
        internal
        view
        returns (uint256 availableUSDC, uint256 balance, uint256 allowance)
    {
        balance = _USDC.balanceOf(wallet);
        allowance = IERC20(address(_USDC)).allowance(wallet, address(this));
        availableUSDC = allowance < balance ? allowance : balance;
    }

    receive() external payable {}
}
