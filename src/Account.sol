// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@account-abstraction/contracts/core/EntryPoint.sol";
import "@account-abstraction/contracts/interfaces/IAccount.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

contract Account is IAccount {
    uint256 public count;
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash, // userOpHash
        uint256 // missingAccountFunds
    ) external view returns (uint256 validationData) {
        address recovered = ECDSA.recover(
            ECDSA.toEthSignedMessageHash(userOpHash),
            userOp.signature
        );
        // if it returns 1 => invalid signature
        // if it returns 0 => valid signature
        return owner == recovered ? 0 : 1;
    }

    function execute() external {
        count++;
    }
}

contract AccountFactory {
    function createAccount(address owner) external returns (address) {
        // create2 is needed so it is deterministic and can have the gas useage confirmed by the bundler (disallowed opcodes)
        // amount, salt, bytecode
        bytes32 salt = bytes32(uint256(uint160(owner)));
        bytes memory bytecode = abi.encodePacked(
            type(Account).creationCode,
            abi.encode(owner)
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
