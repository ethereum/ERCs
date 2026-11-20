// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {RecordKind} from "./AITOTypes.sol";

/// @title Anchoring of content-addressed AITO records
/// @notice A record identifier is the keccak256 hash of the canonical form of the record.
/// Anchoring states that `publisher` stands behind the record; it proves nothing about its content.
interface IAITORecords {
    /// @notice `publisher` anchored record `id`.
    event RecordAnchored(
        bytes32 indexed id, RecordKind indexed kind, address indexed publisher, bytes32 supersedes, string uri
    );
    /// @notice `publisher` changed where record `id` can be fetched. The content is unchanged.
    event RecordRelocated(bytes32 indexed id, address indexed publisher, string uri);
    /// @notice `publisher` anchored a Merkle root over `count` records of one kind.
    event BatchAnchored(
        bytes32 indexed root, RecordKind indexed kind, address indexed publisher, uint256 count, string uri
    );

    /// @notice Anchor record `id` under the caller's address.
    /// @param supersedes Identifier of the record this one replaces, or zero.
    /// @param uri Where the record can be fetched.
    function anchor(bytes32 id, RecordKind kind, bytes32 supersedes, string calldata uri) external;

    /// @notice Change the location of a record the caller anchored.
    function relocate(bytes32 id, string calldata uri) external;

    /// @notice Anchor a Merkle root over `count` records of one kind under the caller's address.
    function anchorBatch(bytes32 root, RecordKind kind, uint256 count, string calldata uri) external;

    /// @notice The record `publisher` anchored under `id`. `anchoredAt` is zero when there is none.
    function recordOf(address publisher, bytes32 id)
        external
        view
        returns (RecordKind kind, uint64 anchoredAt, bytes32 supersedes, string memory uri);

    /// @notice The batch `publisher` anchored under `root`. `anchoredAt` is zero when there is none.
    function batchOf(address publisher, bytes32 root)
        external
        view
        returns (RecordKind kind, uint64 anchoredAt, uint256 count, string memory uri);
}
