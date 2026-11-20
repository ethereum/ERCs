// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ReentrancyGuardTransient} from '@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol';

import {IERC8473} from 'interfaces/IERC8473.sol';
import {IERC8473Policy, TRANSFER_OK} from 'interfaces/IERC8473Policy.sol';

import {PermissivePolicy} from 'contracts/test/FaultyPolicies.sol';

/// @notice The two calls an ERC-3643 token makes to its compliance contract on a transfer
interface IBoolCompliance {
  /**
   * @notice Whether a transfer may happen
   * @param _from The sender
   * @param _to The receiver
   * @param _amount The amount
   * @return _allowed True if it may
   */
  function canTransfer(
    address _from,
    address _to,
    uint256 _amount
  ) external view returns (bool _allowed);

  /**
   * @notice Told about a transfer after the balances change
   * @param _from The sender
   * @param _to The receiver
   * @param _amount The amount
   */
  function transferred(
    address _from,
    address _to,
    uint256 _amount
  ) external;
}

/**
 * @notice Design 1: OpenZeppelin's ERC-20 with no check
 * @dev Gas measurement harness for `GasComparison.t.sol`, not a conforming token
 */
contract PlainGasToken is ERC20 {
  /**
   * @param _holders The accounts that start with a balance
   * @param _amount The balance each holder starts with
   */
  constructor(
    address[] memory _holders,
    uint256 _amount
  ) ERC20('Plain', 'PLAIN') {
    for (uint256 _i; _i < _holders.length; ++_i) {
      _mint(_holders[_i], _amount);
    }
  }
}

/**
 * @notice Design 2: the token reads the allowlist from its own storage
 * @dev Gas measurement harness for `GasComparison.t.sol`, not a conforming token. The zero address passes, as in the
 *      other designs
 */
contract InlineGasToken is ERC20 {
  /// @notice Whether an account may send and receive
  mapping(address _account => bool _isListed) public listed;

  /**
   * @notice Thrown when the sender or the receiver is not listed
   * @param _account The account
   */
  error InlineGasToken_NotListed(address _account);

  /**
   * @param _listed The accounts that may send and receive
   * @param _holders The accounts that start with a balance
   * @param _amount The balance each holder starts with
   */
  constructor(
    address[] memory _listed,
    address[] memory _holders,
    uint256 _amount
  ) ERC20('Inline', 'INLINE') {
    for (uint256 _i; _i < _listed.length; ++_i) {
      listed[_listed[_i]] = true;
    }
    for (uint256 _i; _i < _holders.length; ++_i) {
      _mint(_holders[_i], _amount);
    }
  }

  /**
   * @notice Checks both accounts against the list, then moves the balance
   * @param _from The sender, or address(0) on mint
   * @param _to The receiver, or address(0) on burn
   * @param _value The amount
   */
  function _update(
    address _from,
    address _to,
    uint256 _value
  ) internal override {
    if (_from != address(0) && !listed[_from]) revert InlineGasToken_NotListed(_from);
    if (_to != address(0) && !listed[_to]) revert InlineGasToken_NotListed(_to);
    super._update(_from, _to, _value);
  }
}

/**
 * @notice The rule behind design 3: the sender and the receiver are both listed
 * @dev Gas measurement harness for `GasComparison.t.sol`. `transferred` does nothing, so only the call is measured
 */
contract AllowlistGasCompliance is IBoolCompliance {
  /// @notice Whether an account may send and receive
  mapping(address _account => bool _isListed) public listed;

  /// @param _listed The accounts that may send and receive
  constructor(
    address[] memory _listed
  ) {
    for (uint256 _i; _i < _listed.length; ++_i) {
      listed[_listed[_i]] = true;
    }
  }

  /// @inheritdoc IBoolCompliance
  function transferred(
    address _from,
    address _to,
    uint256 _amount
  ) external {}

  /// @inheritdoc IBoolCompliance
  function canTransfer(
    address _from,
    address _to,
    uint256
  ) external view returns (bool _allowed) {
    _allowed = (_from == address(0) || listed[_from]) && (_to == address(0) || listed[_to]);
  }
}

/**
 * @notice Design 3: a `bool` compliance call in ERC-3643's shape, `canTransfer` before the balances change and
 *         `transferred` after
 * @dev Gas measurement harness for `GasComparison.t.sol`, not a conforming token. A real ERC-3643 token also calls its
 *      identity registry, a second contract, so this design is a lower bound for ERC-3643
 */
contract BoolComplianceGasToken is ERC20 {
  /// @notice The compliance contract, kept in storage as a token that can replace it must
  address internal _compliance;

  /// @notice Thrown when the compliance contract answers false
  error BoolComplianceGasToken_NotAllowed();

  /**
   * @param _initialCompliance The compliance contract
   * @param _holders The accounts that start with a balance
   * @param _amount The balance each holder starts with
   */
  constructor(
    address _initialCompliance,
    address[] memory _holders,
    uint256 _amount
  ) ERC20('BoolCompliance', 'BOOL') {
    _compliance = _initialCompliance;
    for (uint256 _i; _i < _holders.length; ++_i) {
      _mint(_holders[_i], _amount);
    }
  }

  /**
   * @notice Asks the compliance contract, moves the balance, then tells the compliance contract
   * @param _from The sender, or address(0) on mint
   * @param _to The receiver, or address(0) on burn
   * @param _value The amount
   */
  function _update(
    address _from,
    address _to,
    uint256 _value
  ) internal override {
    IBoolCompliance _activeCompliance = IBoolCompliance(_compliance);
    if (!_activeCompliance.canTransfer(_from, _to, _value)) revert BoolComplianceGasToken_NotAllowed();
    super._update(_from, _to, _value);
    _activeCompliance.transferred(_from, _to, _value);
  }
}

/**
 * @notice The rule behind design 4: the sender and the receiver are both listed
 * @dev Gas measurement harness for `GasComparison.t.sol`. Only `checkTransfer` and `wantsAfterTransfer` differ from
 *      `PermissivePolicy`; `afterTransfer` does nothing, so only the call is measured
 */
contract AllowlistGasPolicy is PermissivePolicy {
  /// @notice The listed reason for a receiver that is not listed
  bytes32 public constant RECEIVER_NOT_ELIGIBLE = keccak256('RECEIVER_NOT_ELIGIBLE');
  /// @notice The listed reason for a sender that is not listed
  bytes32 public constant SENDER_NOT_ELIGIBLE = keccak256('SENDER_NOT_ELIGIBLE');

  /// @notice What `wantsAfterTransfer` answers
  bool public immutable WANTS_AFTER;

  /// @notice Whether an account may send and receive
  mapping(address _account => bool _isListed) public listed;

  /**
   * @param _listed The accounts that may send and receive
   * @param _wantsAfter What `wantsAfterTransfer` answers
   */
  constructor(
    address[] memory _listed,
    bool _wantsAfter
  ) {
    WANTS_AFTER = _wantsAfter;
    for (uint256 _i; _i < _listed.length; ++_i) {
      listed[_listed[_i]] = true;
    }
  }

  /// @inheritdoc IERC8473Policy
  function checkTransfer(
    TransferContext calldata _context
  ) external view override returns (bytes32 _reason) {
    if (_context.from != address(0) && !listed[_context.from]) return SENDER_NOT_ELIGIBLE;
    if (_context.to != address(0) && !listed[_context.to]) return RECEIVER_NOT_ELIGIBLE;
    _reason = TRANSFER_OK;
  }

  /// @inheritdoc IERC8473Policy
  function wantsAfterTransfer(
    address
  ) external view override returns (bool _wantsAfter) {
    _wantsAfter = WANTS_AFTER;
  }
}

/**
 * @notice Design 4: the token reaches the rule through an ERC-8473 policy
 * @dev Gas measurement harness for `GasComparison.t.sol`, not a conforming token: no installation and no pre-flights.
 *      The movement path is `ExampleToken._move` without ERC-7943's pause and freeze checks. It reads the policy once,
 *      calls `checkTransfer` and `wantsAfterTransfer` with STATICCALL, calls `afterTransfer` when asked, and is guarded
 *      against reentrancy (token rules 5, 6, 8 and 9)
 */
contract PolicyGasToken is ERC20, ReentrancyGuardTransient {
  /// @notice The policy, kept in storage as a token that can replace it must
  address internal _policy;

  /**
   * @param _initialPolicy The policy
   * @param _holders The accounts that start with a balance
   * @param _amount The balance each holder starts with
   */
  constructor(
    address _initialPolicy,
    address[] memory _holders,
    uint256 _amount
  ) ERC20('Policy', 'POLICY') {
    _policy = _initialPolicy;
    for (uint256 _i; _i < _holders.length; ++_i) {
      _mint(_holders[_i], _amount);
    }
  }

  /**
   * @notice Builds the context, asks the policy, moves the balance, then calls the policy back if it asks
   * @param _from The sender, or address(0) on mint
   * @param _to The receiver, or address(0) on burn
   * @param _value The amount
   */
  function _update(
    address _from,
    address _to,
    uint256 _value
  ) internal override nonReentrant {
    IERC8473Policy.TransferContext memory _ctx = IERC8473Policy.TransferContext({
      token: address(this),
      from: _from,
      to: _to,
      tokenId: 0,
      amount: _value,
      operator: _msgSender(),
      kind: _inferKind(_from, _to),
      data: ''
    });
    IERC8473Policy _activePolicy = IERC8473Policy(_policy); // read once for this movement

    bytes32 _reason = _activePolicy.checkTransfer(_ctx);
    if (_reason != TRANSFER_OK) revert IERC8473.ERC8473PolicyRejected(_reason);

    super._update(_from, _to, _value);

    if (_activePolicy.wantsAfterTransfer(address(this))) _activePolicy.afterTransfer(_ctx);
  }

  /**
   * @notice The kind of a movement: MINT, BURN or TRANSFER
   * @param _from The sender, or address(0)
   * @param _to The receiver, or address(0)
   * @return _kind The kind
   */
  function _inferKind(
    address _from,
    address _to
  ) internal pure returns (IERC8473Policy.TransferKind _kind) {
    if (_from == address(0)) return IERC8473Policy.TransferKind.MINT;
    if (_to == address(0)) return IERC8473Policy.TransferKind.BURN;
    _kind = IERC8473Policy.TransferKind.TRANSFER;
  }
}
