//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ArgumentDescription, ExecVarsMetadata } from "./UtilTypes.sol";
import { Node as ConfiguredNode, ExecVariables } from "./Types.sol";
import { NODE_VARIABLES_LIST_LENGTH_VIOLATES_DESCRIPTOR_ERR } from "./Errors.sol";
import { IArbitraryDataArtifact } from "./erc-8006/interfaces/Interfaces.sol";

function getVarsDesriptionList(
    ConfiguredNode[] memory nodesList
) pure returns (ExecVarsMetadata[] memory varsList) {
    varsList = new ExecVarsMetadata[](nodesList.length - 1);

    for (uint256 i = 0; i < nodesList.length - 1; i++) {
        ConfiguredNode memory rule = nodesList[i + 1];

        (string[] memory argNames, string[] memory argTypes, ) = toArtifactInstance(rule)
            .getExecDescriptor();

        ExecVarsMetadata memory vars = varsList[i];
        vars.nodeIndex = i;
        vars.nodeId = rule.id;
        vars.artifactAddress = rule.clonedArtifact;
        vars.injections = rule.injections;

        // THIS IS REDUNDANT CHECK: since there is no need to check the condition on already configured DAG/Nodes
        // require(
        //     argNames.length >= rule.variableExecArgs.length,
        //     NODE_VARIABLES_LIST_LENGTH_VIOLATES_DESCRIPTOR_ERR
        // );

        vars.descriptions = new ArgumentDescription[](rule.variableExecArgs.length);

        for (uint256 j = 0; j < rule.variableExecArgs.length; j++) {
            uint256 variablePosInTotalArgsList = rule.variableExecArgs[j];

            vars.descriptions[j] = ArgumentDescription({
                typename: argTypes[variablePosInTotalArgsList],
                name: argNames[variablePosInTotalArgsList]
            });
        }
    }
}

function toArtifactInstance(
    ConfiguredNode memory rule
) pure returns (IArbitraryDataArtifact instance) {
    instance = toArtifactInstance(rule.clonedArtifact);
}

function toArtifactInstance(address artifact) pure returns (IArbitraryDataArtifact instance) {
    instance = IArbitraryDataArtifact(artifact);
}

function deployArtifact(ConfiguredNode memory rule) returns (address artifact) {
    artifact = cloneContract(rule.originalArtifact);
}

function cloneContract(address implementation) returns (address cloneInstance) {
    // note: makes a fast copy using Clone-Factory pattern; also gas consumption is great
    cloneInstance = Clones.clone(implementation);
}

function filterSpecificNodeVariables(
    ExecVariables[] memory variableValuesList,
    bytes32 nodeId
) pure returns (bytes[] memory suppliedVars) {
    // important: if artifact a requires artifact d and artifact b requires artifact d, then it is prohibited
    // the same instance of artifact d can not be re-used by multiple artifacts. motivation: this will simplify evertyhing

    for (uint256 i = 0; i < variableValuesList.length; i++) {
        // todo: maybe something more efficient;
        // when transient storage for reference type the approach could be as follows:
        // if variableValuesList[i] is consumed, then it is removed from the 'variableValuesList' array

        if (variableValuesList[i].nodeId == nodeId) {
            suppliedVars = variableValuesList[i].values;
            break;
        }
    }
}
