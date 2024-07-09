// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@account-abstraction/contracts/core/EntryPoint.sol";
import "@account-abstraction/contracts/interfaces/IAccount.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import {IERC721Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {IPerpsMarketProxy} from "src/interfaces/synthetix/IPerpsMarketProxy.sol";
import {IEngine} from "src/interfaces/IEngine.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Zap} from "lib/zap/src/Zap.sol";
import {console} from "forge-std/console.sol";

contract Account is IAccount, IERC721Receiver {
    uint256 public count;
    address public owner;
    IPerpsMarketProxy public perpsMarketSNXV3;
    address public marginPaymaster;
    IEngine public smartMarginV3;
    IERC20 public usdc;
    uint128 public accountId;
    bytes32 internal constant ADMIN_PERMISSION = "ADMIN";
    uint256 public constant USDC_DECIMALS = 6;

    constructor(
        address _owner,
        address _perpsMarketSNXV3,
        address _marginPaymaster,
        address _smartMarginV3,
        address _usdc
    ) {
        owner = _owner;
        perpsMarketSNXV3 = IPerpsMarketProxy(_perpsMarketSNXV3);
        marginPaymaster = _marginPaymaster;
        smartMarginV3 = IEngine(_smartMarginV3);
        usdc = IERC20(_usdc);
    }

    function setupAccount() external {
        accountId = perpsMarketSNXV3.createAccount();
        perpsMarketSNXV3.grantPermission({
            accountId: accountId,
            permission: ADMIN_PERMISSION,
            user: marginPaymaster
        });
        perpsMarketSNXV3.grantPermission({
            accountId: accountId,
            permission: ADMIN_PERMISSION,
            user: address(smartMarginV3)
        });
        int256 minDeposit = int256(5 * 10 ** USDC_DECIMALS);
        usdc.transferFrom(owner, address(this), uint256(minDeposit));
        usdc.approve(address(smartMarginV3), uint256(minDeposit));
        smartMarginV3.modifyCollateralZap(accountId, minDeposit);
    }

    function validateUserOp(
        UserOperation calldata, // userOp
        bytes32, // userOpHash
        uint256 // missingAccountFunds
    ) external pure returns (uint256 validationData) {
        // address recovered = ECDSA.recover(
        //     ECDSA.toEthSignedMessageHash(userOpHash),
        //     userOp.signature
        // );
        // // if it returns 1 => invalid signature
        // // if it returns 0 => valid signature
        // return owner == recovered ? 0 : 1;
        return 0;
    }

    function execute() external {
        count++;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract AccountFactory {
    address public perpsMarketSNXV3;
    address public marginPaymaster;
    address public smartMarginV3;
    address public usdc;

    constructor(
        address _perpsMarketSNXV3,
        address _marginPaymaster,
        address _smartMarginV3,
        address _usdc
    ) {
        perpsMarketSNXV3 = _perpsMarketSNXV3;
        marginPaymaster = _marginPaymaster;
        smartMarginV3 = _smartMarginV3;
        usdc = _usdc;
    }

    function createAccount(address owner) external returns (address) {
        // create2 is needed so it is deterministic and can have the gas useage confirmed by the bundler (disallowed opcodes)
        // amount, salt, bytecode
        bytes32 salt = bytes32(uint256(uint160(owner)));
        bytes memory bytecode = abi.encodePacked(
            type(Account).creationCode,
            abi.encode(
                owner,
                perpsMarketSNXV3,
                marginPaymaster,
                smartMarginV3,
                usdc
            )
        );

        // dont deploy if addr already exists
        address addr = Create2.computeAddress(salt, keccak256(bytecode));
        if (addr.code.length > 0) {
            return addr;
        }

        // cannot use Create2.deploy because it uses SELFBALANCE which is not allowed by the bundler
        // return Create2.deploy(0, salt,bytecode);
        return deploy(salt, bytecode);
    }

    function deploy(
        bytes32 salt,
        bytes memory bytecode
    ) internal returns (address) {
        address addr;
        require(bytecode.length != 0, "Create2: bytecode length is zero");
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "Create2: Failed on deploy");
        return addr;
    }
}
