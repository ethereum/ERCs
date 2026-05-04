// SPDX-License-Identifier: GPL3
pragma solidity ^0.8.20;

import {IERC165} from "./interfaces/IERC165.sol";
import {IERC7656Service} from "./interfaces/IERC7656Service.sol";

import {ERC7656ServiceLib} from "./lib/ERC7656ServiceLib.sol";

/**
 * @title ERC7656Service.sol
 */
contract ERC7656Service is IERC7656Service, IERC165 {
  function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
    return interfaceId == type(IERC7656Service).interfaceId || interfaceId == type(IERC165).interfaceId;
  }

  /**
   * @notice Returns the linkedContract linked to the contract
   */
  function linkedData() public view virtual override returns (uint256, bytes12, address, uint256) {
    return _linkedData();
  }

  /**
   * Private functions
   */

  function _linkedData() internal view returns (uint256, bytes12, address, uint256) {
    return ERC7656ServiceLib.linkedData(address(this));
  }

}
