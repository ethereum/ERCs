// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @title IERCProtectedReceivePermit
 * @notice Optional EIP-712 one-time receive permit extension for `IERCProtectedReceiveCore`.
 * @dev Supports both ECDSA and ERC-1271 smart contract signatures with an unordered 256-bit
 *      nonce bitmap (`wordPos = uint248(nonce >> 8)`, `bitPos = uint8(nonce)`) so concurrent
 *      permits can settle in any order. All 2-address symbols follow `(from, to)` flow order.
 */
interface IERCProtectedReceivePermit {
    /**
     * @notice Emitted when a one-time receive permit is registered for a `(from, to)` pair.
     * @dev Overwrites any previous unconsumed one-time limit for `(from, to)`.
     * @param from The authorized sender (`address(0)` for mints).
     * @param to The protected recipient that signed the permit.
     * @param nonce The unordered bitmap nonce consumed by this registration.
     * @param maxAmount The maximum amount permitted for the next incoming transfer.
     * @param deadline The timestamp after which the signature is no longer valid.
     */
    event OneTimeReceivePermitted(
        address indexed from, address indexed to, uint256 indexed nonce, uint256 maxAmount, uint256 deadline
    );

    /**
     * @notice Reverted when `permitReceive` is called after the signature deadline.
     * @dev Checked against `block.timestamp > deadline`.
     * @param deadline The expired signature deadline timestamp.
     */
    error ExpiredReceivePermit(uint256 deadline);

    /**
     * @notice Reverted when a `permitReceive` signature does not validate for `to`.
     * @dev Covers both invalid ECDSA recovery and failed ERC-1271 `isValidSignature` checks.
     * @param recipient The expected signer / recipient account.
     */
    error InvalidReceivePermitSignature(address recipient);

    /**
     * @notice Reverted when a `permitReceive` nonce bit has already been used.
     * @dev Enforces single-use replay protection on the unordered 256-bit nonce bitmap.
     * @param recipient The recipient account.
     * @param nonce The already-used nonce value.
     */
    error InvalidReceiveNonce(address recipient, uint256 nonce);

    /**
     * @notice Returns the active one-time receive limit for `(from, to)`.
     * @dev Returns `0` when no one-time permit is active (or after it has been consumed).
     * @param from The authorized sender address.
     * @param to The protected recipient address.
     * @return The maximum amount allowed for the next single transfer.
     */
    function oneTimeReceiveLimit(address from, address to) external view returns (uint256);

    /**
     * @notice Returns whether an unordered `permitReceive` `nonce` has already been used for `account`.
     * @dev Implementations MAY store used nonces in a 256-bit bitmap, mapping, or other structure.
     * @param account The recipient account to query.
     * @param nonce The unordered nonce value to check.
     * @return True if `nonce` has been consumed for `account`, false otherwise.
     */
    function isReceiveNonceUsed(address account, uint256 nonce) external view returns (bool);

    /**
     * @notice Registers a one-time receive allowance for `from` to transfer up to `maxAmount` to `to`.
     * @dev Verifies an EIP-712 signature from `to` (or a designated signer) using ECDSA or ERC-1271,
     *      marks `nonce` as used so `isReceiveNonceUsed(to, nonce)` returns `true`, and emits
     *      {OneTimeReceivePermitted}.
     * @param from The authorized sender (`address(0)` for mints).
     * @param to The protected recipient signing the permit.
     * @param maxAmount Maximum amount allowed for the next transfer (`type(uint256).max` for unlimited).
     * @param nonce Unordered single-use nonce scoped to `to`.
     * @param deadline Unix timestamp after which the signature is invalid.
     * @param signature EIP-712 signature bytes (65-byte ECDSA or arbitrary-length ERC-1271).
     */
    function permitReceive(
        address from,
        address to,
        uint256 maxAmount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external;
}
