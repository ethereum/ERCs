// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC_BSS} from "./IERC_BSS.sol";

/// @title IERC_BSS_Queryable — On-chain Segment Query Extension
/// @notice Optional extension for contracts that need to query segment declarations on-chain.
/// @dev Uses storage to persist segment data. Significantly more expensive than the core
///      event-only interface (~20k additional gas per declaration for SSTORE). Only adopt
///      when on-chain queries are strictly required.
///
///      This extension supersedes the core interface's "MUST NOT write to storage" requirement.
///      Implementations MUST write segment data to storage to support queries.
interface IERC_BSS_Queryable is IERC_BSS {
    /// @notice A stored segment record.
    /// @param declarer   Address that declared the segment
    /// @param startFE    Start field element (inclusive)
    /// @param endFE      End field element (exclusive)
    /// @param contentTag Protocol/content identifier
    struct BlobSegment {
        address declarer;
        uint16 startFE;
        uint16 endFE;
        bytes32 contentTag;
    }

    /// @notice Returns a paginated list of segments declared for a given versioned hash.
    /// @param versionedHash The EIP-4844 versioned hash
    /// @param offset        Number of segments to skip (0-based)
    /// @param limit         Maximum number of segments to return
    /// @return segments Array of segment records
    /// @return nextOffset Cursor for the next page (equal to segmentCount when exhausted)
    function getSegments(bytes32 versionedHash, uint256 offset, uint256 limit)
        external
        view
        returns (BlobSegment[] memory segments, uint256 nextOffset);

    /// @notice Returns the number of segments declared for a given versioned hash.
    /// @param versionedHash The EIP-4844 versioned hash
    /// @return count Number of segments
    function segmentCount(bytes32 versionedHash) external view returns (uint256 count);
}
