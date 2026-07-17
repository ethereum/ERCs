// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IERC_BSS — Blob Space Segments
/// @notice Minimal interface for declaring field element sub-ranges within EIP-4844 blobs.
/// @dev Event-only (zero storage). A segment is a half-open range [startFE, endFE) of
///      field elements. The BLOBHASH opcode binds declarations to actual blobs in the
///      current transaction, preventing false claims.
///
///      Content tags use keccak256("protocol.version") for collision-free identification
///      without a registry.
interface IERC_BSS {
    // ═══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a blob segment is declared.
    /// @param versionedHash The EIP-4844 versioned hash of the blob
    /// @param declarer      The address declaring the segment (msg.sender)
    /// @param startFE       Start field element index (inclusive)
    /// @param endFE         End field element index (exclusive)
    /// @param contentTag    Protocol/content identifier (e.g. keccak256("social-blobs.v4"))
    event BlobSegmentDeclared(
        bytes32 indexed versionedHash,
        address indexed declarer,
        uint16 startFE,
        uint16 endFE,
        bytes32 indexed contentTag
    );

    // ═══════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when startFE >= endFE or endFE > 4096.
    /// @param startFE The invalid start field element
    /// @param endFE   The invalid end field element
    error InvalidSegment(uint16 startFE, uint16 endFE);

    /// @notice Thrown when BLOBHASH returns bytes32(0) for the given index.
    /// @param blobIndex The blob index that has no blob
    error NoBlobAtIndex(uint256 blobIndex);

    // ═══════════════════════════════════════════════════════════════════════════════
    // DECLARATION
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Declare a segment of a blob in the current transaction.
    /// @dev Uses BLOBHASH opcode to bind the declaration to an actual blob.
    ///      Reverts if no blob exists at blobIndex or if the range is invalid.
    ///      MUST NOT write to storage. The event log is the sole record.
    /// @param blobIndex  Index of the blob within the transaction (0-based)
    /// @param startFE    Start field element (inclusive). MUST be < endFE
    /// @param endFE      End field element (exclusive). MUST be <= 4096
    /// @param contentTag Protocol/content identifier
    /// @return versionedHash The EIP-4844 versioned hash of the blob
    function declareBlobSegment(uint256 blobIndex, uint16 startFE, uint16 endFE, bytes32 contentTag)
        external
        returns (bytes32 versionedHash);
}
