// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.6;

import "../interfaces/IERC7635.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

/**
* @title ERC-7635 Semi-Fungible Token Standard, optional metadata extension
*  Note: the ERC-165 identifier for this interface is 0xe1600902.
*/
interface IERC7635Metadata is IERC7635, IERC721Metadata {
    /**
     * @notice Returns the Uniform Resource Identifier (URI) for the current contract.
     * @dev This function SHOULD return the URI for this contract in JSON format, starting with
     *  header `data:application/json;`.

     * @return The JSON formatted URI of the current MFT contract
     */
    function contractURI() external view returns (string memory);

    /**
     * @notice Returns the Uniform Resource Identifier (URI) for the specified slot.
     * @dev This function SHOULD return the URI for `_slot` in JSON format, starting with header
     *  `data:application/json;`.
     * @return The JSON formatted URI of `_slot`
     */
    function slotURI(uint256 _slot) external view returns (string memory);
}
