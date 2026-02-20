//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { InjectionMetadata } from "./UtilTypes.sol";

// IMPORTANT:
// The generic arguments-list consists of [...substitutedExecArgs, ...constantExecArgs, ...variableExecArgs]
// "constantExecArgs" is known at a deploy-time
// "substitutedExecArgs" is known at a deploy time
// "variableExecArgs" is run-time supplied; important: it is not all the vars from generic arguments-list, JUST A SUBSET run-time supplied

// note: configured node
struct Node {
    bytes32 id;
    address originalArtifact; // originally deployed by author (could be a third-party author/provider)
    address clonedArtifact; // A) proxy deployed Artifact instance address (cloned from original codebase), stateful; or B) still an original artifact address, if stateless
    uint256 argsCount; // total number of artifact-instance exec params (including vars, constants, sustitutions)
    SubstitutionArgument[] substitutedExecArgs; // exec "substitution-data" (what nodes this node relies on; known at deploy time)
    ConstantArgument[] constantExecArgs; // exec "constants-data" (known at deploy time)
    uint256[] variableExecArgs; // actually, a POSITION index list (where to put supplied variable value) in generic arguments-list of particular node
    InjectionMetadata[] injections;
}

// note: not configured node
struct NodeInitData {
    // unique id, generated offchain
    bytes32 id;
    // init data of artifact-instance (can be "0x")
    bytes initData;
    // needsInitialization=true: Stateful artifact-instance; needsInitialization=false: Stateless artifact-instance
    bool needsInitialization;
    // original artifact address
    address artifactAddress;
    uint256 argsCount;
    SubstitutionArgument[] substitutedExecArgs;
    ConstantArgument[] constantExecArgs;
    uint256[] variableExecArgs;
    InjectionMetadata[] injections; // pure METADATA param; not required in any evaluation; has to be know at deploy time
}

struct SubstitutionArgument {
    bytes32 supplierNodeId; // what node-id from the total nodes list to retrieve its result from
    uint256 index; // position where in generic-arguments-list (of particular node) to insert the substituting node result
}

// note: bytes-packed value with pos
struct ConstantArgument {
    bytes value; // actual bytes encoded constant value
    // todo: pos
    uint256 index; // position where in generic arguments-list (of particular node) to insert the constant value
}

// note: run-time supplied variables
// @important: this is only the vars required to be run-time supplied
struct ExecVariables {
    // node-id where to apply the variables
    bytes32 nodeId;
    // variables-list (encoded as bytes);
    bytes[] values;
}

// note: graph init data
struct InitParams {
    NodeInitData[] nodes;
    bytes32 rootNode; // note: the Root-node is an entry node in "nodes" list, selected as graph starting node
}
