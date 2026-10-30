// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

/**
 * @title IERCXXXX
 * @notice An ERC-7943 token governed by an external policy
 */
interface IERCXXXX is IERC165 {
  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Emitted on every installation, including the first
   * @param _previousPolicy The policy before the change; address(0) on the first installation
   * @param _newPolicy The policy after the change
   */
  event PolicyChanged(address indexed _previousPolicy, address indexed _newPolicy);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Recommended error when the policy rejects a movement
   * @param _reason The policy's reason code
   */
  error ERCXXXXPolicyRejected(bytes32 _reason);

  /*///////////////////////////////////////////////////////////////
                            VIEW
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The policy the token consults for every movement and for its ERC-7943 checks
   * @return _policy The policy
   */
  function policy() external view returns (address _policy);
}
