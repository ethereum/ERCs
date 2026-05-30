// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC_BSS} from "./IERC_BSS.sol";

/// @title IERC_BAM_Core
/// @notice Core interface for Blob Authenticated Messaging — batch registration
/// @dev Extends IERC_BSS to add decoder and signature registry pointers to blob segment
///      declarations. Zero storage — events are the source of truth. Permissionless.
interface IERC_BAM_Core is IERC_BSS {
    /// @notice Emitted when a blob batch is registered.
    /// @param versionedHash     The EIP-4844 versioned hash of the blob.
    /// @param submitter         The address that registered the batch (msg.sender).
    /// @param decoder           Decoder contract for extracting messages from the batch payload.
    /// @param signatureRegistry Signature registry for verifying message signatures.
    event BlobBatchRegistered(
        bytes32 indexed versionedHash, address indexed submitter, address indexed decoder, address signatureRegistry
    );

    /// @notice Emitted when a calldata batch is registered.
    /// @param contentHash       Content hash (keccak256 of batch data).
    /// @param submitter         The address that registered the batch (msg.sender).
    /// @param decoder           Decoder contract for extracting messages from the batch payload.
    /// @param signatureRegistry Signature registry for verifying message signatures.
    event CalldataBatchRegistered(
        bytes32 indexed contentHash, address indexed submitter, address indexed decoder, address signatureRegistry
    );

    /// @notice Register a blob batch with segment coordinates, decoder, and signature registry.
    /// @param blobIndex          Index of the blob within the transaction (0-based).
    /// @param startFE            Start field element (inclusive). MUST be < endFE.
    /// @param endFE              End field element (exclusive). MUST be <= 4096.
    /// @param contentTag         Protocol/content identifier (passed to declareBlobSegment).
    /// @param decoder            Decoder contract address for extracting messages.
    /// @param signatureRegistry  Signature registry address for verifying message signatures.
    /// @return versionedHash The EIP-4844 versioned hash of the blob.
    function registerBlobBatch(
        uint256 blobIndex,
        uint16 startFE,
        uint16 endFE,
        bytes32 contentTag,
        address decoder,
        address signatureRegistry
    ) external returns (bytes32 versionedHash);

    /// @notice Register a batch submitted via calldata.
    /// @param batchData          The batch payload bytes.
    /// @param decoder            Decoder contract address for extracting messages.
    /// @param signatureRegistry  Signature registry address for verifying message signatures.
    /// @return contentHash The keccak256 hash of batchData.
    function registerCalldataBatch(bytes calldata batchData, address decoder, address signatureRegistry)
        external
        returns (bytes32 contentHash);
}
