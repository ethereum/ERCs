//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.27;

import { Node, TreeNodeInitParams } from "./Types.sol";
import { OwnerBase } from "./OwnerBase.sol";
import "./Validations.sol" as Validate;
import "./Utilities.sol" as Utils;

contract ArtifactNodesBase is OwnerBase {
    Node[] internal nodes;
    mapping(bytes32 => uint256) internal idToIndex; // nodeIdToIndex
    // mapping(uint256 => bytes32) internal indexToId; // nodeIndexToId

    constructor(address _adminUser) OwnerBase(_adminUser) {
        // note: the first node is always empty. its index: 0, its id: bytes32(0)
        bytes32 firstNodeId = bytes32(0);
        createEmptyNodeWithId(firstNodeId);
    }

    function addNodeInternal(
        TreeNodeInitParams memory params
    ) internal returns (uint256 newNodeIndex) {
        (Node storage newNode, uint256 nodeIndex) = createEmptyNodeWithId(params.id);
        newNodeIndex = nodeIndex;

        maybeCreateArtifactState(newNode, params);

        setNodeConstants(newNode, params);

        setNodeVariables(newNode, params);

        setNodeInjections(newNode, params);

        setNodeSubstibutions(newNode, params);

        setArgsCount(newNode, params);
    }

    function maybeCreateArtifactState(Node storage node, TreeNodeInitParams memory params) private {
        // note: IArbitraryDataArtifact is erc165-compatible
        node.artifactContractAddress = Validate.validateAddressIsArtifact(params.artifactAddress);

        // note: in case the artifact is STATELESS, or it is ok to rely on shared state:
        node.implementationContractAddress = node.artifactContractAddress;

        // note: in case artifact is STATEFULL and it is sensetive to have/consume a dedicated state within artifact
        if (params.needsInitialization) {
            address deployed = Utils.deployArtifact(node);
            Utils.toArtifactInstance(deployed).init(params.initData);

            node.implementationContractAddress = deployed;
        }
    }

    function createEmptyNode() private returns (Node storage emptyNode, uint256 emptyNodeIndex) {
        // note: pushing new empty node thereby making its storage accesible to write/reade
        nodes.push();

        // note: emptyNodeIndex = total_nodes_count - 1
        // the value of 0 is prevented to be assigned to 'emptyNodeIndex' by pushing Empty Node in constructor
        emptyNodeIndex = nodes.length - 1;
        emptyNode = nodes[emptyNodeIndex];

        return (emptyNode, emptyNodeIndex);
    }

    function createEmptyNodeWithId(
        bytes32 nodeId
    ) private returns (Node storage emptyNode, uint256 emptyNodeIndex) {
        (Node storage node, uint256 index) = createEmptyNode();
        node.id = nodeId;
        idToIndex[nodeId] = index;

        return (node, index);
    }

    function setNodeConstants(Node storage node, TreeNodeInitParams memory params) private {
        for (uint256 i = 0; i < params.partialExecData.length; i++) {
            node.partialExecData.push(params.partialExecData[i]);
        }
    }

    function setNodeVariables(Node storage node, TreeNodeInitParams memory params) private {
        for (uint256 i = 0; i < params.variables.length; i++) {
            node.variables.push(params.variables[i]);
        }
    }

    function setNodeInjections(Node storage node, TreeNodeInitParams memory params) private {
        for (uint256 i = 0; i < params.injections.length; i++) {
            node.injections.push(params.injections[i]);
        }
    }

    function setNodeSubstibutions(Node storage node, TreeNodeInitParams memory params) private {
        for (uint256 i = 0; i < params.substitutions.length; i++) {
            node.substitutions.push(params.substitutions[i]);
        }
    }

    function setArgsCount(Node storage node, TreeNodeInitParams memory params) private {
        Validate.validateArgsCount(node, params.argsCount);
        node.argsCount = params.argsCount;
    }
}
