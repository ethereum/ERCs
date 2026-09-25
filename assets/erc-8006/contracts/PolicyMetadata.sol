//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { InternalContainerDAG } from "./data-structures/InternalContainerDAG.sol";
import "./Validations.sol" as PolicyRulesValidator;
import "./Utilities.sol" as Utils;
import "./data-structures/utils/Validations.sol" as DAGValidation;
import { Node as ConfiguredNode, NodeInitData, InitParams as DAGInitParams } from "./Types.sol";
import { NodeConfig } from "./UtilTypes.sol";
import { OwnerBase } from "./OwnerBase.sol";
import {
    DAG_HAS_DICONNECTED_NODES_CLUSTER_ERR,
    DAG_HAS_CYLE_ERR,
    DAG_IS_INITED_ERR
} from "./Errors.sol";
import { exractNodesConfig as exractDagNodesConfig } from "./PreProcessUtils.sol";
import { ExecVariables, SubstitutionArgument, ConstantArgument } from "./Types.sol";
import { IArbitraryDataArtifact } from "./erc-8006/interfaces/Interfaces.sol";
import { SUPPLIED_VARIABLES_LIST_LENGTH_NOT_MATCHES_EXPECTED_LENGTH_ERR } from "./Errors.sol";

contract PolicyMetadata is InternalContainerDAG, OwnerBase {
    uint256 internal _rootNodeId;
    // policy-related metadata/config/params tied to particular ConfiguredNode of DAG
    mapping(uint256 nodeId => ConfiguredNode configuredRule) internal policyRulesMap;

    constructor(address admin) OwnerBase(admin) {}

    function init(DAGInitParams calldata initParams) public onlyOwner {
        require(_rootNodeId == 0, DAG_IS_INITED_ERR);

        NodeInitData[] calldata nodesInitParamsList = initParams.nodes;
        NodeConfig[] memory nodesConfigList = exractDagNodesConfig(nodesInitParamsList);

        _assignNodes(nodesConfigList);

        _setEdges(nodesConfigList);

        DAGValidation.boolIsFalsyWithErr(_hasCycle(), DAG_HAS_CYLE_ERR);

        _establishPolicyRules(nodesInitParamsList);

        _setRootNode(initParams.rootNode);

        DAGValidation.boolIsFalsyWithErr(
            _hasDisconnectedCluster(initParams.rootNode),
            DAG_HAS_DICONNECTED_NODES_CLUSTER_ERR
        );
    }

    function getNodes() public view returns (ConfiguredNode[] memory list) {
        uint256[] memory nodeIds = _getAllNodes();
        list = new ConfiguredNode[](nodeIds.length);

        for (uint256 i = 0; i < nodeIds.length; i++) {
            bytes32 nodeId = bytes32(nodeIds[i]);
            list[i] = _getPolicyRule(nodeId);
        }
    }

    function rootNodeId() public view returns (bytes32) {
        return bytes32(_rootNodeId);
    }

    function _assignNodes(NodeConfig[] memory configList) private {
        for (uint256 i = 0; i < configList.length; i++) {
            bytes32 nodeId = configList[i].node;

            _addNode(nodeId); // prevents nullable, duplicated nodes
        }
    }

    function _setEdges(NodeConfig[] memory configList) private {
        for (uint256 i = 0; i < configList.length; i++) {
            bytes32 parentNodeId = configList[i].node;

            bytes32[] memory childNodeIds = configList[i].childNodes;

            for (uint256 j = 0; j < childNodeIds.length; j++) {
                bytes32 childNodeId = childNodeIds[j];
                _addEdge(parentNodeId, childNodeId); // prevents self-cycle edges and duplicated edges
            }
        }
    }

    function _establishPolicyRules(NodeInitData[] memory nodesInitParamsList) private {
        for (uint256 i = 0; i < nodesInitParamsList.length; i++) {
            _establishRule(nodesInitParamsList[i]);
        }
    }

    function _establishRule(NodeInitData memory initParams) private {
        ConfiguredNode storage rule = _getPolicyRule(initParams.id);

        _setRuleId(rule, initParams.id);

        maybeCreateArtifactState(rule, initParams);

        setNodeConstants(rule, initParams);

        setNodeVariables(rule, initParams);

        setNodeInjections(rule, initParams);

        setNodeSubstibutions(rule, initParams);

        // note: this has to be the final setter call in the method body; order matters
        setArgsCount(rule, initParams);
    }

    function _setRootNode(bytes32 rootNodeIdValue) private {
        _getNode(rootNodeIdValue); // fails if node does not exist

        _rootNodeId = uint256(rootNodeIdValue);
    }

    //

    function _setRuleId(ConfiguredNode storage rule, bytes32 id) private {
        rule.id = id;
    }

    function maybeCreateArtifactState(
        ConfiguredNode storage rule,
        NodeInitData memory params
    ) private {
        // note: if this is an instance of IArbitraryDataArtifact it has to be erc165-compatible
        rule.originalArtifact = PolicyRulesValidator.validateAddressIsArtifact(
            params.artifactAddress
        );

        // note: when the artifact is STATELESS, it is ok to rely on shared state (between other artifacts users)
        rule.clonedArtifact = rule.originalArtifact;

        // note: when artifact is STATEFULL it means it must allocate/init/consume a new isolated state variables
        if (params.needsInitialization) {
            address newInstance = Utils.deployArtifact(rule);
            Utils.toArtifactInstance(newInstance).init(params.initData);

            rule.clonedArtifact = newInstance;
        }
    }

    function setNodeConstants(ConfiguredNode storage rule, NodeInitData memory params) private {
        for (uint256 i = 0; i < params.constantExecArgs.length; i++) {
            rule.constantExecArgs.push(params.constantExecArgs[i]);
        }
    }

    function setNodeVariables(ConfiguredNode storage rule, NodeInitData memory params) private {
        for (uint256 i = 0; i < params.variableExecArgs.length; i++) {
            rule.variableExecArgs.push(params.variableExecArgs[i]);
        }
    }

    function setNodeSubstibutions(ConfiguredNode storage rule, NodeInitData memory params) private {
        // todo: validate (AT HIGHER LEVEL) artifact assigned to "params.substitutedExecArgs[i].supplierNodeId" returns the
        // desired type matches with "rule.clonedArtifact.getExecDescriptor" type at the same index

        for (uint256 i = 0; i < params.substitutedExecArgs.length; i++) {
            rule.substitutedExecArgs.push(params.substitutedExecArgs[i]);
        }
    }

    function setNodeInjections(ConfiguredNode storage rule, NodeInitData memory params) private {
        for (uint256 i = 0; i < params.injections.length; i++) {
            rule.injections.push(params.injections[i]);
        }
    }

    function setArgsCount(ConfiguredNode storage rule, NodeInitData memory params) private {
        PolicyRulesValidator.validateArgsCount(rule, params.argsCount);

        rule.argsCount = params.argsCount;
    }

    function _getPolicyRule(bytes32 nodeId) private view returns (ConfiguredNode storage rule) {
        // note: no mapping-value-exist validations required, since it always operates with known ids

        rule = policyRulesMap[uint256(nodeId)];
    }

    /* // */

    // note: Traverses the graph and fills its metadata with missing parameters, then enfols it with evaluation steps up to the root node value.
    function evaluateRecursively(
        bytes32 nodeId,
        ExecVariables[] memory variableValuesList // vars for each node
    ) public onlyOwner returns (bytes memory result) {
        ConfiguredNode memory rule = _getPolicyRule(nodeId);
        // note: general list containing the all values of Node
        // (known constants, applied substitutions, run-time supplied variable-values)
        bytes[] memory generalArgumentsList = new bytes[](rule.argsCount);

        fillVariableArguments(rule, generalArgumentsList, variableValuesList);

        fillConstantArguments(rule, generalArgumentsList);

        fillSubstitutedArguments(rule, generalArgumentsList, variableValuesList);

        IArbitraryDataArtifact instance = Utils.toArtifactInstance(rule);
        result = instance.exec(generalArgumentsList);
    }

    function fillSubstitutedArguments(
        ConfiguredNode memory rule,
        bytes[] memory argsList,
        ExecVariables[] memory variableValuesList
    ) private {
        /* note about caching: cache has to be avoided since some artifatcs may have sensitive state 
            to incoming exec calls, therefore, if there are at least two calls for the same artifact instance during the
            recursion, then cache becomes invalide and its purpose fails */

        // note: writting evaluation results of each child node as exec arguments of the currently processed one
        for (uint256 i = 0; i < rule.substitutedExecArgs.length; i++) {
            SubstitutionArgument memory substituting = rule.substitutedExecArgs[i];

            bytes32 childNodeId = substituting.supplierNodeId;

            bytes memory childNodeExecResult = evaluateRecursively(childNodeId, variableValuesList);

            argsList[substituting.index] = childNodeExecResult;
        }
    }

    function fillVariableArguments(
        ConfiguredNode memory rule,
        bytes[] memory argsList,
        ExecVariables[] memory variableValuesList
    ) private pure {
        bytes[] memory nodeVars = Utils.filterSpecificNodeVariables(variableValuesList, rule.id);

        // note: this validates 'variableValuesList' eventually contains all run-time required vars for a given node-id
        require(
            rule.variableExecArgs.length == nodeVars.length,
            SUPPLIED_VARIABLES_LIST_LENGTH_NOT_MATCHES_EXPECTED_LENGTH_ERR
        );

        // note: writing run-time supplied variables to exec arguments
        for (uint256 i = 0; i < rule.variableExecArgs.length; i++) {
            uint256 pos = rule.variableExecArgs[i];
            argsList[pos] = nodeVars[i];
        }
    }

    function fillConstantArguments(
        ConfiguredNode memory rule,
        bytes[] memory argsList
    ) private pure {
        // note: writing constans to exec arguments
        for (uint256 i = 0; i < rule.constantExecArgs.length; i++) {
            ConstantArgument memory arg = rule.constantExecArgs[i];
            uint256 pos = arg.index;
            argsList[pos] = arg.value;
        }
    }
}
