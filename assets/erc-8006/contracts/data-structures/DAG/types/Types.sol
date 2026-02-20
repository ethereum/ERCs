//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

enum VisitStatus {
    Unvisited,
    Visiting,
    Visited
}

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

struct DFSHelper {
    mapping(uint256 nodeId => VisitStatus status) visited;
    uint256[] sorted;
}
