// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC7656Service.sol.sol.sol
 *   InterfaceId 0xfc0c546a
 */
interface IERC7656Service {
  /**
   * @notice Returns the token linked to the contract
   * @return chainId The chainId where the linked contract is deployed
   * @return mode The mode of the link (with or without linkedId)
   * @return linkedContract The address of the linked contract
   * @return linkedId The id of the linked contract (for example, a tokenId)
   */
  function linkedData() external view returns (uint256 chainId, bytes12 mode, address linkedContract, uint256 linkedId);
}
