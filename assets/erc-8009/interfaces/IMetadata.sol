// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.27;

/// @title BalanceMetadata struct used for UI-friendly calldata
/// @notice Passed as a first argument to router functions for easier off-chain decoding; ignored by contracts logic
struct BalanceMetadata {
    string symbol;
    uint8 decimals;
}
