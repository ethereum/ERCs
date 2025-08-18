//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.27;

struct Node {
    bytes32 id;
    address artifactContractAddress; // address originally deployed by author of Artifact
    address implementationContractAddress; // address of clone artifacts
    BytesAndIndex[] partialExecData; // todo: could be 'constantsData'
    uint256 argsCount;
    uint256[] variables; // could be something describing: position of variables supplied run-time in general variables list
    StringAndIndex[] injections;
    Bytes32AndIndex[] substitutions; // could be run-time 'evaluatedVariables'
}

struct CacheRecord {
    bytes32 key;
    bytes evaluationResult;
}

struct Bytes32AndIndex {
    bytes32 value;
    uint256 index;
}
struct StringAndIndex {
    string value;
    uint256 index;
}

struct BytesAndIndex {
    bytes value;
    uint256 index;
}

struct GraphInitParams {
    bytes32 rootNode; // only one in TreeNodeInitParams[] is root node
    TreeNodeInitParams[] nodes;
}

struct TreeNodeInitParams {
    bytes32 id;
    address artifactAddress;
    uint256 argsCount;
    BytesAndIndex[] partialExecData;
    uint256[] variables;
    StringAndIndex[] injections;
    Bytes32AndIndex[] substitutions;
    bytes initData;
    bool needsInitialization;
}

struct Variables {
    bytes32 nodeId;
    bytes[] values;
}

struct NamedTypedVariables {
    bytes32 nodeId;
    uint256 nodeIndex;
    address artifactAddress;
    Argument[] variables;
    StringAndIndex[] injections;
}

struct Argument {
    string name;
    string typename;
}
