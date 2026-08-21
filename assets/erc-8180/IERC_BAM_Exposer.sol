// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IERC_BAM_Exposer
/// @notice Interface for message exposure in Blob Authenticated Messaging
/// @dev Defines the event and query interface for exposing individual messages on-chain.
///      The expose() function itself is NOT standardized — it varies by signature scheme
///      and proof type (KZG, ZK, etc.). Implementations provide their own expose methods
///      and emit the standardized event.
interface IERC_BAM_Exposer {
    /// @notice Emitted when a message is exposed on-chain.
    /// @param contentHash Content identifier (versioned hash for blob, keccak256 for calldata).
    /// @param messageId   Unique message identifier: keccak256(author || nonce || contentHash).
    /// @param author      Author's Ethereum address.
    /// @param exposer     Address that called the expose function.
    /// @param timestamp   Block timestamp when exposed.
    event MessageExposed(
        bytes32 indexed contentHash,
        bytes32 indexed messageId,
        address indexed author,
        address exposer,
        uint64 timestamp
    );

    /// @notice Thrown when the content hash is not registered in the core contract.
    error NotRegistered(bytes32 contentHash);

    /// @notice Thrown when the message has already been exposed.
    error AlreadyExposed(bytes32 messageId);

    /// @notice Check if a message has been exposed.
    /// @param messageId The message identifier.
    /// @return exposed  True if message has been exposed.
    function isExposed(bytes32 messageId) external view returns (bool exposed);
}
