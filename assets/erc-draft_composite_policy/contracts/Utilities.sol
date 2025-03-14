//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.27;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Node, Argument, NamedTypedVariables } from "./Types.sol";
import { NODE_VARIABLES_LIST_LENGTH_VIOLATES_DESCRIPTOR_ERR } from "./Errors.sol";
import { IArbitraryDataArtifact } from "./pre-defined/common/basis/interfaces/Export.sol";

function getVariablesListInternal(
    Node[] memory nodesList
) pure returns (NamedTypedVariables[] memory variablesList) {
    variablesList = new NamedTypedVariables[](nodesList.length - 1);

    for (uint256 i = 0; i < nodesList.length - 1; i++) {
        Node memory node = nodesList[i + 1];

        (string[] memory argNames, string[] memory argTypes, ) = toArtifactInstance(node)
            .getExecDescriptor();

        NamedTypedVariables memory variablesOfNode = variablesList[i];
        variablesOfNode.nodeId = node.id;
        variablesOfNode.artifactAddress = node.implementationContractAddress;
        variablesOfNode.injections = node.injections;
        variablesOfNode.nodeIndex = i;

        require(
            argNames.length >= node.variables.length,
            NODE_VARIABLES_LIST_LENGTH_VIOLATES_DESCRIPTOR_ERR
        );
        variablesOfNode.variables = new Argument[](node.variables.length);

        for (uint256 j = 0; j < node.variables.length; j++) {
            uint256 variableIndex = node.variables[j];

            variablesOfNode.variables[j] = Argument({
                name: argNames[variableIndex],
                typename: argTypes[variableIndex]
            });
        }
    }
}

function toArtifactInstance(Node memory node) pure returns (IArbitraryDataArtifact instance) {
    instance = toArtifactInstance(node.implementationContractAddress);
}

function toArtifactInstance(address artifact) pure returns (IArbitraryDataArtifact instance) {
    instance = IArbitraryDataArtifact(artifact);
}

function deployArtifact(Node memory node) returns (address cloned) {
    // note: makes a fast copy using Clone-Factory pattern; also gas consumption is great
    cloned = Clones.clone(node.artifactContractAddress);
}
