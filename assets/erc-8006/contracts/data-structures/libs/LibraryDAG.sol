//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { CYCLE_DETECTED_WHILE_TOPOLIGICAL_SORT_ERR } from "../constants/Errors.sol";
import { reverseList } from "../utils/Utils.sol";
import { DAG, DAGNode as Node, VisitStatus, DFSHelper } from "../types/Types.sol";
import "../utils/Validations.sol" as Validator;

library DAGOperationsLib {
    // note: add a new node to the graph
    function addNode(DAG storage self, uint256 _nodeId) internal {
        Validator.nodeIdIsNotNill(_nodeId);
        Validator.nodeNotExist(self, _nodeId);

        self.nodes[_nodeId].id = _nodeId;
        self.nodeIds.push(_nodeId);
    }

    // note: add a directed edge from parent to child
    function addEdge(DAG storage self, uint256 _parentId, uint256 _childId) internal {
        Node storage parentNode = getNode(self, _parentId);
        Node storage childNode = getNode(self, _childId);

        Validator.edgeNotExists(parentNode, _childId);
        Validator.edgeNotCyclic(parentNode.id, childNode.id);

        childNode.parents.push(_parentId);
        parentNode.edges[_childId] = true;
        parentNode.children.push(_childId);
    }

    // note: detect if there is a disconnected cluster in the graph starting from a given node
    function hasDisconnectedCluster(
        DAG storage self,
        uint256 startNodeId,
        DFSHelper storage dfsHelper
    ) internal returns (bool) {
        // note: run DFS starting from startNodeId to mark all connected nodes
        dfsConnectedNodes(self, startNodeId, dfsHelper);

        // сheck if any node is still unvisited
        for (uint256 i = 0; i < self.nodeIds.length; i++) {
            uint256 nodeId = self.nodeIds[i];
            if (dfsHelper.visited[nodeId] == VisitStatus.Unvisited) {
                return true; // found a disconnected node
            }
        }

        return false; // no disconnected nodes found
    }

    // note: make Topological Sort based Depth-first search (applies to list copy)
    function topologicalSort(
        DAG storage self,
        DFSHelper storage dfsHelper
    ) internal returns (uint256[] memory) {
        for (uint256 i = 0; i < self.nodeIds.length; i++) {
            uint256 nodeId = self.nodeIds[i];

            if (dfsHelper.visited[nodeId] == VisitStatus.Unvisited) {
                _topologicalSortDfs(self, nodeId, dfsHelper);
            }
        }

        return reverseList(dfsHelper.sorted);
    }

    // note: check if the graph contains a cycle using DFS algorithm
    function hasCycle(DAG storage self, DFSHelper storage dfsHelper) internal returns (bool) {
        uint256 nodesLength = self.nodeIds.length;

        for (uint256 i = 0; i < nodesLength; i++) {
            uint256 nodeId = self.nodeIds[i];
            if (
                dfsHelper.visited[nodeId] == VisitStatus.Unvisited &&
                dfsCycleCheck(self, nodeId, dfsHelper)
            ) {
                return true;
            }
        }

        return false;
    }

    // note: check if an edge exists
    function edgeExists(
        Node storage node,
        uint256 _childNodeId
    ) internal view returns (bool isEdge) {
        return Validator._isEdgeExists(node, _childNodeId);
    }

    // note: check if a node exists
    function nodeExists(DAG storage self, uint256 _nodeId) internal view returns (bool exists) {
        return Validator._isNodeExists(self, _nodeId);
    }

    // note: get all children of a node
    function getChildrenNodes(
        DAG storage self,
        uint256 _nodeId
    ) internal view returns (uint256[] memory) {
        return getNode(self, _nodeId).children;
    }

    // note: get all parents of a node
    function getParentNodes(
        DAG storage self,
        uint256 _nodeId
    ) internal view returns (uint256[] memory) {
        return getNode(self, _nodeId).parents;
    }

    // note: check if a node has any parents
    function hasParents(DAG storage self, uint256 _nodeId) internal view returns (bool) {
        return getParentNodes(self, _nodeId).length > 0;
    }

    // note: check if a node has any children
    function hasChildren(DAG storage self, uint256 _nodeId) internal view returns (bool) {
        return getChildrenNodes(self, _nodeId).length > 0;
    }

    function getNode(DAG storage self, uint256 _nodeId) internal view returns (Node storage node) {
        Validator.nodeExists(self, _nodeId);

        node = self.nodes[_nodeId];
    }

    // note: helper function for "hasDisconnectedCluster" to mark all connected nodes
    function dfsConnectedNodes(
        DAG storage self,
        uint256 nodeId,
        DFSHelper storage dfsHelper
    ) private {
        dfsHelper.visited[nodeId] = VisitStatus.Visited;

        // note: visit all children
        uint256[] memory children = getChildrenNodes(self, nodeId);
        for (uint256 i = 0; i < children.length; i++) {
            uint256 childId = children[i];
            if (dfsHelper.visited[childId] == VisitStatus.Unvisited) {
                dfsConnectedNodes(self, childId, dfsHelper);
            }
        }

        // note: visit all parents
        uint256[] memory parents = getParentNodes(self, nodeId);
        for (uint256 i = 0; i < parents.length; i++) {
            uint256 parentId = parents[i];
            if (dfsHelper.visited[parentId] == VisitStatus.Unvisited) {
                dfsConnectedNodes(self, parentId, dfsHelper);
            }
        }
    }

    // note: intended as a helper for cycle detection (DFS algorithm)
    function dfsCycleCheck(
        DAG storage self,
        uint256 _nodeId,
        DFSHelper storage dfsHelper
    ) private returns (bool) {
        dfsHelper.visited[_nodeId] = VisitStatus.Visiting;

        for (uint256 i = 0; i < self.nodes[_nodeId].children.length; i++) {
            uint256 childId = self.nodes[_nodeId].children[i];
            if (dfsHelper.visited[childId] == VisitStatus.Visiting) {
                return true; // note: node self-cycle detected
            }
            if (
                dfsHelper.visited[childId] == VisitStatus.Unvisited &&
                dfsCycleCheck(self, childId, dfsHelper)
            ) {
                return true; // note: cycle detected in recursive call
            }
        }

        dfsHelper.visited[_nodeId] = VisitStatus.Visited;

        // note: mark as fully visited
        return false;
    }

    // note: helper function for DFS-based topological sorting
    function _topologicalSortDfs(
        DAG storage self,
        uint256 _nodeId,
        DFSHelper storage dfsHelper
    ) private {
        bool isCycleDetected = dfsCycleCheckV2(self, _nodeId, dfsHelper);

        Validator.boolIsFalsyWithErr(isCycleDetected, CYCLE_DETECTED_WHILE_TOPOLIGICAL_SORT_ERR);
    }

    // note: helper function for topoligical sort and dag cycle check
    function dfsCycleCheckV2(
        DAG storage self,
        uint256 _nodeId,
        DFSHelper storage dfsHelper
    ) private returns (bool) {
        dfsHelper.visited[_nodeId] = VisitStatus.Visiting;

        for (uint256 i = 0; i < self.nodes[_nodeId].children.length; i++) {
            uint256 childId = self.nodes[_nodeId].children[i];

            if (dfsHelper.visited[childId] == VisitStatus.Visiting) {
                return true; // note: node self-cycle detected
            }
            if (
                dfsHelper.visited[childId] == VisitStatus.Unvisited &&
                dfsCycleCheckV2(self, childId, dfsHelper)
            ) {
                return true; // note: cycle detected in recursive call
            }
        }

        dfsHelper.visited[_nodeId] = VisitStatus.Visited;
        dfsHelper.sorted.push(_nodeId); // the best place to push sorted values

        // note: mark as fully visited
        return false;
    }
}
