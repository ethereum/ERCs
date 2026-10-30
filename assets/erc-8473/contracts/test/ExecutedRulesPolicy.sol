// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TRANSFER_OK} from 'interfaces/IERC8473Policy.sol';

import {PermissivePolicy} from 'contracts/test/FaultyPolicies.sol';

/**
 * @notice Decides `EXECUTED` by `operator`, by both words of `data` and by a settlement window, and `TRANSFER` by a
 *         switch. Every other kind is permitted
 * @dev Test helper. `ExamplePolicy` reads neither `operator` nor `data`, so on its own it could not catch a pre-flight
 *      that builds them wrongly
 */
contract ExecutedRulesPolicy is PermissivePolicy {
  bytes32 public constant DEADLINE_TOO_FAR = keccak256('DEADLINE_TOO_FAR');
  bytes32 public constant DIRECT_TRANSFERS_DISABLED = keccak256('DIRECT_TRANSFERS_DISABLED');
  bytes32 public constant MALFORMED_DATA = keccak256('MALFORMED_DATA');
  bytes32 public constant OPERATOR_NOT_ALLOWED = keccak256('OPERATOR_NOT_ALLOWED');
  bytes32 public constant REFERENCE_BLOCKED = keccak256('REFERENCE_BLOCKED');
  bytes32 public constant WINDOW_CLOSED = keccak256('WINDOW_CLOSED');

  address public allowedOperator;
  bytes32 public blockedReference;
  bool public directTransfersDisabled;
  uint256 public maxDeadline;
  bool public windowClosed;

  constructor(
    address _allowedOperator,
    bytes32 _blockedReference,
    uint256 _maxDeadline
  ) {
    allowedOperator = _allowedOperator;
    blockedReference = _blockedReference;
    maxDeadline = _maxDeadline;
  }

  function setDirectTransfersDisabled(
    bool _disabled
  ) external {
    directTransfersDisabled = _disabled;
  }

  function setWindowClosed(
    bool _closed
  ) external {
    windowClosed = _closed;
  }

  function checkTransfer(
    TransferContext calldata _context
  ) external view override returns (bytes32 _reason) {
    if (_context.kind == TransferKind.TRANSFER) {
      return directTransfersDisabled ? DIRECT_TRANSFERS_DISABLED : TRANSFER_OK;
    }
    if (_context.kind != TransferKind.EXECUTED) return TRANSFER_OK;
    if (windowClosed) return WINDOW_CLOSED;
    if (_context.operator != allowedOperator) return OPERATOR_NOT_ALLOWED;
    if (_context.data.length != 64) return MALFORMED_DATA;
    (bytes32 _instructionRef, uint256 _deadline) = abi.decode(_context.data, (bytes32, uint256));
    if (_instructionRef == blockedReference) return REFERENCE_BLOCKED;
    if (_deadline > maxDeadline) return DEADLINE_TOO_FAR;
    _reason = TRANSFER_OK;
  }
}
