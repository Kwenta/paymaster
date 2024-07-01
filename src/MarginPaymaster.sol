// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

/// @title Kwenta Paymaster Contract
/// @notice Responsible for paying tx gas fees using trader margin
/// @author tommyrharper (zeroknowledge@gmail.com)
contract MarginPaymaster {
    uint256 public number;

    function increment() public {
        number++;
    }
}
