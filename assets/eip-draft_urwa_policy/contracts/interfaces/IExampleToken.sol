// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC7943Fungible} from 'interfaces/IERC7943Fungible.sol';
import {IERCXXXX} from 'interfaces/IERCXXXX.sol';

/**
 * @title IExampleToken
 * @notice Example ERC-20 token that implements ERC-7943 through an ERC-XXXX policy
 * @dev Non-normative and not audited. Enforcement (`forcedTransfer`, `setFrozenTokens`) needs ENFORCER_ROLE, issuance
 *      MINTER_ROLE, pausing PAUSER_ROLE, and installing the policy DEFAULT_ADMIN_ROLE. The token starts without a
 *      policy and rejects every movement until one is installed
 */
interface IExampleToken is IERC7943Fungible, IERCXXXX {
  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Thrown when a policy does not advertise the ERC-XXXX policy interface through ERC-165
   * @param _policy The rejected policy
   */
  error ExampleToken_PolicyNotSupported(address _policy);

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Destroys the caller's own tokens: a BURN, subject to the policy and the frozen amount
   * @param _amount The amount to burn
   */
  function burn(
    uint256 _amount
  ) external;

  /**
   * @notice Issues tokens: a MINT, subject to the policy
   * @dev Only MINTER_ROLE
   * @param _to The receiver
   * @param _amount The amount to issue
   */
  function mint(
    address _to,
    uint256 _amount
  ) external;

  /**
   * @notice Pauses every movement except FORCED
   * @dev Only PAUSER_ROLE
   */
  function pause() external;

  /**
   * @notice Installs a policy, which may be the current one, and calls its `onInstall`
   * @dev Only DEFAULT_ADMIN_ROLE. The policy must advertise the ERC-XXXX policy interface. Emits `PolicyChanged`, sets
   *      the policy, then calls `onInstall`; if that reverts, the installation reverts. No movement or installation can
   *      start while `onInstall` runs
   * @param _newPolicy The new policy
   * @param _data Passed to the policy's `onInstall` unchanged
   */
  function setPolicy(
    address _newPolicy,
    bytes calldata _data
  ) external;

  /**
   * @notice Lifts the pause
   * @dev Only PAUSER_ROLE
   */
  function unpause() external;

  /*///////////////////////////////////////////////////////////////
                            VIEW
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The role allowed to force transfers and set frozen amounts
   * @return _role keccak256('ENFORCER_ROLE')
   */
  // getter of an UPPER_SNAKE constant
  // solhint-disable-next-line style-guide-casing
  function ENFORCER_ROLE() external view returns (bytes32 _role);

  /**
   * @notice The role allowed to mint
   * @return _role keccak256('MINTER_ROLE')
   */
  // getter of an UPPER_SNAKE constant
  // solhint-disable-next-line style-guide-casing
  function MINTER_ROLE() external view returns (bytes32 _role);

  /**
   * @notice The role allowed to pause and unpause
   * @return _role keccak256('PAUSER_ROLE')
   */
  // getter of an UPPER_SNAKE constant
  // solhint-disable-next-line style-guide-casing
  function PAUSER_ROLE() external view returns (bytes32 _role);
}
