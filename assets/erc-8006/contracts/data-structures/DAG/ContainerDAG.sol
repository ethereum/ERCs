// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { DAG } from "./types/Types.sol";
import { DAGOperationsLib } from "./libs/LibraryDAG.sol";
import { DFSearchHelper } from "./DFSearchHelper.sol";

/// @title Container DAG
/// @notice Provides public interface for DAG operations with simplified access to underlying library functions
/// @dev Container (proxy) contract to access the DAGOperationsLib library functionality:
///      - Some DAG validation checks are deliberately not enforced at this contract level
contract ContainerDAG is DFSearchHelper {
    using DAGOperationsLib for DAG;

    DAG internal dag;

    function addNode(uint256 _nodeId) public {
        dag.addNode(_nodeId);
    }

    function addEdge(uint256 _parentId, uint256 _childId) public {
        dag.addEdge(_parentId, _childId);
    }

    function hasDisconnectedCluster(uint256 startNodeId) public returns (bool result) {
        result = dag.hasDisconnectedCluster(startNodeId, getDfsHelper(dag.nodeIds));
    }

    function topologicalSort() public returns (uint256[] memory sortedResult) {
        sortedResult = dag.topologicalSort(getDfsHelper(dag.nodeIds));
    }

    function hasCycle() public returns (bool result) {
        result = dag.hasCycle(getDfsHelper(dag.nodeIds));
    }

    function nodeExists(uint256 _nodeId) public view returns (bool exists) {
        exists = dag.nodeExists(_nodeId);
    }

    function getAllNodes() public view returns (uint256[] memory nodeIds) {
        nodeIds = dag.nodeIds;
    }

    function getChildren(uint256 _nodeId) public view returns (uint256[] memory children) {
        children = dag.getChildrenNodes(_nodeId);
    }

    function getParents(uint256 _nodeId) public view returns (uint256[] memory parents) {
        parents = dag.getParentNodes(_nodeId);
    }

    function hasParents(uint256 _nodeId) public view returns (bool result) {
        result = dag.hasParents(_nodeId);
    }

    function hasChildren(uint256 _nodeId) public view returns (bool result) {
        result = dag.hasChildren(_nodeId);
    }
}
