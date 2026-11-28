// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @title IERCProtectedReceiveSig
 * @notice Optional EIP-712 signature-based protection management extension for `IERCProtectedReceiveCore`.
 * @dev Enables 0-ETH accounts (such as recipient-derived one-off addresses, counterfactual wallets,
 *      or cold storage) to enable, update, or disable receive protection via a relayer or atomically
 *      within the same transaction as an initial deposit (`1. transfer` -> `2. setReceiveProtectionWithSig`).
 */
interface IERCProtectedReceiveSig {
    /**
     * @notice Reverted when `setReceiveProtectionWithSig` is called after `deadline`.
     * @dev Checked against `block.timestamp > deadline`.
     * @param deadline The expired signature deadline timestamp.
     */
    error ExpiredReceiveProtectionSetupSignature(uint256 deadline);

    /**
     * @notice Reverted when a `setReceiveProtectionWithSig` signature does not validate for `account`.
     * @dev Covers both invalid ECDSA recovery and failed ERC-1271 `isValidSignature` checks.
     * @param account The expected signer account.
     */
    error InvalidReceiveProtectionSetupSignature(address account);

    /**
     * @notice Sets `protectionLevel` for `account` using an EIP-712 signature.
     * @dev Verifies an EIP-712 signature from `account` (ECDSA or ERC-1271), enforces
     *      single-use replay protection on an implementation-defined nonce, and updates `account`'s protection level.
     * @param account The account whose receive protection level is being updated.
     * @param protectionLevel The `bytes32` protection level (`bytes32(0)` disables protection).
     * @param deadline Unix timestamp after which the signature is invalid.
     * @param signature EIP-712 signature bytes (65-byte ECDSA or arbitrary-length ERC-1271).
     */
    function setReceiveProtectionWithSig(
        address account,
        bytes32 protectionLevel,
        uint256 deadline,
        bytes calldata signature
    ) external;
}
