// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { DFSHelper, VisitStatus } from "./types/Types.sol";

// note: only reasons to keep it in a dedicated contract are
// a. to have cleaner codebase
// b. the need of DFSHelper variable to be state variable accessing storage
contract DFSearchHelper {
    // todo: apply transient storage whenever available for other types than value types
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
