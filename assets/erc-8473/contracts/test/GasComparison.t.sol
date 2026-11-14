// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IERC8473} from 'interfaces/IERC8473.sol';
import {IERC8473Policy} from 'interfaces/IERC8473Policy.sol';

import {
  AllowlistGasCompliance,
  AllowlistGasPolicy,
  BoolComplianceGasToken,
  IBoolCompliance,
  InlineGasToken,
  PlainGasToken,
  PolicyGasToken
} from 'contracts/test/GasComparison.sol';
import {Helpers} from 'contracts/test/Helpers.sol';

/**
 * @notice What it costs to reach the same rule in five ways: no check, inline, a `bool` compliance call in ERC-3643's
 *         shape, and ERC-8473 without and with the after-transfer callback
 * @dev Only the `isolated` profile gives transaction gas, because it runs each call as its own transaction, so every
 *      account and slot starts cold. `npm run gas` runs it with `--snapshot`, which writes the values to `snapshots/`
 */
contract GasComparisonTest is Helpers {
  /// @notice One deployment of every design
  struct Designs {
    PlainGasToken plain;
    InlineGasToken inlineToken;
    AllowlistGasCompliance compliance;
    BoolComplianceGasToken boolToken;
    AllowlistGasPolicy quietPolicy;
    PolicyGasToken policyToken;
    AllowlistGasPolicy callbackPolicy;
    PolicyGasToken callbackToken;
  }

  /// @notice The snapshot group, written to `snapshots/erc8473-gas-comparison.json`
  string internal constant _GROUP = 'erc8473-gas-comparison';
  /// @notice What each holder starts with
  uint256 internal constant _HOLDING = 1000;
  /// @notice What each measured transfer moves
  uint256 internal constant _AMOUNT = 10;

  address internal _holder = makeAddr('holder');
  address internal _receiver = makeAddr('receiver');
  address internal _newcomer = makeAddr('newcomer');
  address internal _outsider = makeAddr('outsider');

  /// @notice The designs most tests use, and the transfers to a holder are measured on
  Designs internal _first;
  /// @notice The transfers to a new account are measured on these, so no test touches a contract twice: in the default
  ///         profile a test is one transaction, and a second touch would find warm slots
  Designs internal _second;

  function setUp() public {
    _first = _deploy();
    _second = _deploy();
  }

  function test_WhenEachDesignTransfers_ItRecordsTheGas() public {
    IERC20[5] memory _firstTokens = _tokens(_first);
    IERC20[5] memory _secondTokens = _tokens(_second);
    string[5] memory _names = ['plain', 'inline', 'bool-compliance', 'erc8473', 'erc8473-callback'];
    uint256[5] memory _toHolder;
    uint256[5] memory _toNewcomer;

    for (uint256 _i; _i < _names.length; ++_i) {
      _toHolder[_i] = _measure(_firstTokens[_i], _receiver, string.concat(_names[_i], '-to-holder'));
      _toNewcomer[_i] = _measure(_secondTokens[_i], _newcomer, string.concat(_names[_i], '-to-new-account'));
    }

    // The scenarios differ only in the token's balance writes, which every design shares.
    for (uint256 _i = 1; _i < _names.length; ++_i) {
      assertEq(_toHolder[_i] - _toHolder[0], _toNewcomer[_i] - _toNewcomer[0], _names[_i]);
    }
  }

  function test_WhenTheSenderIsNotListed_EveryCheckingDesignRejects() public {
    bytes32 _notEligible = _first.quietPolicy.SENDER_NOT_ELIGIBLE();

    vm.expectRevert(abi.encodeWithSelector(InlineGasToken.InlineGasToken_NotListed.selector, _outsider));
    vm.prank(_outsider);
    _first.inlineToken.transfer(_holder, 0);

    vm.expectRevert(BoolComplianceGasToken.BoolComplianceGasToken_NotAllowed.selector);
    vm.prank(_outsider);
    _first.boolToken.transfer(_holder, 0);

    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _notEligible));
    vm.prank(_outsider);
    _first.policyToken.transfer(_holder, 0);

    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _notEligible));
    vm.prank(_outsider);
    _first.callbackToken.transfer(_holder, 0);
  }

  function test_WhenTheReceiverIsNotListed_EveryCheckingDesignRejects() public {
    bytes32 _notEligible = _first.quietPolicy.RECEIVER_NOT_ELIGIBLE();

    vm.expectRevert(abi.encodeWithSelector(InlineGasToken.InlineGasToken_NotListed.selector, _outsider));
    vm.prank(_holder);
    _first.inlineToken.transfer(_outsider, _AMOUNT);

    vm.expectRevert(BoolComplianceGasToken.BoolComplianceGasToken_NotAllowed.selector);
    vm.prank(_holder);
    _first.boolToken.transfer(_outsider, _AMOUNT);

    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _notEligible));
    vm.prank(_holder);
    _first.policyToken.transfer(_outsider, _AMOUNT);

    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _notEligible));
    vm.prank(_holder);
    _first.callbackToken.transfer(_outsider, _AMOUNT);
  }

  function test_WhenThePolicyWantsTheCallback_ItGetsTheContextCheckTransferGot() public {
    IERC8473Policy.TransferContext memory _context = IERC8473Policy.TransferContext({
      token: address(_first.callbackToken),
      from: _holder,
      to: _receiver,
      tokenId: 0,
      amount: _AMOUNT,
      operator: _holder,
      kind: IERC8473Policy.TransferKind.TRANSFER,
      data: ''
    });
    address _policy = address(_first.callbackPolicy);

    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.checkTransfer, (_context)), 1);
    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.afterTransfer, (_context)), 1);
    vm.prank(_holder);
    _first.callbackToken.transfer(_receiver, _AMOUNT);
  }

  function test_WhenThePolicyDoesNotWantTheCallback_ItIsNotCalled() public {
    address _policy = address(_first.quietPolicy);

    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.wantsAfterTransfer, ()), 1);
    vm.expectCall(_policy, abi.encodeWithSelector(IERC8473Policy.afterTransfer.selector), 0);
    vm.prank(_holder);
    _first.policyToken.transfer(_receiver, _AMOUNT);
  }

  function test_WhenTheBoolDesignTransfers_ItCallsCanTransferAndTransferred() public {
    address _compliance = address(_first.compliance);

    vm.expectCall(_compliance, abi.encodeCall(IBoolCompliance.canTransfer, (_holder, _receiver, _AMOUNT)), 1);
    vm.expectCall(_compliance, abi.encodeCall(IBoolCompliance.transferred, (_holder, _receiver, _AMOUNT)), 1);
    vm.prank(_holder);
    _first.boolToken.transfer(_receiver, _AMOUNT);
  }

  /**
   * @notice Deploys every design, with the holder and the receiver holding `_HOLDING` and the newcomer listed
   * @return _designs The deployed designs
   */
  function _deploy() internal returns (Designs memory _designs) {
    address[] memory _listed = new address[](3);
    (_listed[0], _listed[1], _listed[2]) = (_holder, _receiver, _newcomer);
    address[] memory _holders = new address[](2);
    (_holders[0], _holders[1]) = (_holder, _receiver);

    _designs.plain = new PlainGasToken(_holders, _HOLDING);
    _designs.inlineToken = new InlineGasToken(_listed, _holders, _HOLDING);
    _designs.compliance = new AllowlistGasCompliance(_listed);
    _designs.boolToken = new BoolComplianceGasToken(address(_designs.compliance), _holders, _HOLDING);
    _designs.quietPolicy = new AllowlistGasPolicy(_listed, false);
    _designs.policyToken = new PolicyGasToken(address(_designs.quietPolicy), _holders, _HOLDING);
    _designs.callbackPolicy = new AllowlistGasPolicy(_listed, true);
    _designs.callbackToken = new PolicyGasToken(address(_designs.callbackPolicy), _holders, _HOLDING);
  }

  /**
   * @notice Has the holder send `_AMOUNT` and records the transaction's gas under `_name`
   * @param _token The design's token
   * @param _to The receiver
   * @param _name The snapshot name
   * @return _gas The gas the transfer used
   */
  function _measure(
    IERC20 _token,
    address _to,
    string memory _name
  ) internal returns (uint256 _gas) {
    uint256 _before = _token.balanceOf(_to);
    vm.prank(_holder);
    _token.transfer(_to, _AMOUNT);
    _gas = vm.snapshotGasLastFrame(_GROUP, _name);
    assertEq(_token.balanceOf(_to), _before + _AMOUNT, _name);
  }

  /**
   * @notice A set's tokens, in the order of the snapshot names
   * @param _designs The set
   * @return _list Plain, inline, `bool` compliance, ERC-8473, ERC-8473 with the callback
   */
  function _tokens(
    Designs memory _designs
  ) internal pure returns (IERC20[5] memory _list) {
    _list = [
      IERC20(address(_designs.plain)),
      IERC20(address(_designs.inlineToken)),
      IERC20(address(_designs.boolToken)),
      IERC20(address(_designs.policyToken)),
      IERC20(address(_designs.callbackToken))
    ];
  }
}
