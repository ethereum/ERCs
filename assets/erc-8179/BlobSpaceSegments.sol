// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC_BSS} from "./IERC_BSS.sol";

/// @title BlobSpaceSegments
/// @notice Reference implementation of ERC-BSS: Blob Space Segments
/// @dev Zero storage — events are the sole record. Uses BLOBHASH opcode (EIP-4844).
contract BlobSpaceSegments is IERC_BSS {
    /// @dev Maximum number of field elements per EIP-4844 blob.
    uint16 internal constant MAX_FIELD_ELEMENTS = 4096;

    /// @inheritdoc IERC_BSS
    function declareBlobSegment(uint256 blobIndex, uint16 startFE, uint16 endFE, bytes32 contentTag)
        external
        returns (bytes32 versionedHash)
    {
        if (startFE >= endFE || endFE > MAX_FIELD_ELEMENTS) {
            revert InvalidSegment(startFE, endFE);
        }

        // BLOBHASH returns bytes32(0) for indices without a blob in this tx
        assembly {
            versionedHash := blobhash(blobIndex)
        }
        if (versionedHash == bytes32(0)) revert NoBlobAtIndex(blobIndex);

        emit BlobSegmentDeclared(versionedHash, msg.sender, startFE, endFE, contentTag);
    }
}
