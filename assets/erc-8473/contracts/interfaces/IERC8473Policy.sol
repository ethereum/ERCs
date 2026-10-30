// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

/// @dev The only value a check returns to permit. Every other value, including zero, rejects.
bytes32 constant TRANSFER_OK = keccak256('TRANSFER_OK');

/**
 * @title IERC8473Policy
 * @notice Decides whether an account may send or receive an ERC-7943 token, and whether a movement of it may happen
 */
interface IERC8473Policy is IERC165 {
  /*///////////////////////////////////////////////////////////////
                            ENUMS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The authority under which a movement happens. The set is closed
   * @param TRANSFER Any other movement between two accounts, typically one the holder directed
   * @param EXECUTED A signed holder instruction the token verified, executed by an account the token authorises
   * @param FORCED The token's enforcement authority, which does not depend on the holder directing the movement
   * @param MINT Issuance under the token's ordinary issuance rules
   * @param BURN Destruction the holder directed
   */
  enum TransferKind {
    TRANSFER,
    EXECUTED,
    FORCED,
    MINT,
    BURN
  }

  /*///////////////////////////////////////////////////////////////
                            STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice One movement, as the token describes it to its policy
   * @param token The token whose balance or ownership changes
   * @param from The account whose position decreases, or address(0) when the movement creates the position
   * @param to The account whose position increases, or address(0) when the movement destroys the position
   * @param tokenId 0 for an ERC-20 token; the token identifier for ERC-721, ERC-1155 and ERC-6909 tokens
   * @param amount The quantity moved; 1 for an ERC-721 token
   * @param operator The account that called the token to cause the movement
   * @param kind The authority under which the movement happens
   * @param data Token-defined data. For EXECUTED and FORCED, whatever the token passes. For TRANSFER, MINT and BURN,
   *        empty or only values the token derives from its own state, never anything the caller supplied
   */
  struct TransferContext {
    address token;
    address from;
    address to;
    uint256 tokenId;
    uint256 amount;
    address operator;
    TransferKind kind;
    bytes data;
  }

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Records a movement after balances changed, in the same transaction
   * @dev Only the token named in the context may call it
   * @param _context The context the token passed to `checkTransfer` for this movement
   */
  function afterTransfer(
    TransferContext calldata _context
  ) external;

  /**
   * @notice Initialises the policy for a token that installs it
   * @dev Called by the token on every installation, once its `policy()` returns this policy. Only `_token` may call it
   * @param _token The token installing the policy
   * @param _previousPolicy The policy the token consulted until now; address(0) on the first installation
   * @param _data Data from the account that installs the policy, passed on unchanged
   */
  function onInstall(
    address _token,
    address _previousPolicy,
    bytes calldata _data
  ) external;

  /**
   * @notice Account-level eligibility to receive `_token`; backs the token's ERC-7943 `canReceive`
   * @param _token The token
   * @param _account The account
   * @return _reason TRANSFER_OK to permit, any other value to reject
   */
  function checkReceive(
    address _token,
    address _account
  ) external view returns (bytes32 _reason);

  /**
   * @notice Account-level eligibility to send `_token`; backs the token's ERC-7943 `canSend`
   * @param _token The token
   * @param _account The account
   * @return _reason TRANSFER_OK to permit, any other value to reject
   */
  function checkSend(
    address _token,
    address _account
  ) external view returns (bytes32 _reason);

  /**
   * @notice Decides one movement
   * @dev Called by the token before balances change, and by anyone to simulate
   * @param _context The movement
   * @return _reason TRANSFER_OK to permit, any other value to reject
   */
  function checkTransfer(
    TransferContext calldata _context
  ) external view returns (bytes32 _reason);

  /**
   * @notice Whether the token must call `afterTransfer` after each movement
   * @dev May change with the policy's configuration
   * @return _wantsAfter True if the token must call `afterTransfer`
   */
  function wantsAfterTransfer() external view returns (bool _wantsAfter);
}
