//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.27;

import {
    SUPPLIED_VARIABLES_LIST_LENGTH_NOT_MATCHES_EXPECTED_LENGTH_ERR,
    SUPPLIED_NODE_ID_NOT_UNIQUE_ERR,
    SUPPLIED_NODE_ID_IS_NIL_ERR,
    NODE_NOT_EXISTS_ERR,
    NODE_INDEX_NOT_EXISTS_ERR,
    PROVIDED_NODE_REFERENCE_IS_NIL_ERR
} from "./Errors.sol";
import { IArbitraryDataArtifact } from "./pre-defined/common/basis/interfaces/Export.sol";
import {
    BytesAndIndex,
    Bytes32AndIndex,
    Node,
    TreeNodeInitParams,
    Variables,
    CacheRecord,
    NamedTypedVariables
} from "./Types.sol";
import { ArtifactNodesBase } from "./ArtifactNodesBase.sol";
import "./Utilities.sol" as Utils;


contract ArtifactNodes is ArtifactNodesBase {
    constructor(address _adminUser) ArtifactNodesBase(_adminUser) {}

    function addNode(
        TreeNodeInitParams memory params
    ) public onlyOwner returns (uint256 newNodeIndex) {
        require(params.id != bytes32(0), SUPPLIED_NODE_ID_IS_NIL_ERR);
        require(idToIndex[params.id] == 0, SUPPLIED_NODE_ID_NOT_UNIQUE_ERR);

        newNodeIndex = addNodeInternal(params);
    }

    // note: policy tree can not be too broad or
    // cyclic cause of stack depth (see: PolicyHandler.set)
    function evaluateRecursively(
        Node memory node,
        Variables[] memory variables,
        CacheRecord[] memory cache,
        uint256 lastCacheRecord
    ) public onlyOwner returns (bytes memory result) {
        // note: validation "isUnuqie(variables[i].nodeId)" is redundant since this.addNode requires nodes to have uniqe id
        IArbitraryDataArtifact instance = Utils.toArtifactInstance(node);
        bytes[] memory selfVariables;

        // todo: maybe something more efficient
        // suggestion: if variables[i] is consumed, then it is removed from the 'variables'
        // and the altered array is passed to next recursive iteration.

        // important: if artifact a requires artifact d and artifact b requires artifact d, then it is prohibited
        // the same instance of artifact d can not be re-used by multiple artifacts. motivation: this will simplify evertyhing
        for (uint256 i = 0; i < variables.length; i++) {
            if (variables[i].nodeId == node.id) {
                selfVariables = variables[i].values;
                break;
            }
        }

        bytes[] memory execArgumentsArraified = new bytes[](node.argsCount);

        require(
            node.variables.length == selfVariables.length,
            SUPPLIED_VARIABLES_LIST_LENGTH_NOT_MATCHES_EXPECTED_LENGTH_ERR
        );
        // note: writing run-time supplied variables to exec arguments
        for (uint256 i = 0; i < node.variables.length; i++) {
            execArgumentsArraified[node.variables[i]] = selfVariables[i];
        }

        // note: writing constans to exec arguments
        for (uint256 i = 0; i < node.partialExecData.length; i++) {
            BytesAndIndex memory constMember = node.partialExecData[i];

            execArgumentsArraified[constMember.index] = constMember.value;
        }

        // note: writting execution results of other Artifacts as exec arguments of the current one
        // note: recursion base
        // question: what if node.substitutions.length == 0; recursion should stop at this point. can this lead to unexpected result?
        // answer: actually this in my opinion is an optimisation
        for (uint256 i = 0; i < node.substitutions.length; i++) {
            Bytes32AndIndex memory pointer = node.substitutions[i];
            bool cacheHit;

            for (uint256 j = 0; j < cache.length; j++) {
                if (cache[j].key == pointer.value) {
                    execArgumentsArraified[pointer.index] = cache[j].evaluationResult;
                    cacheHit = true;
                    break;
                }
            }

            if (cacheHit) continue;

            Node memory subsequentNode = getNodeById(pointer.value);

            bytes memory subsequentResult = evaluateRecursively(
                subsequentNode,
                variables,
                cache,
                lastCacheRecord + 1
            );

            execArgumentsArraified[pointer.index] = subsequentResult;

            cache[lastCacheRecord] = CacheRecord({
                key: subsequentNode.id,
                evaluationResult: subsequentResult
            });
        }

        result = instance.exec(execArgumentsArraified);
    }

    function nodesCount() public view returns (uint256) {
        return nodes.length;
    }

    // nodeByIndex
    function getNode(uint256 index) public view returns (Node memory) {
        require(index < nodes.length, NODE_INDEX_NOT_EXISTS_ERR);
        return nodes[index];
    }

    function getNodes() public view returns (Node[] memory) {
        return nodes;
    }

    // nodeById
    function getNodeById(bytes32 id) public view returns (Node memory) {
        require(id != bytes32(0), PROVIDED_NODE_REFERENCE_IS_NIL_ERR);
        uint256 nodeIndex = idToIndex[id];

        require(nodeIndex > 0, NODE_NOT_EXISTS_ERR);
        return getNode(nodeIndex);
    }
}
