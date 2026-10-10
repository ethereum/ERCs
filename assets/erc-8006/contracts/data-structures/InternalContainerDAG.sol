// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { DAG, DAGNode } from "./types/Types.sol";
import { toUint } from "./utils/Utils.sol";
import { DAGOperationsLib } from "./libs/LibraryDAG.sol";
import { DFSearchHelper } from "./DFSearchHelper.sol";

// note: his is rather a container (proxy) to access the DAGOperationsLib library,
// since some DAG checks are not enforced here.
contract InternalContainerDAG is DFSearchHelper {
    using DAGOperationsLib for DAG;

    DAG internal dag;

    function _addNode(bytes32 _nodeId) internal {
        dag.addNode(toUint(_nodeId));
    }

    // note: add a directed edge from parent to child
    function _addEdge(bytes32 _parentId, bytes32 _childId) internal {
        dag.addEdge(toUint(_parentId), toUint(_childId));
    }

    // note: detect if there is a disconnected cluster in the graph starting from the root node
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

    // note: if a node has any parents
    function _hasParents(bytes32 _nodeId) internal view returns (bool result) {
        result = dag.hasParents(toUint(_nodeId));
    }

    // note: if a node has any children
    function _hasChildren(bytes32 _nodeId) internal view returns (bool result) {
        result = dag.hasChildren(toUint(_nodeId));
    }
}
