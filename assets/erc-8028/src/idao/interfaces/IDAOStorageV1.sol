// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "./IIDAO.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title Storage for IDAO
 * @notice For future upgrades, do not change IDAOStorageV1. Create a new
 * contract which implements IDAOStorageV1
 */
abstract contract IDAOStorageV1 is IIDAO {
    string public override name;
    string public override description;
    DataAnchoringToken public override token;
    IVerifiedComputing public override verifiedComputing;
    ISettlement public override settlement;
}
