// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IVerifiedComputing} from "../../verifiedComputing/interfaces/IVerifiedComputing.sol";
import {ISettlement} from "../../settlement/interfaces/ISettlement.sol";
import {DataAnchoringToken} from "../../dat/DataAnchoringToken.sol";

interface IIDAO {
    function name() external view returns (string memory);
    function description() external view returns (string memory);
    function version() external pure returns (uint256);

    function token() external view returns (DataAnchoringToken);
    function updateToken(address newToken) external;

    function verifiedComputing() external view returns (IVerifiedComputing);
    function updateVerifiedComputing(address newVerifiedComputing) external;

    function settlement() external view returns (ISettlement);
    function updateSettlement(address newSettlement) external;

    function pause() external;
    function unpause() external;
}
