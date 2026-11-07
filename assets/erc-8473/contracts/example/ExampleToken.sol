// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControl} from '@openzeppelin/contracts/access/AccessControl.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {Pausable} from '@openzeppelin/contracts/utils/Pausable.sol';
import {ReentrancyGuardTransient} from '@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol';
import {ERC165Checker} from '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import {IERC7943Fungible} from 'interfaces/IERC7943Fungible.sol';
import {IERC8473} from 'interfaces/IERC8473.sol';
import {IERC8473Policy, TRANSFER_OK} from 'interfaces/IERC8473Policy.sol';
import {IExampleToken} from 'interfaces/IExampleToken.sol';

/**
 * @title ExampleToken
 * @notice ERC-20 token that implements ERC-7943 through an ERC-8473 policy, as specified in `IExampleToken`
 * @dev Non-normative and not audited. Shows the token side of ERC-8473: one check path shared by movements and
 *      pre-flights, the policy read once per movement, fail-closed policy calls, and FORCED for enforcement
 */
contract ExampleToken is ERC20, AccessControl, Pausable, ReentrancyGuardTransient, IExampleToken {
  /// @inheritdoc IExampleToken
  bytes32 public constant ENFORCER_ROLE = keccak256('ENFORCER_ROLE');
  /// @inheritdoc IExampleToken
  bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');
  /// @inheritdoc IExampleToken
  bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

  /// @notice Token-side reason: paused. Never reaches the policy
  bytes32 private constant _PAUSED = keccak256('PAUSED');
  /// @notice Token-side reason: the amount exceeds the unfrozen balance. Never reaches the policy
  bytes32 private constant _INSUFFICIENT_UNFROZEN = keccak256('INSUFFICIENT_UNFROZEN');

  /// @notice The policy consulted for every movement and for the ERC-7943 checks
  address internal _policy;
  /// @notice Frozen amount per account; may exceed the balance, as ERC-7943 allows
  mapping(address _account => uint256 _amount) internal _frozen;
  /// @notice Set by `forcedTransfer` for the single movement it causes; consumed by `_update`
  bool internal transient _forcedPending;

  /**
   * @param _name The token name
   * @param _symbol The token symbol
   * @param _admin The DEFAULT_ADMIN_ROLE holder, who installs the first policy
   */
  constructor(
    string memory _name,
    string memory _symbol,
    address _admin
  ) ERC20(_name, _symbol) {
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
  }

  /*///////////////////////////////////////////////////////////////
                            ENFORCEMENT
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IERC7943Fungible
  function forcedTransfer(
    address _from,
    address _to,
    uint256 _amount
  ) external onlyRole(ENFORCER_ROLE) returns (bool _result) {
    if (_from == address(0)) revert ERC20InvalidSender(address(0));
    _unfreezeMoved(_from, _amount);
    _forcedPending = true;
    _transfer(_from, _to, _amount);
    // Emitted after the policy's afterTransfer: `_move`'s guard blocks re-entry into any movement.
    // slither-disable-next-line reentrancy-events
    emit ForcedTransfer(_from, _to, _amount);
    _result = true;
  }

  /// @inheritdoc IERC7943Fungible
  function setFrozenTokens(
    address _account,
    uint256 _amount
  ) external onlyRole(ENFORCER_ROLE) returns (bool _result) {
    _frozen[_account] = _amount;
    emit Frozen(_account, _amount);
    _result = true;
  }

  /*///////////////////////////////////////////////////////////////
                            ISSUANCE, REDEMPTION, PAUSE
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IExampleToken
  function burn(
    uint256 _amount
  ) external {
    _burn(_msgSender(), _amount);
  }

  /// @inheritdoc IExampleToken
  function mint(
    address _to,
    uint256 _amount
  ) external onlyRole(MINTER_ROLE) {
    _mint(_to, _amount);
  }

  /// @inheritdoc IExampleToken
  function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
  }

  /**
   * @inheritdoc IExampleToken
   * @dev Shares `_move`'s guard, so `onInstall` can start neither a movement nor another installation
   */
  function setPolicy(
    address _newPolicy,
    bytes calldata _data
  ) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
    if (!ERC165Checker.supportsInterface(_newPolicy, type(IERC8473Policy).interfaceId)) {
      revert ExampleToken_PolicyNotSupported(_newPolicy);
    }
    address _previousPolicy = _policy;
    emit PolicyChanged(_previousPolicy, _newPolicy);
    _policy = _newPolicy;
    IERC8473Policy(_newPolicy).onInstall(address(this), _previousPolicy, _data);
  }

  /// @inheritdoc IExampleToken
  function unpause() external onlyRole(PAUSER_ROLE) {
    _unpause();
  }

  /*///////////////////////////////////////////////////////////////
                            VIEW
  //////////////////////////////////////////////////////////////*/

  /**
   * @inheritdoc IERC7943Fungible
   * @dev True for the zero address, the sink of every burn, without calling the policy
   */
  function canReceive(
    address _account
  ) external view returns (bool _allowed) {
    _allowed =
      _account == address(0) || _permits(abi.encodeCall(IERC8473Policy.checkReceive, (address(this), _account)));
  }

  /**
   * @inheritdoc IERC7943Fungible
   * @dev True for the zero address, the source of every mint, without calling the policy
   */
  function canSend(
    address _account
  ) external view returns (bool _allowed) {
    _allowed = _account == address(0) || _permits(abi.encodeCall(IERC8473Policy.checkSend, (address(this), _account)));
  }

  /**
   * @inheritdoc IERC7943Fungible
   * @dev Evaluates exactly what `_move` evaluates for the TRANSFER, MINT or BURN its arguments describe, without
   *      reverting. The operator is `_from`, zero for a mint, so the context depends only on the arguments; these
   *      kinds' decisions cannot depend on it
   */
  function canTransfer(
    address _from,
    address _to,
    uint256 _amount
  ) external view returns (bool _allowed) {
    if (_from == address(0) && _to == address(0)) return false;
    IERC8473Policy.TransferKind _kind = _inferKind(_from, _to);
    if (_tokenCheck(_from, _amount, _kind) != TRANSFER_OK) return false;
    _allowed = _permits(abi.encodeCall(IERC8473Policy.checkTransfer, (_context(_from, _to, _amount, _from, _kind, ''))));
  }

  /// @inheritdoc IERC7943Fungible
  function getFrozenTokens(
    address _account
  ) external view returns (uint256 _amount) {
    _amount = _frozen[_account];
  }

  /// @inheritdoc IERC8473
  function policy() external view returns (address _currentPolicy) {
    _currentPolicy = _policy;
  }

  /// @inheritdoc IERC165
  function supportsInterface(
    bytes4 _interfaceId
  ) public view override(AccessControl, IERC165) returns (bool _supported) {
    _supported = _interfaceId == type(IERC7943Fungible).interfaceId || _interfaceId == type(IERC8473).interfaceId
      || super.supportsInterface(_interfaceId);
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Gives every mint, burn, transfer and forced transfer its kind, and sends it down the single path
   * @param _from The sender, or address(0) on mint
   * @param _to The receiver, or address(0) on burn
   * @param _value The amount
   */
  function _update(
    address _from,
    address _to,
    uint256 _value
  ) internal override {
    IERC8473Policy.TransferKind _kind = _forcedPending ? IERC8473Policy.TransferKind.FORCED : _inferKind(_from, _to);
    _forcedPending = false;
    _move(_from, _to, _value, _kind, '');
  }

  /**
   * @notice The single path every movement takes
   * @dev Guarded against reentrancy, so a policy's `afterTransfer` cannot start another movement. `_update` passes empty
   *      data, so only a token that adds an EXECUTED path can pass any
   * @param _from The sender, or address(0) on mint
   * @param _to The receiver, or address(0) on burn
   * @param _value The amount
   * @param _kind The kind
   * @param _data The context's data
   */
  function _move(
    address _from,
    address _to,
    uint256 _value,
    IERC8473Policy.TransferKind _kind,
    bytes memory _data
  ) internal nonReentrant {
    bytes32 _tokenReason = _tokenCheck(_from, _value, _kind);
    if (_tokenReason == _PAUSED) revert EnforcedPause();
    if (_tokenReason == _INSUFFICIENT_UNFROZEN) {
      uint256 _balance = balanceOf(_from);
      if (_value > _balance) revert ERC20InsufficientBalance(_from, _balance, _value);
      revert ERC7943InsufficientUnfrozenBalance(_from, _value, _unfrozen(_from));
    }

    IERC8473Policy.TransferContext memory _ctx = _context(_from, _to, _value, _msgSender(), _kind, _data);
    IERC8473Policy _activePolicy = IERC8473Policy(_policy); // read once for this movement

    // A revert, missing code or short return data reverts here too: the movement fails closed.
    bytes32 _reason = _activePolicy.checkTransfer(_ctx);
    if (_reason != TRANSFER_OK) revert ERC8473PolicyRejected(_reason);

    super._update(_from, _to, _value);

    if (_activePolicy.wantsAfterTransfer()) _activePolicy.afterTransfer(_ctx);
  }

  /**
   * @notice Unfreezes only the frozen part of what an enforcement action moves
   * @dev A freeze above the balance (allowed by ERC-7943) keeps withholding future receipts. Emits `Frozen` before the
   *      transfer event, as ERC-7943 requires
   * @param _account The account tokens are taken from
   * @param _amount The amount taken
   */
  function _unfreezeMoved(
    address _account,
    uint256 _amount
  ) internal {
    uint256 _balance = balanceOf(_account);
    if (_amount > _balance) revert ERC20InsufficientBalance(_account, _balance, _amount);
    uint256 _free = _unfrozen(_account);
    if (_amount <= _free) return;
    uint256 _remaining = _frozen[_account] - (_amount - _free);
    _frozen[_account] = _remaining;
    emit Frozen(_account, _remaining);
  }

  /**
   * @notice Builds a movement's context
   * @param _from The sender, or address(0)
   * @param _to The receiver, or address(0)
   * @param _amount The amount
   * @param _operator The account that called the token
   * @param _kind The kind
   * @param _data The data
   * @return _ctx The context
   */
  function _context(
    address _from,
    address _to,
    uint256 _amount,
    address _operator,
    IERC8473Policy.TransferKind _kind,
    bytes memory _data
  ) internal view returns (IERC8473Policy.TransferContext memory _ctx) {
    _ctx = IERC8473Policy.TransferContext({
      token: address(this),
      from: _from,
      to: _to,
      tokenId: 0,
      amount: _amount,
      operator: _operator,
      kind: _kind,
      data: _data
    });
  }

  /**
   * @notice Calls the policy without reverting; permits only on at least 32 bytes whose first word is TRANSFER_OK
   * @dev Matches what Solidity's decoder accepts in `_move`. Copies one word, and only once the answer is long enough,
   *      so a short answer can never be completed by leftover memory. An address without code answers with no data, so
   *      it never permits
   * @param _payload The encoded check
   * @return _permitted True if the policy permits
   */
  function _permits(
    bytes memory _payload
  ) internal view returns (bool _permitted) {
    address _activePolicy = _policy;
    bytes32 _ok = TRANSFER_OK;
    assembly ('memory-safe') {
      let _success := staticcall(gas(), _activePolicy, add(_payload, 0x20), mload(_payload), 0x00, 0x00)
      if and(_success, gt(returndatasize(), 0x1f)) {
        returndatacopy(0x00, 0x00, 0x20)
        _permitted := eq(mload(0x00), _ok)
      }
    }
  }

  /**
   * @notice The token's own checks, shared by `_move` and `canTransfer`
   * @dev Enforcement ignores the pause, and `forcedTransfer` has already unfrozen what it moves. As in ERC-7943, the
   *      unfrozen check applies only while the account has a frozen amount: a balance shortfall with nothing frozen
   *      is left to the base standard, which reverts with `ERC20InsufficientBalance`
   * @param _from The sender, or address(0)
   * @param _amount The amount
   * @param _kind The kind
   * @return _reason TRANSFER_OK, `_PAUSED`, or `_INSUFFICIENT_UNFROZEN` when frozen tokens stand in the way
   */
  function _tokenCheck(
    address _from,
    uint256 _amount,
    IERC8473Policy.TransferKind _kind
  ) internal view returns (bytes32 _reason) {
    if (_kind == IERC8473Policy.TransferKind.FORCED) return TRANSFER_OK;
    if (paused()) return _PAUSED;
    if (_from != address(0) && _frozen[_from] > 0 && _amount > _unfrozen(_from)) return _INSUFFICIENT_UNFROZEN;
    _reason = TRANSFER_OK;
  }

  /**
   * @notice The balance not covered by the frozen amount
   * @param _account The account
   * @return _free The unfrozen balance
   */
  function _unfrozen(
    address _account
  ) internal view returns (uint256 _free) {
    uint256 _balance = balanceOf(_account);
    uint256 _amountFrozen = _frozen[_account];
    _free = _balance > _amountFrozen ? _balance - _amountFrozen : 0;
  }

  /**
   * @notice The kind of a movement no function announced: MINT, BURN or TRANSFER
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
