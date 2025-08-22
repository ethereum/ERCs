//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { CYCLE_DETECTED_WHILE_TOPOLIGICAL_SORT_ERR } from "../constants/ErrorCodes.sol";
import { DAG, DAGNode as Node, VisitStatus, DFSHelper } from "../types/Types.sol";
import "../utils/MiscUtils.sol" as HelperUtils;
import "../utils/ValidationUtils.sol" as Validator;

/// @title DAG Operations Library
/// @dev Library containing operations for Directed Acyclic Graph (DAG) data structure
/// @notice Provides functions to manipulate and query DAG structures including node/edge management,
///         cycle detection, topological sorting, and connectivity analysis
library DAGOperationsLib {
    /// @notice Adds a new node to the DAG
    /// @dev Validates that the node ID is not null and doesn't already exist
    /// @param self The DAG storage reference
    /// @param nodeId The unique identifier for the new node
    function addNode(DAG storage self, uint256 nodeId) internal {
        Validator.nodeIdIsNotNill(nodeId);
        Validator.nodeNotExist(self, nodeId);

        self.nodes[nodeId].id = nodeId;
        self.nodeIds.push(nodeId);
    }

    /// @notice Adds a directed edge from parent to child node
    /// @dev Validates that both nodes exist, edge doesn't already exist, and won't create a cycle
    /// @param self The DAG storage reference
    /// @param _parentId The ID of the parent node
    /// @param _childId The ID of the child node
    function addEdge(DAG storage self, uint256 _parentId, uint256 _childId) internal {
        Node storage parentNode = getNode(self, _parentId);
        Node storage childNode = getNode(self, _childId);

        Validator.edgeNotExists(parentNode, _childId);
        Validator.edgeNotCyclic(parentNode.id, childNode.id);

        childNode.parents.push(_parentId);
        parentNode.edges[_childId] = true;
        parentNode.children.push(_childId);
    }

    /// @notice Detects if there is a disconnected cluster in the graph starting from a given node
    /// @dev Runs DFS from the start node to mark all connected nodes, then checks for unvisited nodes
    /// @param self The DAG storage reference
    /// @param startNodeId The ID of the starting node for connectivity analysis
    /// @param dfsHelper Helper struct containing visited status tracking
    /// @return bool True if there are disconnected clusters, false otherwise
    function hasDisconnectedCluster(
        DAG storage self,
        uint256 startNodeId,
        DFSHelper storage dfsHelper
    ) internal returns (bool) {
        // note: run DFS starting from startNodeId to mark all connected nodes
        dfsConnectedNodes(self, startNodeId, dfsHelper);

        // note: сheck if any node is still unvisited
        for (uint256 i = 0; i < self.nodeIds.length; i++) {
            uint256 nodeId = self.nodeIds[i];
            if (dfsHelper.visited[nodeId] == VisitStatus.Unvisited) {
                return true; // found a disconnected node
            }
        }

        return false; // no disconnected nodes found
    }

    /// @notice Performs topological sort using Depth-First Search algorithm
    /// @dev Applies topological sorting to a copy of the node list and returns nodes in topologically sorted order
    /// @param self The DAG storage reference
    /// @param dfsHelper Helper struct containing visited status tracking and sorted results
    /// @return uint256[] Array of node IDs in topologically sorted order
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

        return HelperUtils.reverseList(dfsHelper.sorted);
    }

    /// @notice Checks if the graph contains a cycle using DFS algorithm
    /// @dev Iterates through all nodes and performs DFS-based cycle detection
    /// @param self The DAG storage reference
    /// @param dfsHelper Helper struct containing visited status tracking
    /// @return bool True if a cycle is detected, false otherwise
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

    /// @notice Checks if an edge exists between a node and its potential child
    /// @dev Uses HelperUtils to verify edge existence
    /// @param node The parent node storage reference
    /// @param _childNodeId The ID of the potential child node
    /// @return isEdge True if edge exists, false otherwise
    function edgeExists(
        Node storage node,
        uint256 _childNodeId
    ) internal view returns (bool isEdge) {
        return HelperUtils.isEdgeExists(node, _childNodeId);
    }

    /// @notice Checks if a node exists in the DAG
    /// @dev Uses HelperUtils to verify node existence
    /// @param self The DAG storage reference
    /// @param nodeId The ID of the node to check
    /// @return exists True if node exists, false otherwise
    function nodeExists(DAG storage self, uint256 nodeId) internal view returns (bool exists) {
        return HelperUtils.isNodeExists(self, nodeId);
    }

    /// @notice Gets all children nodes of a specified node
    /// @dev Retrieves the children array from the node structure
    /// @param self The DAG storage reference
    /// @param nodeId The ID of the parent node
    /// @return uint256[] Array of child node IDs
    function getChildrenNodes(
        DAG storage self,
        uint256 nodeId
    ) internal view returns (uint256[] memory) {
        return getNode(self, nodeId).children;
    }

    /// @notice Gets all parent nodes of a specified node
    /// @dev Retrieves the parents array from the node structure
    /// @param self The DAG storage reference
    /// @param nodeId The ID of the child node
    /// @return uint256[] Array of parent node IDs
    function getParentNodes(
        DAG storage self,
        uint256 nodeId
    ) internal view returns (uint256[] memory) {
        return getNode(self, nodeId).parents;
    }

    /// @notice Checks if a node has any parent nodes
    /// @dev Returns true if the node's parents array has length > 0
    /// @param self The DAG storage reference
    /// @param nodeId The ID of the node to check
    /// @return bool True if node has parents, false otherwise
    function hasParents(DAG storage self, uint256 nodeId) internal view returns (bool) {
        return getParentNodes(self, nodeId).length > 0;
    }

    /// @notice Checks if a node has any child nodes
    /// @dev Returns true if the node's children array has length > 0
    /// @param self The DAG storage reference
    /// @param nodeId The ID of the node to check
    /// @return bool True if node has children, false otherwise
    function hasChildren(DAG storage self, uint256 nodeId) internal view returns (bool) {
        return getChildrenNodes(self, nodeId).length > 0;
    }

    /// @notice Gets a node by its ID with existence validation
    /// @dev Validates node existence before returning the storage reference
    /// @param self The DAG storage reference
    /// @param nodeId The ID of the node to retrieve
    /// @return node Storage reference to the requested node
    function getNode(DAG storage self, uint256 nodeId) internal view returns (Node storage node) {
        Validator.nodeExists(self, nodeId);

        node = self.nodes[nodeId];
    }

    /// @notice Helper function for "hasDisconnectedCluster" to mark all connected nodes
    /// @dev Performs DFS traversal marking all nodes reachable from the starting node
    /// @param self The DAG storage reference
    /// @param nodeId The current node ID being visited
    /// @param dfsHelper Helper struct containing visited status tracking
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

    /// @notice Helper function for cycle detection using DFS algorithm
    /// @dev Performs depth-first search with three-color marking to detect cycles
    /// @param self The DAG storage reference
    /// @param nodeId The current node ID being processed
    /// @param dfsHelper Helper struct containing visited status tracking
    /// @return bool True if cycle detected, false otherwise
    function dfsCycleCheck(
        DAG storage self,
        uint256 nodeId,
        DFSHelper storage dfsHelper
    ) private returns (bool) {
        dfsHelper.visited[nodeId] = VisitStatus.Visiting;

        for (uint256 i = 0; i < self.nodes[nodeId].children.length; i++) {
            uint256 childId = self.nodes[nodeId].children[i];
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

        dfsHelper.visited[nodeId] = VisitStatus.Visited;

        // note: mark as fully visited
        return false;
    }

    /// @notice Helper function for DFS-based topological sorting
    /// @dev Initiates cycle check and validates DAG property before sorting
    /// @param self The DAG storage reference
    /// @param nodeId The starting node ID for the DFS traversal
    /// @param dfsHelper Helper struct containing visited status tracking
    function _topologicalSortDfs(
        DAG storage self,
        uint256 nodeId,
        DFSHelper storage dfsHelper
    ) private {
        bool isCycleDetected = dfsCycleCheckV2(self, nodeId, dfsHelper);

        Validator.boolIsFalsyWithErr(isCycleDetected, CYCLE_DETECTED_WHILE_TOPOLIGICAL_SORT_ERR);
    }

    /// @notice Helper function for topological sort and DAG cycle check
    /// @dev Performs DFS with cycle detection while building the topologically sorted list
    /// @param self The DAG storage reference
    /// @param nodeId The current node ID being processed
    /// @param dfsHelper Helper struct containing visited status tracking and sorted results
    /// @return bool True if cycle detected, false otherwise
    function dfsCycleCheckV2(
        DAG storage self,
        uint256 nodeId,
        DFSHelper storage dfsHelper
    ) private returns (bool) {
        dfsHelper.visited[nodeId] = VisitStatus.Visiting;

        for (uint256 i = 0; i < self.nodes[nodeId].children.length; i++) {
            uint256 childId = self.nodes[nodeId].children[i];

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

        dfsHelper.visited[nodeId] = VisitStatus.Visited;
        dfsHelper.sorted.push(nodeId); // the best place to push sorted values

        // note: mark as fully visited
        return false;
    }
}
