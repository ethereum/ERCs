// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { InternalContainerDAG } from "./InternalContainerDAG.sol";

/* 
    note: this is rather a container (proxy) to access the DAGOperationsLib library,
    since some DAG checks are not enforced here.
*/
contract ContainerDAGBytes32 is InternalContainerDAG {
    function addNode(bytes32 _nodeId) public {
        _addNode(_nodeId);
    }

    function addEdge(bytes32 _parentId, bytes32 _childId) public {
        _addEdge(_parentId, _childId);
    }

    function topologicalSort() public returns (uint256[] memory) {
        return _topologicalSort();
    }

    function hasCycle() public returns (bool result) {
        result = _hasCycle();
    }

    function nodeExists(bytes32 _nodeId) public view returns (bool) {
        return _nodeExists(_nodeId);
    }

    function getAllNodes() public view returns (uint256[] memory) {
        return getAllNodes();
    }

    function getChildren(bytes32 _nodeId) public view returns (uint256[] memory children) {
        children = _getChildren(_nodeId);
    }

    function getParents(bytes32 _nodeId) public view returns (uint256[] memory parents) {
        parents = _getParents(_nodeId);
    }

    function hasChildren(bytes32 _nodeId) public view returns (bool) {
        return _hasChildren(_nodeId);
    }

    function hasParents(bytes32 _nodeId) public view returns (bool) {
        return _hasParents(_nodeId);
    }
}
