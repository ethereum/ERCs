// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "./IDataRegistry.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IVerifiedComputing} from "../../verifiedComputing/interfaces/IVerifiedComputing.sol";

/**
 * @title Storage for DataRegistry
 * @notice For future upgrades, do not change DataRegistryStorageV1. Create a new
 * contract which implements DataRegistryStorageV1
 */
abstract contract DataRegistryStorageV1 is IDataRegistry {
    string public override name;
    uint256 public override filesCount;
    DataAnchoringToken public override token;
    IVerifiedComputing public override verifiedComputing;
    string public override publicKey;
    mapping(uint256 fileId => File) internal _files;
    mapping(bytes32 => uint256) internal _urlHashToFileId;
}
