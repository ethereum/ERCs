//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

// note: this struct describes only those params that have to be run-time supplied
struct ExecVarsMetadata {
    bytes32 nodeId; // what node-id the vars belong to
    uint256 nodeIndex; // position of node in total nodes list
    address artifactAddress; // either original address, or cloned proxy address
    // "name"-and-"type" list of node vars according to respective output of "Arfifact.getExecDescriptor" method;
    // applies to ONLY run-time supplied
    ArgumentDescription[] descriptions;
    InjectionMetadata[] injections; // list of injections metadata (injection name and pos in Node.variableExecArgs)
}

struct ArgumentDescription {
    string name; // from "getExecDescriptor"
    string typename; // from "getExecDescriptor"
}

struct InjectionMetadata {
    // example: "varboolVar$\"is_dev\"", where "varboolVar" dsl-declared name and "is_dev" is dsl-declared injection tag value
    // todo: string key
    string value;
    // position index in "Node.variableExecArgs";
    // example: index=1; "Node.variableExecArgs" is [1,3,5]; therefore, 'index' points to '3'
    uint256 index;
}

// note: raw node init config (matters only to graph structure)
struct NodeConfig {
    bytes32 node; // parent node
    bytes32[] childNodes;
}
