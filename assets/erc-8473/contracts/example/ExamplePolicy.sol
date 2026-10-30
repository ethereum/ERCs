// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC165} from '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import {IERC8473Policy, TRANSFER_OK} from 'interfaces/IERC8473Policy.sol';
import {IExamplePolicy} from 'interfaces/IExamplePolicy.sol';

/**
 * @title ExamplePolicy
 * @notice ERC-8473 policy for one ERC-20 token: an allowlist and a holder cap, as specified in `IExamplePolicy`
 * @dev Non-normative and not audited. Shows the policy side of ERC-8473: account checks that the transfer check stays
 *      consistent with, decisions per kind, and an authenticated `afterTransfer`
 */
contract ExamplePolicy is ERC165, Ownable, IExamplePolicy {
  /// @inheritdoc IExamplePolicy
  bytes32 public constant MAX_HOLDERS = keccak256('MAX_HOLDERS');
  /// @inheritdoc IExamplePolicy
  bytes32 public constant RECEIVER_NOT_ELIGIBLE = keccak256('RECEIVER_NOT_ELIGIBLE');
  /// @inheritdoc IExamplePolicy
  bytes32 public constant SENDER_NOT_ELIGIBLE = keccak256('SENDER_NOT_ELIGIBLE');
  /// @inheritdoc IExamplePolicy
  bytes32 public constant UNKNOWN_TOKEN = keccak256('UNKNOWN_TOKEN');

  /// @inheritdoc IExamplePolicy
  address public immutable TOKEN;

  /// @inheritdoc IExamplePolicy
  mapping(address _account => bool _allowed) public allowlisted;
  /// @inheritdoc IExamplePolicy
  uint256 public cap;
  /// @inheritdoc IExamplePolicy
  uint256 public holderCount;

  /**
   * @param _token The token this policy serves
   * @param _owner The owner, who manages the allowlist and the cap
   * @param _cap The initial holder cap
   */
  constructor(
    address _token,
    address _owner,
    uint256 _cap
  ) Ownable(_owner) {
    if (_token == address(0)) revert ExamplePolicy_ZeroAddress();
    TOKEN = _token;
    cap = _cap;
    emit CapSet(_cap);
  }

  /*///////////////////////////////////////////////////////////////
                            ADMIN
  //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IExamplePolicy
  function setAllowlisted(
    address _account,
    bool _allowed
  ) external onlyOwner {
    allowlisted[_account] = _allowed;
    emit AllowlistSet(_account, _allowed);
  }

  /// @inheritdoc IExamplePolicy
  function setCap(
    uint256 _cap
  ) external onlyOwner {
    cap = _cap;
    emit CapSet(_cap);
  }

  /*///////////////////////////////////////////////////////////////
                            ERC-8473
  //////////////////////////////////////////////////////////////*/

  /**
   * @inheritdoc IERC8473Policy
   * @dev Only the token may report its movements, so the count only follows real balance changes
   */
  function afterTransfer(
    TransferContext calldata _context
  ) external {
    if (msg.sender != TOKEN || _context.token != TOKEN) revert ExamplePolicy_OnlyToken(msg.sender);
    if (_context.amount == 0 || _context.from == _context.to) return;
    // A holder is an account with a non-zero balance: exact comparisons are the definition, not a price check.
    // slither-disable-next-line incorrect-equality
    if (_context.from != address(0) && IERC20(TOKEN).balanceOf(_context.from) == 0) holderCount -= 1;
    // slither-disable-next-line incorrect-equality
    if (_context.to != address(0) && IERC20(TOKEN).balanceOf(_context.to) == _context.amount) holderCount += 1;
  }

  /**
   * @inheritdoc IERC8473Policy
   * @dev `_data` is `abi.encode(address[])`: accounts in strictly ascending order whose balances add up to
   *      `totalSupply()`. Then no account outside the list holds tokens, so the count is exact when the call runs,
   *      however old the list is. Only non-zero balances count, so the list may name accounts that hold nothing. The
   *      count is set on every call, a reinstall included. `_previousPolicy` is unused: the count never comes from
   *      another contract. Each entry costs a cold read of its balance. Measured 2026-10-24 on `ExampleToken`,
   *      installing a freshly deployed policy: about 3,900 gas per entry when the admin calls `setPolicy` directly,
   *      and about 4,210 when a `TimelockController` executes that call. Under the per-transaction gas cap of
   *      16,777,216 (EIP-7825), 4,260 entries fit in the direct call and 3,950 through the timelock; 4,270 and 3,960
   *      did not
   */
  function onInstall(
    address _token,
    address,
    bytes calldata _data
  ) external {
    if (msg.sender != TOKEN || _token != TOKEN) revert ExamplePolicy_OnlyToken(msg.sender);
    address[] memory _holders = abi.decode(_data, (address[]));
    // The sum, the count and the previous address start at zero.
    // slither-disable-start uninitialized-local
    uint256 _sum;
    uint256 _count;
    address _previous;
    // slither-disable-end uninitialized-local
    uint256 _length = _holders.length;
    for (uint256 _i; _i < _length; ++_i) {
      address _holder = _holders[_i];
      if (_holder <= _previous) revert ExamplePolicy_HoldersNotAscending(_i);
      _previous = _holder;
      uint256 _balance = IERC20(TOKEN).balanceOf(_holder);
      if (_balance > 0) {
        _sum += _balance;
        ++_count;
      }
    }
    uint256 _supply = IERC20(TOKEN).totalSupply();
    if (_sum != _supply) revert ExamplePolicy_HoldersIncomplete(_sum, _supply);
    emit HolderCountSeeded(holderCount, _count);
    holderCount = _count;
  }

  /**
   * @inheritdoc IERC8473Policy
   * @dev Never reads `operator` or `data`: no kind this policy decides on needs them
   */
  function checkTransfer(
    TransferContext calldata _context
  ) external view returns (bytes32 _reason) {
    if (_context.token != TOKEN) return UNKNOWN_TOKEN;

    // Enforcement: the receiver must still be eligible; exempt from the cap, though `afterTransfer` counts it.
    if (_context.kind == TransferKind.FORCED) {
      return _context.to == address(0) ? TRANSFER_OK : checkReceive(_context.token, _context.to);
    }

    // Every other kind: both account checks, so the token's `canTransfer` covers `canSend` and `canReceive`.
    if (_context.from != address(0)) {
      _reason = checkSend(_context.token, _context.from);
      if (_reason != TRANSFER_OK) return _reason;
    }
    if (_context.to != address(0)) {
      _reason = checkReceive(_context.token, _context.to);
      if (_reason != TRANSFER_OK) return _reason;
    }
    _reason = _admitsHolder(_context) ? TRANSFER_OK : MAX_HOLDERS;
  }

  /// @inheritdoc IERC8473Policy
  function wantsAfterTransfer() external pure returns (bool _wantsAfter) {
    _wantsAfter = true;
  }

  /// @inheritdoc IERC8473Policy
  function checkReceive(
    address _token,
    address _account
  ) public view returns (bytes32 _reason) {
    if (_token != TOKEN) return UNKNOWN_TOKEN;
    _reason = allowlisted[_account] ? TRANSFER_OK : RECEIVER_NOT_ELIGIBLE;
  }

  /// @inheritdoc IERC8473Policy
  function checkSend(
    address _token,
    address _account
  ) public view returns (bytes32 _reason) {
    if (_token != TOKEN) return UNKNOWN_TOKEN;
    _reason = allowlisted[_account] ? TRANSFER_OK : SENDER_NOT_ELIGIBLE;
  }

  /// @inheritdoc IERC165
  function supportsInterface(
    bytes4 _interfaceId
  ) public view override(ERC165, IERC165) returns (bool _supported) {
    _supported = _interfaceId == type(IERC8473Policy).interfaceId || super.supportsInterface(_interfaceId);
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Whether the movement keeps the holder count within the cap, reading balances before the movement
   * @dev A move to an existing holder is never capped. A move that also takes the sender's whole balance leaves the
   *      count unchanged and passes while the count is at or below the cap; any other new holder needs the count below
   *      the cap. Above a lowered cap, no new holder is admitted
   * @param _context The movement
   * @return _admits True if the cap admits the movement
   */
  function _admitsHolder(
    TransferContext calldata _context
  ) internal view returns (bool _admits) {
    if (_context.to == address(0) || _context.amount == 0 || _context.to == _context.from) return true;
    if (IERC20(TOKEN).balanceOf(_context.to) != 0) return true;
    // A full-balance move empties the sender: an exact comparison by definition.
    // slither-disable-next-line incorrect-equality
    bool _senderLeaves = _context.from != address(0) && IERC20(TOKEN).balanceOf(_context.from) == _context.amount;
    _admits = holderCount + (_senderLeaves ? 0 : 1) <= cap;
  }
}
