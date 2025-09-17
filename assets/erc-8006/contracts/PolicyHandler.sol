//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { ExecVariables, InitParams as PolicyInitParams } from "./types/MainTypes.sol";
import { ExecVarsMetadata } from "./types/UtilTypes.sol";
import "./utils/ValidationUtils.sol" as PolicyHandlerValidator;
import { OwnerBase } from "./utils/OwnerBase.sol";
import { MAX_NODES_LENGTH } from "./constants/Constants.sol";
import { DAGWithPolicyMetadata } from "./inheritance/DAGWithPolicyMetadata.sol";
import "./utils/MiscUtils.sol" as HelperUtils;
import {
    POLICY_DOES_NOT_HAVE_ANY_ARTIFACT_ERR,
    INIT_NODES_LIST_IS_LARGER_THAN_MAX_LENGTH_ERR,
    POLICY_ALREADY_INITIALIZED_ERR,
    POLICY_NOT_INITIALIZED_ERR
} from "./constants/ErrorCodes.sol";
import { IPolicyHandler } from "./interfaces/IPolicyHandler.sol";

/// @title Policy Handler
/// @notice Handles policy initialization, reset, and evaluation with rule-based artifact processing
/// @dev Main contract for managing and evaluating policy rules using DAG-based artifact relationships:
///      - Implements IPolicyHandler interface
///      - Extends OwnerBase for access control
contract PolicyHandler is IPolicyHandler, OwnerBase {
    DAGWithPolicyMetadata internal dag;
    bool private isInitialized = false;

    /// @notice Initializes the PolicyHandler with an admin user
    /// @dev Sets up the contract with owner-based access control
    /// @param _adminUser The address that will have admin privileges
    constructor(address _adminUser) OwnerBase(_adminUser) {}

    /// @notice Initializes policy handler with rules (list of linked artifacts)
    /// @param params Policy initialization parameters containing nodes and configuration
    /// @dev Creates new DAG instance and sets up policy configuration for the first time:
    ///      - Emits Set event with root node ID and number of nodes
    function set(PolicyInitParams memory params) public onlyOwner {
        PolicyHandlerValidator.boolIsFalsyWithErr(isInitialized, POLICY_ALREADY_INITIALIZED_ERR);

        _set(params);

        emit Set(dag.rootNodeId(), params.nodes.length);
    }

    /// @notice Re-initializes policy handler with rules (list of linked artifacts)
    /// @param params Policy initialization parameters containing nodes and configuration
    /// @dev Abandons previous configuration and creates new policy setup:
    ///      - Emits Upgraded event with new root node ID and number of nodes
    function reset(PolicyInitParams memory params) public onlyOwner {
        PolicyHandlerValidator.boolIsTruthyWithErr(isInitialized, POLICY_NOT_INITIALIZED_ERR);

        _set(params);

        emit Upgraded(dag.rootNodeId(), params.nodes.length);
    }

    /// @notice Evaluates the policy check result by traversing all graph starting from root node
    /// @param variables Array of execution variables to be passed to policy artifacts
    /// @return result Boolean result of the policy evaluation
    /// @dev Artifact input params "variables" are forwarded to respective artifacts during evaluation:
    ///      - Emits Evaluated event with result and root node ID
    function evaluate(ExecVariables[] memory variables) public onlyOwner returns (bool result) {
        bytes memory encodedResult = dag.evaluateRecursively(dag.rootNodeId(), variables);

        result = abi.decode(encodedResult, (bool));

        emit Evaluated(result, dag.rootNodeId());
    }

    /// @notice Returns arguments list for runtime-supplied parameters to particular nodes
    /// @dev Retrieves variable descriptions from all nodes in the DAG structure (relate only to those node that require run-time supplied args)
    /// @return list Array of execution variable metadata for runtime parameters
    function getVariablesList() public view returns (ExecVarsMetadata[] memory list) {
        PolicyHandlerValidator.boolIsTruthyWithErr(isInitialized, POLICY_NOT_INITIALIZED_ERR);

        list = HelperUtils.getVarsDesriptionList(dag.getNodes());
    }

    /// @notice Internal function to set up policy configuration
    /// @dev Creates new DAG instance with policy metadata and initializes it
    /// @param params Policy initialization parameters containing nodes and configuration
    function _set(PolicyInitParams memory params) internal onlyOwner {
        PolicyHandlerValidator.boolIsTruthyWithErr(
            params.nodes.length > 0,
            POLICY_DOES_NOT_HAVE_ANY_ARTIFACT_ERR
        );
        // Prevents call stack depth overflow by limiting nodes length
        // link: https://ethereum.stackexchange.com/questions/142102/solidity-1024-call-stack-depth
        PolicyHandlerValidator.boolIsTruthyWithErr(
            params.nodes.length <= MAX_NODES_LENGTH,
            INIT_NODES_LIST_IS_LARGER_THAN_MAX_LENGTH_ERR
        );

        dag = new DAGWithPolicyMetadata(address(this));
        dag.init(params);

        isInitialized = true;
    }
}
