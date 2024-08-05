// Licence - KGSL: Kwenta General Source License
pragma solidity 0.8.20;

import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {
    IPaymaster,
    UserOperation
} from "lib/account-abstraction/contracts/interfaces/IPaymaster.sol";
import {IPerpsMarketProxy} from "src/interfaces/external/IPerpsMarketProxy.sol";
import {IV3SwapRouter} from "src/interfaces/external/IV3SwapRouter.sol";
import {IWETH9} from "src/interfaces/external/IWETH9.sol";
import {Zap} from "lib/zap/src/Zap.sol";
import {OracleLibrary} from "src/libraries/OracleLibrary.sol";
import {IUniswapV3Pool} from "src/interfaces/external/IUniswapV3Pool.sol";
import {IERC20} from
    "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {INftModule} from "src/interfaces/external/INftModule.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title Kwenta Paymaster Contract
/// @notice Responsible for paying tx gas fees using trader margin
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
contract MarginPaymaster is IPaymaster, Zap, Ownable {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    EntryPoint public immutable entryPoint;
    IPerpsMarketProxy public immutable perpsMarketSNXV3;
    IV3SwapRouter public immutable uniV3Router;
    IWETH9 public immutable weth;
    IUniswapV3Pool public immutable pool;
    uint128 public constant sUSDId = 0;
    INftModule public immutable snxV3AccountsModule;
    uint24 constant POOL_FEE = 500; // 0.05%, top uni pool for USDC/WETH liquidity based on https://www.geckoterminal.com/base/uniswap-v3-base/pools
    bytes32 public constant PERPS_MODIFY_COLLATERAL_PERMISSION =
        "PERPS_MODIFY_COLLATERAL";
    uint32 public constant TWAP_PERIOD = 300; // 5 minutes
    uint256 public constant MAX_POST_OP_GAS_USEAGE = 520_072; // As last calculated
    uint256 public constant IS_AUTHORIZED = 0;
    uint256 public constant IS_NOT_AUTHORIZED = 1;
    uint256 public constant DEFAULT_WALLET_INDEX = 0;
    uint256 public constant USDC_TO_SUSDC_DECIMALS_INCREASE = 1e12;
    uint256 public constant SIGNATURE_BYTES_OFFSET = 20;
    uint256 public constant ACCOUNT_ID_BYTES_OFFSET = 85;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice authorizers are able to sign off-chain requests to use the paymaster
    mapping(address => bool) public authorizers;
    uint256 public percentageMarkup = 120; // 20% markup on gas costs

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted when the percentage markup is set by the owner
    /// @param newPercentageMarkup the new percentage markup
    event PercentageMarkupSet(uint256 newPercentageMarkup);

    /// @notice emitted when an authorizer status is set by the owner
    /// @param authorizer the address of the authorizer
    /// @param status the status of the authorizer
    event AuthorizerSet(address authorizer, bool status);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidEntryPoint();

    /// @notice thrown when the paymaster address provided in the userOp
    /// is not the address of this contract
    error InvalidPaymasterAddress();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _entryPoint,
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
        perpsMarketSNXV3 = IPerpsMarketProxy(_perpsMarketSNXV3);
        uniV3Router = IV3SwapRouter(_uniV3Router);
        weth = IWETH9(_weth);
        pool = IUniswapV3Pool(_pool);
        _USDC.approve(_uniV3Router, type(uint256).max);
        snxV3AccountsModule =
            INftModule(perpsMarketSNXV3.getAccountTokenAddress());
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

    /// @notice set the authorizer status
    /// @dev only the owner can set the authorizer status
    /// @param authorizer the address of the authorizer
    /// @param status the status of the authorizer
    function setAuthorizer(address authorizer, bool status)
        external
        onlyOwner
    {
        authorizers[authorizer] = status;
        emit AuthorizerSet(authorizer, status);
    }

    /// @notice return the hash we're going to sign off-chain (and validate on-chain)
    /// @notice this method is called by the off-chain service, to sign the request.
    /// @notice it is called on-chain from the validatePaymasterUserOp, to validate the signature.
    /// @dev this signature covers all fields of the UserOperation, except the "paymasterAndData"
    /// @dev "paymasterAndData" will carry the signature itself
    function getHash(UserOperation calldata userOp)
        public
        
        returns (bytes32)
    {   
        uint128 accountId;

        /// @dev userOp.hash() cannot be used because 
        /// it contains the paymasterAndData
        address paymasterAddress = address(
            bytes20(
                userOp.paymasterAndData[:SIGNATURE_BYTES_OFFSET]
            )
        );

        /// @dev the paymaster address specified in userOp
        /// must be the address of this contract
        if (paymasterAddress != address(this)) {
            revert InvalidPaymasterAddress();
        }
        
        /// @dev userOp data may optionally contain an accountId
        /// thus conditional logic sets it when present
        if (userOp.paymasterAndData.length > ACCOUNT_ID_BYTES_OFFSET) {
            accountId = uint128(
                bytes16(userOp.paymasterAndData[ACCOUNT_ID_BYTES_OFFSET:])
            );
        }

        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.callGasLimit,
                userOp.verificationGasLimit,
                userOp.preVerificationGas,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                paymasterAddress,
                accountId,
                block.chainid
            )
        );
    }

    /// @inheritdoc IPaymaster
    /// @notice We rely entirely on the back-end to decide which transactions should be sponsored
    /// @notice if the user has USDC available in their wallet or margin, we will use that
    /// @notice if they do not, the paymaster will pay
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32,
        uint256
    )
        external
        
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        bytes32 customUserOpHash = getHash(userOp);
        address recovered = ECDSA.recover(
            ECDSA.toEthSignedMessageHash(customUserOpHash),
            userOp.paymasterAndData[
                SIGNATURE_BYTES_OFFSET:ACCOUNT_ID_BYTES_OFFSET
            ]
        );
        bool isAuthorized = authorizers[recovered];
        validationData = isAuthorized ? IS_AUTHORIZED : IS_NOT_AUTHORIZED;
        bytes memory accountId =
            userOp.paymasterAndData[ACCOUNT_ID_BYTES_OFFSET:];
        context = abi.encode(
            userOp.sender,
            userOp.maxFeePerGas,
            userOp.maxPriorityFeePerGas,
            /// @custom:auditor // watch out, i hacked out this accountId logic at the last minute, could have made a mistake
            // the accountId field is optional, if it is not present we will take the first account appearing on-chain
            // if the accountId is invalid, we will again attempt to take the first account appearing on-chain
            // if it is set correctly, then margin will be pulled from specified accountId. This allows support for users with multiple snxv3 accounts
            uint128(bytes16(accountId))
        ); // passed to the postOp method
    }

    /*//////////////////////////////////////////////////////////////
                                POST OP
    //////////////////////////////////////////////////////////////*/

    /// @custom:auditor // please check carefully over this function, this is where most of the custom logic is
    /// @inheritdoc IPaymaster
    /// @notice attempt to pull funds from user's wallet, if insufficient, pull from margin
    /// @notice if insufficient margin, pull whatever is available
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCostInWei
    ) external onlyEntryPoint {
        /// @dev: if the mode is postOpReverted, this means the entry point contract already attempted
        /// to execute this postOp function and it reverted. This is the second call to postOp
        /// In this scenario we do not want to attempt to pull funds from the user's wallet
        /// Because clearly this caused a reversion in the last attempt. If we revert again, then the paymaster
        /// will be treated as DOSing the system and will be blacklisted by bundlers. Hence in this scenario
        /// we just return early, allowing the paymaster to subsidize the gas cost. It is worth noting that
        /// this scenario should never occur, but the check remains just in case.
        if (mode == PostOpMode.postOpReverted) return;

        (
            address sender,
            uint256 maxFeePerGas,
            uint256 maxPriorityFeePerGas,
            uint128 accountId
        ) = abi.decode(context, (address, uint256, uint256, uint128));

        uint256 gasPrice = getUserOpGasPrice(maxFeePerGas, maxPriorityFeePerGas);
        uint256 postOpCostInWei = MAX_POST_OP_GAS_USEAGE * gasPrice;
        uint256 costOfGasInUSDC =
            getCostOfGasInUSDC(actualGasCostInWei + postOpCostInWei);

        if (costOfGasInUSDC == 0) return;

        (uint256 availableUSDCInWallet,,) = getUSDCAvailableInWallet(sender);

        // draw funds from wallet before accessing margin
        if (availableUSDCInWallet >= costOfGasInUSDC) {
            // pull funds from wallet
            _USDC.transferFrom(sender, address(this), costOfGasInUSDC);
        } else {
            if (availableUSDCInWallet > 0) {
                // pull remaining USDC from wallet
                _USDC.transferFrom(sender, address(this), availableUSDCInWallet);
            }

            uint256 sUSDToWithdrawFromMargin = (
                costOfGasInUSDC - availableUSDCInWallet
            ) * USDC_TO_SUSDC_DECIMALS_INCREASE;
            uint256 withdrawn =
                withdrawFromMargin(sender, sUSDToWithdrawFromMargin, accountId);
            if (withdrawn > 0) {
                // zap sUSD into USDC
                _zapOut(withdrawn);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FUND MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice swap USDC -> WETH -> ETH
    /// @dev swaps entire USDC balance for ETH via Uniswap and WETH contract
    /// @dev only callable by the owner
    /// @param amountOutMinimum the minimum amount of ETH to receive
    function swapUSDCToETH(uint256 amountOutMinimum) external onlyOwner {
        uint256 amountIn = _USDC.balanceOf(address(this));

        // swap USDC for WETH via Uniswap v3 router
        uint256 amountOut = swapUSDCForWETH(amountIn, amountOutMinimum);

        // unwrap WETH to ETH via WETH contract
        weth.withdraw(amountOut);
    }

    function depositToEntryPoint(uint256 amount) external payable onlyOwner {
        entryPoint.depositTo{value: amount}(address(this));
    }

    function stake(uint256 amount, uint32 unstakeDelaySec) external onlyOwner {
        entryPoint.addStake{value: amount}(unstakeDelaySec);
    }

    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    function withdrawStake(address payable withdrawAddress)
        external
        onlyOwner
    {
        entryPoint.withdrawStake(withdrawAddress);
    }

    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount)
        external
        onlyOwner
    {
        entryPoint.withdrawTo(withdrawAddress, withdrawAmount);
    }

    function withdrawETH(address payable withdrawAddress, uint256 amount)
        external
        onlyOwner
    {
        withdrawAddress.call{value: amount}("");
    }

    function withdrawUSDC(address withdrawAddress, uint256 amount)
        external
        onlyOwner
    {
        _USDC.transfer(withdrawAddress, amount);
    }

    /// @notice set the percentage markup on gas costs
    /// @dev only the owner can set the percentage markup
    /// @param newPercentageMarkup the new percentage markup
    function setPercentageMarkup(uint256 newPercentageMarkup)
        external
        onlyOwner
    {
        percentageMarkup = newPercentageMarkup;
        emit PercentageMarkupSet(newPercentageMarkup);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice copied from the EntryPoint contract
    function getUserOpGasPrice(
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas
    ) internal view returns (uint256) {
        unchecked {
            if (maxFeePerGas == maxPriorityFeePerGas) {
                //legacy mode (for networks that don't support basefee opcode)
                return maxFeePerGas;
            }
            return min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
        }
    }

    function getCostOfGasInUSDC(uint256 gasCostInWei)
        internal
        view
        returns (uint256)
    {
        (int24 arithmeticMeanTick,) =
            OracleLibrary.consult(address(pool), TWAP_PERIOD);
        return (
            OracleLibrary.getQuoteAtTick(
                arithmeticMeanTick,
                uint128(gasCostInWei),
                address(weth),
                address(_USDC)
            ) * percentageMarkup
        ) / 100;
    }

    function getWalletAccountId(address wallet)
        internal
        view
        returns (uint128)
    {
        /// @dev: note, this impl assumes the user has only one account
        /// @dev: if you want to support multiple accounts, append the accountId
        /// @dev: field to the end of the userOp.paymasterAndData
        return uint128(
            snxV3AccountsModule.tokenOfOwnerByIndex(
                wallet, DEFAULT_WALLET_INDEX
            )
        );
    }

    /// @custom:auditor // please check PARTICULARLY carefully over this function, this is the most specific logic to us
    /// @custom:auditor // because we are pulling form SNXv3 margin (no one else is doing this in paymasters as far as we know)
    /// @custom:auditor // this function should NEVER revert, see if you can find a way to make it revert
    /// @notice withdraws sUSD from margin account
    /// @notice if insufficent margin, pulls out whatever is available
    /// @param sender the address of the users smart wallet
    /// @param sUSDToWithdrawFromMargin the amount of sUSD to withdraw from margin
    /// @param accountId the account Id of the user, if zero, we will attempt to find the actual ID onchain
    function withdrawFromMargin(
        address sender,
        uint256 sUSDToWithdrawFromMargin,
        uint128 accountId
    ) internal returns (uint256) {
        /// @custom:auditor // watch out for this accountId logic, i hacked it out quickly at the last minute
        /// @custom:auditor // previously it didn't support the BE defining an accountId in paymasterAndData
        /// @custom:auditor // it always just checked the first account on-chain, so take a closer look at this
        if (accountId != 0) {
            // check if the account Id is valid
            try snxV3AccountsModule.ownerOf(accountId) returns (address owner) {
                // only allow the owners accounts to subsidise gas
                if (owner != sender) accountId = 0;
            } catch {
                // set accountId to zero, and then check if the sender has an account on-chain
                accountId = 0;
            }
        }

        if (accountId == 0) {
            uint256 accountBalance = snxV3AccountsModule.balanceOf(sender);
            if (accountBalance == 0) return 0;

            accountId = getWalletAccountId(sender);
        }

        bool isAuthorized = perpsMarketSNXV3.isAuthorized(
            accountId, PERPS_MODIFY_COLLATERAL_PERMISSION, address(this)
        );

        if (!isAuthorized) return 0;

        int256 withdrawableMargin =
            perpsMarketSNXV3.getWithdrawableMargin(accountId);

        if (withdrawableMargin <= 0) return 0;
        uint256 withdrawableMarginUint = uint256(withdrawableMargin);

        uint256 amountToPullFromMargin =
            min(sUSDToWithdrawFromMargin, withdrawableMarginUint);

        // pull sUSD from margin
        perpsMarketSNXV3.modifyCollateral(
            accountId, sUSDId, -int256(amountToPullFromMargin)
        );

        return amountToPullFromMargin;
    }

    /// @notice swap USDC for WETH via Uniswap v3 router
    /// @param amountIn the amount of USDC to swap
    /// @param amountOutMinimum the minimum amount of WETH to receive
    /// @return the amount of WETH received
    function swapUSDCForWETH(uint256 amountIn, uint256 amountOutMinimum)
        internal
        returns (uint256)
    {
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

    function getUSDCAvailableInWallet(address wallet)
        internal
        view
        returns (uint256 availableUSDC, uint256 balance, uint256 allowance)
    {
        balance = _USDC.balanceOf(wallet);
        allowance = IERC20(address(_USDC)).allowance(wallet, address(this));
        availableUSDC = min(balance, allowance);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    receive() external payable {}
}
