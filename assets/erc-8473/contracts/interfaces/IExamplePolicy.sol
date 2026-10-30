// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC8473Policy} from 'interfaces/IERC8473Policy.sol';

/**
 * @title IExamplePolicy
 * @notice Example ERC-8473 policy for one ERC-20 token: an allowlist and a holder cap
 * @dev Non-normative and not audited. Holders are accounts with a non-zero balance. `onInstall` sets the count from a
 *      list of holders on every installation, and `afterTransfer` keeps it. A cap of zero admits no holder
 */
interface IExamplePolicy is IERC8473Policy {
  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Emitted when an account is added to or removed from the allowlist
   * @param _account The account
   * @param _allowed Whether the account is allowlisted
   */
  event AllowlistSet(address indexed _account, bool _allowed);

  /**
   * @notice Emitted when the holder cap is set
   * @param _cap The new cap
   */
  event CapSet(uint256 _cap);

  /**
   * @notice Emitted when `onInstall` sets the holder count
   * @param _oldCount The count before
   * @param _newCount The count set
   */
  event HolderCountSeeded(uint256 _oldCount, uint256 _newCount);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Thrown when the listed balances do not add up to the total supply: an account outside the list holds tokens
   * @param _sum The sum of the listed balances
   * @param _supply The token's total supply
   */
  error ExamplePolicy_HoldersIncomplete(uint256 _sum, uint256 _supply);

  /**
   * @notice Thrown when the holder list is not strictly ascending, which also rejects duplicates and the zero address
   * @param _index The first entry that is not above the one before it (the first is compared with the zero address)
   */
  error ExamplePolicy_HoldersNotAscending(uint256 _index);

  /**
   * @notice Thrown when `afterTransfer` or `onInstall` is called by anyone but the token, or for another token
   * @param _caller The caller
   */
  error ExamplePolicy_OnlyToken(address _caller);

  /// @notice Thrown when the token is the zero address
  error ExamplePolicy_ZeroAddress();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Adds an account to or removes it from the allowlist
   * @dev Only the owner
   * @param _account The account
   * @param _allowed Whether the account is allowlisted
   */
  function setAllowlisted(
    address _account,
    bool _allowed
  ) external;

  /**
   * @notice Sets the holder cap
   * @dev Only the owner. Lowering it below the current count admits no new holder until the count is back down
   * @param _cap The new cap
   */
  function setCap(
    uint256 _cap
  ) external;

  /*///////////////////////////////////////////////////////////////
                            VIEW
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Whether an account is allowlisted
   * @param _account The account
   * @return _allowed True if allowlisted
   */
  function allowlisted(
    address _account
  ) external view returns (bool _allowed);

  /**
   * @notice The holder cap
   * @return _cap The cap
   */
  function cap() external view returns (uint256 _cap);

  /**
   * @notice The number of holders the policy has counted
   * @return _count The count
   */
  function holderCount() external view returns (uint256 _count);

  /**
   * @notice Reason returned when the cap admits no new holder
   * @return _reason keccak256('MAX_HOLDERS')
   */
  // getter of an UPPER_SNAKE constant
  // solhint-disable-next-line style-guide-casing
  function MAX_HOLDERS() external view returns (bytes32 _reason);

  /**
   * @notice Reason returned when the receiver is not allowlisted
   * @return _reason keccak256('RECEIVER_NOT_ELIGIBLE')
   */
  // getter of an UPPER_SNAKE constant
  // solhint-disable-next-line style-guide-casing
  function RECEIVER_NOT_ELIGIBLE() external view returns (bytes32 _reason);

  /**
   * @notice Reason returned when the sender is not allowlisted
   * @return _reason keccak256('SENDER_NOT_ELIGIBLE')
   */
  // getter of an UPPER_SNAKE constant
  // solhint-disable-next-line style-guide-casing
  function SENDER_NOT_ELIGIBLE() external view returns (bytes32 _reason);

  /**
   * @notice The token this policy serves
   * @return _token The token
   */
  // getter of an UPPER_SNAKE immutable
  // solhint-disable-next-line style-guide-casing
  function TOKEN() external view returns (address _token);

  /**
   * @notice Reason returned for any token other than `TOKEN`
   * @return _reason keccak256('UNKNOWN_TOKEN')
   */
  // getter of an UPPER_SNAKE constant
  // solhint-disable-next-line style-guide-casing
  function UNKNOWN_TOKEN() external view returns (bytes32 _reason);
}
