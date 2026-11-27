// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ERC165} from '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import {IERC8473Policy, TRANSFER_OK} from 'interfaces/IERC8473Policy.sol';

/**
 * @notice A policy built from other policies, its modules: a movement must pass every module, and the callbacks go to
 *         the modules as policy requirement 17 says
 * @dev Test helper. It is a policy itself, so policy requirements 10 and 15 apply to it: it accepts the callbacks only
 *      from the token they name, then forwards them. Without that check, anyone could reach the modules through it.
 *      Every module receives the same `onInstall` data
 */
contract ForwardingPolicy is ERC165, IERC8473Policy {
  /// @notice The modules, in the order they are consulted
  IERC8473Policy[] internal _modules;

  /**
   * @notice Thrown when a callback does not come from the token it names
   * @param _caller The caller
   */
  error ForwardingPolicy_OnlyToken(address _caller);

  /// @notice Thrown when the forwarder is built without modules, which would permit every movement
  error ForwardingPolicy_NoModules();

  /// @param _policies The modules, in the order they are consulted
  constructor(
    IERC8473Policy[] memory _policies
  ) {
    if (_policies.length == 0) revert ForwardingPolicy_NoModules();
    _modules = _policies;
  }

  /// @inheritdoc IERC8473Policy
  function afterTransfer(
    TransferContext calldata _context
  ) external {
    if (msg.sender != _context.token) revert ForwardingPolicy_OnlyToken(msg.sender);
    for (uint256 _i; _i < _modules.length; ++_i) {
      if (_modules[_i].wantsAfterTransfer(_context.token)) _modules[_i].afterTransfer(_context);
    }
  }

  /// @inheritdoc IERC8473Policy
  function onInstall(
    address _token,
    address _previousPolicy,
    bytes calldata _data
  ) external {
    if (msg.sender != _token) revert ForwardingPolicy_OnlyToken(msg.sender);
    for (uint256 _i; _i < _modules.length; ++_i) {
      _modules[_i].onInstall(_token, _previousPolicy, _data);
    }
  }

  /// @inheritdoc IERC8473Policy
  function checkReceive(
    address _token,
    address _account
  ) external view returns (bytes32 _reason) {
    _reason = TRANSFER_OK;
    for (uint256 _i; _i < _modules.length && _reason == TRANSFER_OK; ++_i) {
      _reason = _modules[_i].checkReceive(_token, _account);
    }
  }

  /// @inheritdoc IERC8473Policy
  function checkSend(
    address _token,
    address _account
  ) external view returns (bytes32 _reason) {
    _reason = TRANSFER_OK;
    for (uint256 _i; _i < _modules.length && _reason == TRANSFER_OK; ++_i) {
      _reason = _modules[_i].checkSend(_token, _account);
    }
  }

  /// @inheritdoc IERC8473Policy
  function checkTransfer(
    TransferContext calldata _context
  ) external view returns (bytes32 _reason) {
    _reason = TRANSFER_OK;
    for (uint256 _i; _i < _modules.length && _reason == TRANSFER_OK; ++_i) {
      _reason = _modules[_i].checkTransfer(_context);
    }
  }

  /// @inheritdoc IERC8473Policy
  function wantsAfterTransfer(
    address _token
  ) external view returns (bool _wantsAfter) {
    for (uint256 _i; _i < _modules.length && !_wantsAfter; ++_i) {
      _wantsAfter = _modules[_i].wantsAfterTransfer(_token);
    }
  }

  /// @inheritdoc IERC165
  function supportsInterface(
    bytes4 _interfaceId
  ) public view override(ERC165, IERC165) returns (bool _supported) {
    _supported = _interfaceId == type(IERC8473Policy).interfaceId || super.supportsInterface(_interfaceId);
  }
}
