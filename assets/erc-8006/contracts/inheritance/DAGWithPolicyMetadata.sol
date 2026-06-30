//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { InternalContainerDAG } from "../data-structures/DAG/InternalContainerDAG.sol";
import "../utils/MiscUtils.sol" as HelperUtils;
import "../data-structures/DAG/utils/ValidationUtils.sol" as DAGValidation;
import {
    ExecVariables,
    SubstitutionArgument,
    ConstantArgument,
    Node as ConfiguredNode,
    NodeInitData,
    InitParams as DAGInitParams
} from "../types/MainTypes.sol";
import { NodeConfig } from "../types/UtilTypes.sol";
import { OwnerBase } from "../utils/OwnerBase.sol";
import {
    DAG_HAS_DICONNECTED_NODES_CLUSTER_ERR,
    DAG_HAS_CYLE_ERR,
    DAG_IS_INITED_ERR
} from "../constants/ErrorCodes.sol";
import { exractNodesConfig as exractDagNodesConfig } from "../utils/PreProcessUtils.sol";
import { IArbitraryDataArtifact } from "../standard/common/basis/Export.sol";
import {
    SUPPLIED_VARIABLES_LIST_LENGTH_NOT_MATCHES_EXPECTED_LENGTH_ERR
} from "../constants/ErrorCodes.sol";

/// @title DAG with Policy Metadata
/// @notice Manages policy-configured DAG nodes with artifact evaluation and variable substitution
/// @dev Contract that extends DAG functionality with policy rules and metadata management:
///      - Inherits from InternalContainerDAG for DAG operations
///      - Inherits from OwnerBase for access control
contract DAGWithPolicyMetadata is InternalContainerDAG, OwnerBase {
    uint256 internal _rootNodeId;

    // note: policy-related metadata/config/params tied to particular ConfiguredNode of DAG
    mapping(uint256 nodeId => ConfiguredNode configuredRule) internal policyRulesMap;

    /// @notice Initializes the DAGWithPolicyMetadata contract with an admin user
    /// @dev Sets up the contract with owner-based access control
    /// @param _admin The address that will have admin privileges for the contract
    constructor(address _admin) OwnerBase(_admin) {}

    /// @notice Initializes the DAG with policy metadata using provided configuration parameters
    /// @param initParams Initialization parameters containing nodes configuration and root node ID
    /// @dev Sets up nodes, edges, validates DAG structure, establishes policy rules, and sets root node:
    ///      - Validates that DAG is acyclic and has no disconnected clusters starting from root node
    function init(DAGInitParams calldata initParams) public onlyOwner {
        DAGValidation.boolIsTruthyWithErr(_rootNodeId == 0, DAG_IS_INITED_ERR);

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

    /// @notice Traverses the graph and fills its metadata with missing parameters, then unfolds it with evaluation steps up to the root node value
    /// @param nodeId The ID of the node to start evaluation from
    /// @param variableValuesList Runtime-supplied variables for each node in the evaluation chain
    /// @return result The encoded execution result from the artifact evaluation
    /// @dev Processes node arguments by filling variables, constants, and substitutions, then executes the artifact:
    ///      - Creates a general arguments list containing known constants, applied substitutions, and runtime variable values
    function evaluateRecursively(
        bytes32 nodeId,
        ExecVariables[] memory variableValuesList // vars for each node
    ) public onlyOwner returns (bytes memory result) {
        ConfiguredNode memory rule = _getPolicyRule(nodeId);
        // note: general list containing the all values of Node, which
        // contains known constants, applied substitutions, run-time supplied variable-values
        bytes[] memory generalArgumentsList = new bytes[](rule.argsCount);

        fillVariableArguments(rule, generalArgumentsList, variableValuesList);

        fillConstantArguments(rule, generalArgumentsList);

        fillSubstitutedArguments(rule, generalArgumentsList, variableValuesList);

        IArbitraryDataArtifact instance = HelperUtils.toArtifactInstance(rule);
        result = instance.exec(generalArgumentsList);
    }

    /// @notice Retrieves all configured nodes in the DAG with their policy metadata
    /// @dev Iterates through all node IDs and returns their corresponding configured rules
    /// @return list Array of ConfiguredNode structures containing policy rules for each node
    function getNodes() public view returns (ConfiguredNode[] memory list) {
        uint256[] memory nodeIds = _getAllNodes();
        list = new ConfiguredNode[](nodeIds.length);

        for (uint256 i = 0; i < nodeIds.length; i++) {
            bytes32 nodeId = bytes32(nodeIds[i]);
            list[i] = _getPolicyRule(nodeId);
        }
    }

    /// @notice Returns the root node ID of the DAG
    /// @dev Converts the internal uint256 root node ID to bytes32 format
    /// @return bytes32 The root node identifier
    function rootNodeId() public view returns (bytes32) {
        return bytes32(_rootNodeId);
    }

    function _assignNodes(NodeConfig[] memory configList) private {
        for (uint256 i = 0; i < configList.length; i++) {
            bytes32 nodeId = configList[i].node;

            // note: prevents nullable, duplicated nodes
            _addNode(nodeId);
        }
    }

    function _setEdges(NodeConfig[] memory configList) private {
        for (uint256 i = 0; i < configList.length; i++) {
            bytes32 parentNodeId = configList[i].node;

            bytes32[] memory childNodeIds = configList[i].childNodes;

            for (uint256 j = 0; j < childNodeIds.length; j++) {
                bytes32 childNodeId = childNodeIds[j];
                // note: detect and prevent self-cycle edges and duplicated edges
                _addEdge(parentNodeId, childNodeId);
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

    function _setRuleId(ConfiguredNode storage rule, bytes32 id) private {
        rule.id = id;
    }

    function maybeCreateArtifactState(
        ConfiguredNode storage rule,
        NodeInitData memory params
    ) private {
        rule.originalArtifact = params.artifactAddress;
        rule.clonedArtifact = params.artifactAddress; // will remain the same if STATELESS

        // note: when artifact is STATEFULL it means it must allocate/init/consume a new, isolated dedicated state variables
        if (params.needsInitialization) {
            address newInstance = HelperUtils.deployArtifact(rule);
            HelperUtils.toArtifactInstance(newInstance).init(params.initData);

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
        DAGValidation.argsCountMatches(rule, params.argsCount);

        rule.argsCount = params.argsCount;
    }

    function fillSubstitutedArguments(
        ConfiguredNode memory rule,
        bytes[] memory argsList,
        ExecVariables[] memory variableValuesList
    ) private {
        // note: retrieve evaluation results of each child node and use them as Substitions in Exec arguments list of the currently processed one
        for (uint256 i = 0; i < rule.substitutedExecArgs.length; i++) {
            SubstitutionArgument memory substituting = rule.substitutedExecArgs[i];

            bytes32 childNodeId = substituting.supplierNodeId;

            bytes memory childNodeExecResult = evaluateRecursively(childNodeId, variableValuesList);

            argsList[substituting.index] = childNodeExecResult;
        }
    }

    function _getPolicyRule(bytes32 nodeId) private view returns (ConfiguredNode storage rule) {
        // note: no mapping-value-exist validations, since it always operates with known ids

        rule = policyRulesMap[uint256(nodeId)];
    }

    function fillVariableArguments(
        ConfiguredNode memory rule,
        bytes[] memory argsList,
        ExecVariables[] memory variableValuesList
    ) private pure {
        bytes[] memory nodeVars = HelperUtils.filterVariablesByNodeId(variableValuesList, rule.id);

        // note: this validates 'variableValuesList' eventually contains all run-time required vars for a given node-id
        DAGValidation.boolIsTruthyWithErr(
            rule.variableExecArgs.length == nodeVars.length,
            SUPPLIED_VARIABLES_LIST_LENGTH_NOT_MATCHES_EXPECTED_LENGTH_ERR
        );

        // note: writing run-time supplied Variables to Exec arguments
        for (uint256 i = 0; i < rule.variableExecArgs.length; i++) {
            uint256 pos = rule.variableExecArgs[i];
            argsList[pos] = nodeVars[i];
        }
    }

    function fillConstantArguments(
        ConfiguredNode memory rule,
        bytes[] memory argsList
    ) private pure {
        // note: writing Constans to exec arguments
        for (uint256 i = 0; i < rule.constantExecArgs.length; i++) {
            ConstantArgument memory arg = rule.constantExecArgs[i];
            uint256 pos = arg.index;
            argsList[pos] = arg.value;
        }
    }
}
