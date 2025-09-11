//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { IArbitraryDataArtifact } from "../standard/common/basis/Export.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

uint256 constant MAX_NODES_LENGTH = 256;
bytes4 constant ERC165_INTERFACE_ID = type(IERC165).interfaceId;
bytes4 constant ARBITRARY_DATA_ARTIFACT_INTERFACE_ID = type(IArbitraryDataArtifact).interfaceId;
