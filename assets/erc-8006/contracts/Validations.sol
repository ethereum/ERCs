//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.27;

import { Node } from "./Types.sol";
// import {
//     ARTIFACT_INSTANCE_NOT_IMPLEMENTS_ERC165_INTERFACE_ERR,
//     ARTIFACT_INSTANCE_NOT_SUPPORTS_REQUIRED_INTERFACE_ERR,
//     INCORRECT_NODE_ARGUMENTS_NUMBER_IS_SUPPLIED_ERR
// } from "./Errors.sol";
import { INCORRECT_NODE_ARGUMENTS_NUMBER_IS_SUPPLIED_ERR } from "./Errors.sol";
// import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
// import { ERC165_INTERFACE_ID, ARBITRARY_DATA_ARTIFACT_INTERFACE_ID } from "./Constants.sol";

function validateAddressIsArtifact(address artifactAddress) pure returns (address validated) {
    /* solhint-disable-next-line no-empty-blocks */
    // try IERC165(artifactAddress).supportsInterface(ERC165_INTERFACE_ID) {
    //     //
    // } catch {
    //     revert(ARTIFACT_INSTANCE_NOT_IMPLEMENTS_ERC165_INTERFACE_ERR);
    // }
    // bool isSupported = IERC165(artifactAddress).supportsInterface(
    //     ARBITRARY_DATA_ARTIFACT_INTERFACE_ID
    // );
    // require(isSupported, ARTIFACT_INSTANCE_NOT_SUPPORTS_REQUIRED_INTERFACE_ERR);
    validated = artifactAddress;
}

function validateArgsCount(Node memory node, uint256 argsCount) pure {
    uint256 suppliedArgsCount = node.partialExecData.length +
        node.substitutions.length +
        node.variables.length;
    require(argsCount == suppliedArgsCount, INCORRECT_NODE_ARGUMENTS_NUMBER_IS_SUPPLIED_ERR);
}
