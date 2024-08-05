// Licence - KGSL: Kwenta General Source License
pragma solidity 0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from
    "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Zap} from "lib/zap/src/Zap.sol";
import {
    IPaymaster,
    UserOperation
} from "lib/account-abstraction/contracts/interfaces/IPaymaster.sol";
import {INftModule} from "src/interfaces/external/INftModule.sol";
import {IPerpsMarketProxy} from "src/interfaces/external/IPerpsMarketProxy.sol";
import {IUniswapV3Pool} from "src/interfaces/external/IUniswapV3Pool.sol";
import {IV3SwapRouter} from "src/interfaces/external/IV3SwapRouter.sol";
import {IWETH9} from "src/interfaces/external/IWETH9.sol";
import {OracleLibrary} from "src/libraries/OracleLibrary.sol";

/// @title Kwenta Paymaster Contract
/// @notice Manages gas sponsorship for Kwenta traders
/// @author tommyrharper (zeroknowledgeltd@gmail.com)
/// @author jaredborders (jared@kwenta.io)
contract MarginPaymaster is IPaymaster, Zap, Ownable {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice synthetix v3 sUSD token/synth Id
    uint128 public constant SUSD_ID = 0;

    /// @notice 0.05% uniswap v3 USDC/WETH pool fee tier
    /// @custom:link https://www.geckoterminal.com/base/uniswap-v3-base/pools
    uint24 public constant POOL_FEE = 500;

    /// @notice synthetix v3 RBAC permission required to modify collateral
    bytes32 public constant PERPS_MODIFY_COLLATERAL_PERMISSION =
        "PERPS_MODIFY_COLLATERAL";

    /// @notice seconds in the past from which to calculate the time-weighted means
    /// @dev see OracleLibrary
    uint32 public constant TWAP_PERIOD = 5 minutes;

    /// @notice the maximum gas usage for the postOp function
    /// @dev calculated on August 1st, 2024
    uint256 public constant MAX_POST_OP_GAS_USEAGE = 520_072;

    /// @notice assigned to validationData when the user is NOT authorized
    /// @dev see validatePaymasterUserOp()
    uint256 public constant IS_AUTHORIZED = 0;

    /// @notice assigned to validationData when the user is authorized
    /// @dev see validatePaymasterUserOp()
    uint256 public constant IS_NOT_AUTHORIZED = 1;

    /// @notice the index of the synthetx v3 account owned by the wallet
    uint256 public constant DEFAULT_WALLET_INDEX = 0;

    /// @notice the increase in decimals when converting USDC to sUSD
    uint256 public constant USDC_TO_SUSDC_DECIMALS_INCREASE = 1e12;

    /// @notice the offset of the signature bytes in the paymasterAndData field
    uint256 public constant SIGNATURE_BYTES_OFFSET = 20;

    /// @notice the offset of the account Id bytes in the paymasterAndData field
    uint256 public constant ACCOUNT_ID_BYTES_OFFSET = 85;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice account-abstraction (EIP-4337) singleton EntryPoint implementation
    EntryPoint public immutable entryPoint;

    /// @notice synthetix v3 perpetuals market proxy contract
    IPerpsMarketProxy public immutable snxv3PerpsMarket;

    /// @notice synthetix v3 NFT module contract
    /// @dev used to fetch NFT specific data from synthetix v3 account NFTs
    INftModule public immutable snxV3AccountsModule;

    /// @notice uniswap v3 swap router contract
    IV3SwapRouter public immutable uniV3Router;

    /// @notice uniswap v3 USDC/WETH pool contract
    IUniswapV3Pool public immutable univ3Pool;

    /// @notice wrapped ether contract
    IWETH9 public immutable weth;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice authorizers are able to sign off-chain requests to use the paymaster
    mapping(address => bool) public authorizers;

    /// @notice the percentage markup on gas costs
    /// @dev 100 = 100%, 120 = 120%
    uint256 public percentageMarkup = 120;

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

    /// @notice thrown when the entry point is not the caller
    error InvalidEntryPoint();

    /// @notice thrown when the paymaster address provided in the userOp
    /// is not the address of this contract
    error InvalidPaymasterAddress();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice MarginPaymaster constructor
    /// @dev Zap may revert if it's constructor parameters are incorrect
    /// @param _entryPoint address of the (EIP-4337) singleton EntryPoint
    /// @param _snxv3PerpsMarket address of the synthetix v3 perpetuals market proxy
    /// @param _usdc address of the USDC token
    /// @param _sUSDProxy address of the synthetix sUSD proxy
    /// @param _spotMarketProxy address of the synthetix v3 Spot Market proxy
    /// @param _sUSDCId the synthetix v3 sUSD token/synth Id
    /// @param _uniV3Router address of the uniswap v3 Swap Router
    /// @param _weth address of the wrapped ether contract
    /// @param _pool address of the uniswap v3 USDC/WETH Pool
    constructor(
        address _entryPoint,
        address _snxv3PerpsMarket,
        address _usdc,
        address _sUSDProxy,
        address _spotMarketProxy,
        uint128 _sUSDCId,
        address _uniV3Router,
        address _weth,
        address _pool
    ) Zap(_usdc, _sUSDProxy, _spotMarketProxy, _sUSDCId) {
        entryPoint = EntryPoint(payable(_entryPoint));
        snxv3PerpsMarket = IPerpsMarketProxy(_snxv3PerpsMarket);
        uniV3Router = IV3SwapRouter(_uniV3Router);
        weth = IWETH9(_weth);
        univ3Pool = IUniswapV3Pool(_pool);
        snxV3AccountsModule =
            INftModule(snxv3PerpsMarket.getAccountTokenAddress());

        // give unlimited USDC allowance to the uniswap v3 router
        _USDC.approve(_uniV3Router, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice verify the entry point is the caller
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

    /// @notice generate hash to sign and subsequently validate off-chain
    /// @notice called by the off-chain service to sign the request
    /// @notice called on-chain from the validatePaymasterUserOp to validate the signature
    /// @custom:caution signature covers ALL fields of the UserOperation, EXCEPT paymasterAndData
    /// @dev paymasterAndData will carry the signature itself
    /// @param userOp the UserOperation struct
    /// @return hash of the UserOperation struct
    function getHash(UserOperation calldata userOp)
        public
        view
        returns (bytes32)
    {
        uint128 accountId;

        /// @dev userOp.hash() cannot be used because
        /// it contains the paymasterAndData
        address paymasterAddress =
            address(bytes20(userOp.paymasterAndData[:SIGNATURE_BYTES_OFFSET]));

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

    /// @notice payment validation: check if paymaster agrees to pay
    /// @notice robust off-chain validation **is assumed** to have already occurred
    /// @notice USDC is debited from wallet; if insufficient, account margin is used
    /// @notice in the event of insufficient margin, paymaster will subsidize the gas cost
    /// @dev must verify sender is the entryPoint; revert to reject this request
    /// @dev validation code cannot use block.timestamp (or block.number)
    /// @param userOp the user operation
    /// @return context value to send to a postOp; zero length if postOp not required
    /// @return validationData signature and time-range of this operation,
    /// encoded the same as the return value of validateUserOperation:
    /// - <20-byte> sigAuthorizer:
    /// - - 0 for valid signature
    /// - - 1 to mark signature failure
    /// - - otherwise, an address of an authorizer contract
    /// - <6-byte> validUntil: last timestamp this operation is valid
    /// - - 0 for indefinite
    /// - <6-byte> validAfter: first timestamp this operation is valid
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32,
        uint256
    )
        external
        view
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
            uint128(bytes16(accountId))
        );
    }

    /*//////////////////////////////////////////////////////////////
                                POST OP
    //////////////////////////////////////////////////////////////*/

    /// @notice post-operation handler
    /// @dev USDC is debited from wallet; if insufficient, account margin is used
    /// @dev in the event of insufficient margin, paymaster will subsidize the gas cost
    /// @dev verify sender is the entryPoint
    /// @param mode enum with the following options:
    /// - `opSucceeded`: user operation succeeded
    /// - `opReverted`: user operation reverted -> still has to pay for gas
    /// - `postOpReverted`: user operation succeeded, but caused postOp (in mode=opSucceeded)
    ///   to revert; now this is the 2nd call, after user's operation was deliberately reverted
    /// @param context value returned by validatePaymasterUserOp
    /// @param actualGasCostInWei gas used so far (without this postOp call) in wei
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCostInWei
    ) external onlyEntryPoint {
        /// @dev If the mode is `postOpReverted`, this means the entry point contract
        /// already attempted to execute this postOp function and it reverted. Thus,
        /// this is the second call to postOp. In this scenario, we do not want to
        /// attempt to pull funds from the user's wallet because it caused a reversion
        /// in the last attempt. If we revert again, then the paymaster will be treated
        /// as DOSing the system and will be *blacklisted* by bundlers. Hence, in this
        /// scenario, we just return early, allowing the paymaster to subsidize the gas
        /// cost. It is worth noting that this scenario *should never occur*, but the
        /// check remains just in case.
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

        // prioritize pulling USDC from wallet
        if (availableUSDCInWallet >= costOfGasInUSDC) {
            _USDC.transferFrom(sender, address(this), costOfGasInUSDC);
        } else {
            // pull whatever is available from the wallet prior to margin
            if (availableUSDCInWallet > 0) {
                _USDC.transferFrom(sender, address(this), availableUSDCInWallet);
            }

            // determine the amount of sUSD to withdraw from margin
            uint256 sUSDToWithdrawFromMargin = (
                costOfGasInUSDC - availableUSDCInWallet
            ) * USDC_TO_SUSDC_DECIMALS_INCREASE;

            // withdraw sUSD from margin; if insufficient, pull whatever is available
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
    /// @dev swaps entire USDC balance for ETH via uniswap and WETH contract
    /// @dev only callable by the owner
    /// @param amountOutMinimum the minimum amount of ETH to receive
    function swapUSDCToETH(uint256 amountOutMinimum) external onlyOwner {
        uint256 amountIn = _USDC.balanceOf(address(this));

        // swap USDC for WETH via uniswap v3 router
        uint256 amountOut = swapUSDCForWETH(amountIn, amountOutMinimum);

        // unwrap WETH to ETH via WETH contract
        weth.withdraw(amountOut);
    }

    /// @notice deposit ETH into the entry point
    /// @dev only callable by the owner
    /// @param amount the amount of ETH to deposit
    function depositToEntryPoint(uint256 amount) external payable onlyOwner {
        entryPoint.depositTo{value: amount}(address(this));
    }

    /// @notice stake ETH in the entry point
    /// @dev only callable by the owner
    /// @param amount the amount of ETH to stake
    /// @param unstakeDelaySec the delay in seconds before the stake can be withdrawn
    function stake(uint256 amount, uint32 unstakeDelaySec) external onlyOwner {
        entryPoint.addStake{value: amount}(unstakeDelaySec);
    }

    /// @notice unlock the staked ETH in the entry point
    /// @dev only callable by the owner
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /// @notice withdraw staked ETH from the entry point
    /// @dev only callable by the owner
    /// @param withdrawAddress the address to withdraw the staked ETH to
    function withdrawStake(address payable withdrawAddress)
        external
        onlyOwner
    {
        entryPoint.withdrawStake(withdrawAddress);
    }

    /// @notice withdraw ETH from the entry point
    /// @dev only callable by the owner
    /// @param withdrawAddress the address to withdraw the ETH to
    /// @param withdrawAmount the amount of ETH to withdraw
    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount)
        external
        onlyOwner
    {
        entryPoint.withdrawTo(withdrawAddress, withdrawAmount);
    }

    /// @notice withdraw ETH from the contract
    /// @dev only callable by the owner
    /// @param withdrawAddress the address to withdraw the ETH to
    /// @param amount the amount of ETH to withdraw
    function withdrawETH(address payable withdrawAddress, uint256 amount)
        external
        onlyOwner
    {
        withdrawAddress.call{value: amount}("");
    }

    /// @notice withdraw USDC from the contract
    /// @dev only callable by the owner
    /// @param withdrawAddress the address to withdraw the USDC to
    /// @param amount the amount of USDC to withdraw
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
    /// @dev determine the gas price this UserOp agrees to pay
    /// @dev relayer/block builder may submit the tx with higher priorityFee,
    /// but the user should not
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

    /// @notice get the cost of gas in USDC
    /// @param gasCostInWei the cost of gas in Wei
    /// @return the cost of gas in USDC
    function getCostOfGasInUSDC(uint256 gasCostInWei)
        internal
        view
        returns (uint256)
    {
        (int24 arithmeticMeanTick,) =
            OracleLibrary.consult(address(univ3Pool), TWAP_PERIOD);
        return (
            OracleLibrary.getQuoteAtTick(
                arithmeticMeanTick,
                uint128(gasCostInWei),
                address(weth),
                address(_USDC)
            ) * percentageMarkup
        ) / 100;
    }

    /// @notice get the synthetix v3 account Id of which the wallet owns
    /// @param wallet the address of the users smart wallet
    /// @return synthetix v3 account Id
    function getWalletAccountId(address wallet)
        internal
        view
        returns (uint128)
    {
        /// @dev the following logic assumes the user has only one account
        /// @dev append the accountId to the userOp.paymasterAndData
        /// to support multiple accounts
        return uint128(
            snxV3AccountsModule.tokenOfOwnerByIndex(
                wallet, DEFAULT_WALLET_INDEX
            )
        );
    }

    /// @notice withdraws sUSD from margin account
    /// @notice if insufficent margin, pulls out whatever is available
    /// @param sender the address of the users smart wallet
    /// @param sUSDToWithdrawFromMargin the amount of sUSD to withdraw from margin
    /// @param accountId the account Id of the user, if zero, attempt to find ID onchain
    function withdrawFromMargin(
        address sender,
        uint256 sUSDToWithdrawFromMargin,
        uint128 accountId
    ) internal returns (uint256) {
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

        bool isAuthorized = snxv3PerpsMarket.isAuthorized(
            accountId, PERPS_MODIFY_COLLATERAL_PERMISSION, address(this)
        );

        if (!isAuthorized) return 0;

        int256 withdrawableMargin =
            snxv3PerpsMarket.getWithdrawableMargin(accountId);

        if (withdrawableMargin <= 0) return 0;
        uint256 withdrawableMarginUint = uint256(withdrawableMargin);

        uint256 amountToPullFromMargin =
            min(sUSDToWithdrawFromMargin, withdrawableMarginUint);

        // pull sUSD from margin
        snxv3PerpsMarket.modifyCollateral(
            accountId, SUSD_ID, -int256(amountToPullFromMargin)
        );

        return amountToPullFromMargin;
    }

    /// @notice swap USDC for WETH via uniswap v3 router
    /// @param amountIn the amount of USDC to swap
    /// @param amountOutMinimum the minimum amount of WETH to receive
    /// @return amount of WETH received
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

    /// @notice get the available USDC in the wallet
    /// @param wallet the address of the users smart wallet
    /// @return availableUSDC the available USDC in the wallet
    /// @return balance the USDC balance of the wallet
    /// @return allowance the USDC allowance of the wallet
    function getUSDCAvailableInWallet(address wallet)
        internal
        view
        returns (uint256 availableUSDC, uint256 balance, uint256 allowance)
    {
        balance = _USDC.balanceOf(wallet);
        allowance = IERC20(address(_USDC)).allowance(wallet, address(this));
        availableUSDC = min(balance, allowance);
    }

    /*//////////////////////////////////////////////////////////////
                                  MATH
    //////////////////////////////////////////////////////////////*/

    /// @notice get the minimum of two numbers
    /// @dev if a == b, b is returned
    /// @param a the first number
    /// @param b the second number
    /// @return the minimum of the two numbers
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /*//////////////////////////////////////////////////////////////
                                PAYABLE
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
