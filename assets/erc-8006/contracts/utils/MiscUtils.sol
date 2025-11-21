//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ArgumentDescription, ExecVarsMetadata } from "../types/UtilTypes.sol";
import { Node as ConfiguredNode, ExecVariables } from "../types/MainTypes.sol";
import { IArbitraryDataArtifact } from "../standard/common/basis/Export.sol";

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

function deployArtifact(ConfiguredNode memory rule) returns (address cloned) {
    // note: makes a fast copy using Clone-Factory pattern; also gas consumption is great
    cloned = Clones.clone(rule.originalArtifact);
}

function filterVariablesByNodeId(
    ExecVariables[] memory variableValuesList,
    bytes32 nodeId
) pure returns (bytes[] memory suppliedVars) {
    for (uint256 i = 0; i < variableValuesList.length; i++) {
        if (variableValuesList[i].nodeId == nodeId) {
            suppliedVars = variableValuesList[i].values;
            break;
        }
    }
}
