// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { DAG, DAGNode } from "./types/Types.sol";
import { toUint } from "./utils/MiscUtils.sol";
import { DAGOperationsLib } from "./libs/LibraryDAG.sol";
import { DFSearchHelper } from "./DFSearchHelper.sol";

/// @title Internal Container DAG
/// @notice Provides internal interface for DAG operations using bytes32 identifiers with type conversion
/// @dev Internal container (proxy) contract to access the DAGOperationsLib library functionality:
///      - Some DAG validation checks are deliberately not enforced at this contract level
contract InternalContainerDAG is DFSearchHelper {
    using DAGOperationsLib for DAG;

    DAG internal dag;

    function _addNode(bytes32 _nodeId) internal {
        dag.addNode(toUint(_nodeId));
    }

    function _addEdge(bytes32 _parentId, bytes32 _childId) internal {
        dag.addEdge(toUint(_parentId), toUint(_childId));
    }

    function _hasDisconnectedCluster(bytes32 startNodeId) internal returns (bool result) {
        result = dag.hasDisconnectedCluster(toUint(startNodeId), getDfsHelper(dag.nodeIds));
    }

    function _topologicalSort() internal returns (uint256[] memory sortedResult) {
        sortedResult = dag.topologicalSort(getDfsHelper(dag.nodeIds));
    }

    function _hasCycle() internal returns (bool result) {
        result = dag.hasCycle(getDfsHelper(dag.nodeIds));
    }

    function _nodeExists(bytes32 _nodeId) internal view returns (bool exists) {
        exists = dag.nodeExists(toUint(_nodeId));
    }

    function _getAllNodes() internal view returns (uint256[] memory nodeIds) {
        nodeIds = dag.nodeIds;
    }

    function _getNode(bytes32 nodeId) internal view returns (DAGNode storage node) {
        node = dag.getNode(uint256(nodeId));
    }

    function _getChildren(bytes32 _nodeId) internal view returns (uint256[] memory children) {
        children = dag.getChildrenNodes(toUint(_nodeId));
    }

    function _getParents(bytes32 _nodeId) internal view returns (uint256[] memory parents) {
        parents = dag.getParentNodes(toUint(_nodeId));
    }

    function _hasParents(bytes32 _nodeId) internal view returns (bool result) {
        result = dag.hasParents(toUint(_nodeId));
    }

    function _hasChildren(bytes32 _nodeId) internal view returns (bool result) {
        result = dag.hasChildren(toUint(_nodeId));
    }
}
