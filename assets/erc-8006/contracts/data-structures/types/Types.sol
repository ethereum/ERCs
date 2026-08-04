//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

struct DAGNode {
    uint256 id; // node-Id
    uint256[] children; // children node-Ids
    mapping(uint256 childNodeId => bool isEdge) edges; // parent node is aware what edges to child nodes exist
    uint256[] parents; // parent node-Ids (needed to track dangline nodes)
}

struct DAG {
    mapping(uint256 => DAGNode) nodes; // id=>Node
    uint256[] nodeIds;
}

struct VisitedNode {
    VisitStatus status;
    uint256 nodeId;
}

enum VisitStatus {
    Unvisited,
    Visiting,
    Visited
}

struct DFSHelper {
    mapping(uint256 nodeId => VisitStatus status) visited;
    uint256[] sorted;
}
