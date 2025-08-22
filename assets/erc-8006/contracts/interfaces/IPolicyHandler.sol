//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { ExecVariables, InitParams as PolicyInitParams } from "../types/MainTypes.sol";
import { ExecVarsMetadata } from "../types/UtilTypes.sol";

interface IPolicyHandler {
    /**
     * @dev Events that should be emitted by the implementation
     */
    event Evaluated(bool indexed result, bytes32 indexed rootNode);
    event Set(bytes32 indexed rootNodeId, uint256 indexed nodesCount);
    event Upgraded(bytes32 indexed rootNodeId, uint256 indexed nodesCount);

    /**
     * @notice Initializes the policy handler with rules (list of linked artifacts)
     * @param params Initialization parameters containing nodes and root node
     */
    function set(PolicyInitParams memory params) external;

    /**
     * @notice Re-initializes the policy handler with new rules, abandoning previous configuration
     * @param params Initialization parameters containing nodes and root node
     */
    function reset(PolicyInitParams memory params) external;

    /**
     * @notice Evaluates the policy check result by traversing the graph from root node
     * @param variables Runtime variables to be forwarded to respective artifacts
     * @return result The evaluation result
     */
    function evaluate(ExecVariables[] memory variables) external returns (bool result);

    /**
     * @notice Returns the list of run-time arguments that need to be supplied to nodes
     * @return list Array of variable metadata descriptions
     */
    function getVariablesList() external view returns (ExecVarsMetadata[] memory list);
}
