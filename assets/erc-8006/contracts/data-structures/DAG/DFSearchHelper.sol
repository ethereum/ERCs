// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { DFSHelper, VisitStatus } from "./types/Types.sol";

/// @title Depth-First Search Helper
/// @notice Provides DFS helper functionality with transient storage for visit tracking and sorting
/// @dev Dedicated contract for managing DFS operations:
///      - Separated into dedicated contract for cleaner codebase architecture
///      - Enables DFSHelper variable ue as a state variable with storage acces
contract DFSearchHelper {
    // @important: transient storage
    DFSHelper private dfs;

    function getDfsHelper(uint256[] memory nodeIds) internal returns (DFSHelper storage _dfs) {
        _cleanUpDfsHelper(nodeIds);
        _dfs = dfs;
    }

    function _cleanUpDfsHelper(uint256[] memory nodeIds) private {
        for (uint256 i; i < nodeIds.length; i++) {
            uint256 nodeId = nodeIds[i];
            dfs.visited[nodeId] = VisitStatus.Unvisited;
        }

        delete dfs.sorted;
    }
}
