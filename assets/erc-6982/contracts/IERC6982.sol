// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.9;

// ERC165 interfaceId 0x6b61a747
interface IERC6982 {
  /**
   * @dev MUST be emitted when the contract is deployed to establish the default lock status
   *      for all tokens. Also, MUST be emitted again if the default lock status changes,
   *      to ensure the default status for all tokens (without a specific `Locked` event) is updated.
   */
  event DefaultLocked(bool locked);

  /**
   * @dev MUST be emitted when the lock status of a specific token changes.
   *      This status overrides the default lock status for that specific token.
   */
  event Locked(uint256 indexed tokenId, bool locked);

  /**
   * @dev Returns the current default lock status for tokens.
   *      The returned value MUST reflect the status indicated by the most recent `DefaultLocked` event.
   */
  function defaultLocked() external view returns (bool);

  /**
   * @dev Returns the lock status of a specific token.
   *      If no `Locked` event has been emitted for the token, it MUST return the current default lock status.
   *      The function MUST revert if the token does not exist.
   */
  function locked(uint256 tokenId) external view returns (bool);
}
