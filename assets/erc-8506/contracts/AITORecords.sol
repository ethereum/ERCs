// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAITORecords} from "./interfaces/IAITORecords.sol";
import {RecordKind} from "./interfaces/AITOTypes.sol";

/// @title Reference registry of content-addressed AITO records
/// @notice Records are keyed by publisher and identifier. A record, once anchored, cannot be
/// replaced; a new version is a new record that names the one it supersedes.
contract AITORecords is IAITORecords, IERC165 {
    struct Record {
        RecordKind kind;
        uint64 anchoredAt;
        bytes32 supersedes;
        string uri;
    }

    struct Batch {
        RecordKind kind;
        uint64 anchoredAt;
        uint256 count;
        string uri;
    }

    mapping(address publisher => mapping(bytes32 id => Record)) private _records;
    mapping(address publisher => mapping(bytes32 root => Batch)) private _batches;

    error ZeroIdentifier();
    error AlreadyAnchored(address publisher, bytes32 id);
    error NotAnchored(address publisher, bytes32 id);
    error SupersedesItself();
    error EmptyBatch();

    /// @inheritdoc IAITORecords
    function anchor(bytes32 id, RecordKind kind, bytes32 supersedes, string calldata uri) external {
        if (id == bytes32(0)) revert ZeroIdentifier();
        if (supersedes == id) revert SupersedesItself();
        Record storage r = _records[msg.sender][id];
        if (r.anchoredAt != 0) revert AlreadyAnchored(msg.sender, id);
        r.kind = kind;
        r.anchoredAt = uint64(block.timestamp);
        r.supersedes = supersedes;
        r.uri = uri;
        emit RecordAnchored(id, kind, msg.sender, supersedes, uri);
    }

    /// @inheritdoc IAITORecords
    function relocate(bytes32 id, string calldata uri) external {
        Record storage r = _records[msg.sender][id];
        if (r.anchoredAt == 0) revert NotAnchored(msg.sender, id);
        r.uri = uri;
        emit RecordRelocated(id, msg.sender, uri);
    }

    /// @inheritdoc IAITORecords
    function anchorBatch(bytes32 root, RecordKind kind, uint256 count, string calldata uri) external {
        if (root == bytes32(0)) revert ZeroIdentifier();
        if (count == 0) revert EmptyBatch();
        Batch storage b = _batches[msg.sender][root];
        if (b.anchoredAt != 0) revert AlreadyAnchored(msg.sender, root);
        b.kind = kind;
        b.anchoredAt = uint64(block.timestamp);
        b.count = count;
        b.uri = uri;
        emit BatchAnchored(root, kind, msg.sender, count, uri);
    }

    /// @inheritdoc IAITORecords
    function recordOf(address publisher, bytes32 id)
        external
        view
        returns (RecordKind kind, uint64 anchoredAt, bytes32 supersedes, string memory uri)
    {
        Record storage r = _records[publisher][id];
        return (r.kind, r.anchoredAt, r.supersedes, r.uri);
    }

    /// @inheritdoc IAITORecords
    function batchOf(address publisher, bytes32 root)
        external
        view
        returns (RecordKind kind, uint64 anchoredAt, uint256 count, string memory uri)
    {
        Batch storage b = _batches[publisher][root];
        return (b.kind, b.anchoredAt, b.count, b.uri);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAITORecords).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
