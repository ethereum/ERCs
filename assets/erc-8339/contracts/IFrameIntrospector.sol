// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

/// @title IFrameIntrospector: read-only view of the current EIP-8141 frame transaction.
/// @notice Solidity cannot emit the EIP-8141 introspection opcodes (TXPARAM, FRAMEPARAM,
///         FRAMEDATACOPY), so a tiny Yul contract exposes them behind this ABI. The opcodes
///         are transaction-scoped, so a STATICCALL into the introspector sees the same
///         frames as its caller. Every function halts outside a frame transaction.
interface IFrameIntrospector {
    /// @notice TXPARAM(CURRENT_FRAME_INDEX): index of the frame currently executing.
    function currentFrameIndex() external view returns (uint256);

    /// @notice TXPARAM(SENDER): the frame transaction's `sender`.
    function txSender() external view returns (address);

    /// @notice FRAMEPARAM(i, MODE): 0 DEFAULT, 1 VERIFY, 2 SENDER.
    function frameMode(uint256 i) external view returns (uint256);

    /// @notice FRAMEPARAM(i, FLAGS): bits 0-1 approval scope, bit 2 ATOMIC_BATCH.
    function frameFlags(uint256 i) external view returns (uint256);

    /// @notice FRAMEPARAM(i, RESOLVED_TARGET): frame target, with null resolved to the sender.
    function frameTarget(uint256 i) external view returns (address);

    /// @notice FRAMEPARAM(i, VALUE): wei attached to the frame (non-zero only in SENDER mode).
    function frameValue(uint256 i) external view returns (uint256);

    /// @notice FRAMEDATACOPY over frame i's full `data`.
    function frameData(uint256 i) external view returns (bytes memory);
}
