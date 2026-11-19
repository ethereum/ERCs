// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC165} from '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import {IERC8473Policy} from 'interfaces/IERC8473Policy.sol';

/**
 * @notice A policy built from one other policy: it forwards every call to `MODULE`
 * @dev Test helper. It is a policy itself, so policy requirements 10 and 15 apply to it: it accepts the callbacks only
 *      from the token they name, then forwards them. Without that check, anyone could reach the module through it
 */
contract ForwardingPolicy is ERC165, IERC8473Policy {
  /// @notice The policy every call is forwarded to
  IERC8473Policy public immutable MODULE;

  /**
   * @notice Thrown when a callback does not come from the token it names
   * @param _caller The caller
   */
  error ForwardingPolicy_OnlyToken(address _caller);

  /// @param _module The policy every call is forwarded to
  constructor(
    IERC8473Policy _module
  ) {
    MODULE = _module;
  }

  /// @inheritdoc IERC8473Policy
  function afterTransfer(
    TransferContext calldata _context
  ) external {
    if (msg.sender != _context.token) revert ForwardingPolicy_OnlyToken(msg.sender);
    MODULE.afterTransfer(_context);
  }

  /// @inheritdoc IERC8473Policy
  function onInstall(
    address _token,
    address _previousPolicy,
    bytes calldata _data
  ) external {
    if (msg.sender != _token) revert ForwardingPolicy_OnlyToken(msg.sender);
    MODULE.onInstall(_token, _previousPolicy, _data);
  }

  /// @inheritdoc IERC8473Policy
  function checkReceive(
    address _token,
    address _account
  ) external view returns (bytes32 _reason) {
    _reason = MODULE.checkReceive(_token, _account);
  }

  /// @inheritdoc IERC8473Policy
  function checkSend(
    address _token,
    address _account
  ) external view returns (bytes32 _reason) {
    _reason = MODULE.checkSend(_token, _account);
  }

  /// @inheritdoc IERC8473Policy
  function checkTransfer(
    TransferContext calldata _context
  ) external view returns (bytes32 _reason) {
    _reason = MODULE.checkTransfer(_context);
  }

  /// @inheritdoc IERC8473Policy
  function wantsAfterTransfer(
    address _token
  ) external view returns (bool _wantsAfter) {
    _wantsAfter = MODULE.wantsAfterTransfer(_token);
  }

  /// @inheritdoc IERC165
  function supportsInterface(
    bytes4 _interfaceId
  ) public view override(ERC165, IERC165) returns (bool _supported) {
    _supported = _interfaceId == type(IERC8473Policy).interfaceId || super.supportsInterface(_interfaceId);
  }
}
