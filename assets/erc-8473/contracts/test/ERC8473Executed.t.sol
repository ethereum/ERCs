// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuardTransient} from '@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol';

import {IERC8473} from 'interfaces/IERC8473.sol';
import {IExampleExecutorToken} from 'interfaces/IExampleExecutorToken.sol';

import {ExampleExecutorToken} from 'contracts/example/ExampleExecutorToken.sol';
import {ExamplePolicy} from 'contracts/example/ExamplePolicy.sol';
import {ExecutedRulesPolicy} from 'contracts/test/ExecutedRulesPolicy.sol';
import {GasBurningPolicy, ReentrantExecutorPolicy} from 'contracts/test/FaultyPolicies.sol';
import {InstructionHelpers} from 'contracts/test/InstructionHelpers.sol';

/// @notice ERC-8473 conformance for EXECUTED movements: the executor token with real policies
contract ERC8473ExecutedIntegrationTest is InstructionHelpers {
  uint256 internal constant _NOT_AN_EXECUTOR = 1;
  uint256 internal constant _EXPIRED = 2;
  uint256 internal constant _REFERENCE_USED = 3;
  uint256 internal constant _WRONG_SIGNER = 4;

  address internal _admin = makeAddr('admin');
  address internal _minter = makeAddr('minter');
  address internal _enforcer = makeAddr('enforcer');
  address internal _pauser = makeAddr('pauser');
  address internal _executor = makeAddr('executor');
  address internal _secondExecutor = makeAddr('secondExecutor');
  address internal _stranger = makeAddr('stranger');
  address[4] internal _actors;
  uint256[4] internal _keys;
  uint256 internal _deadline;

  ExamplePolicy internal _policy;
  ExampleExecutorToken internal _token;

  function setUp() public {
    string[4] memory _labels = ['a', 'b', 'c', 'd'];
    for (uint256 _i; _i < _actors.length; ++_i) {
      (_actors[_i], _keys[_i]) = makeAddrAndKey(_labels[_i]);
    }
    _deadline = block.timestamp + 1 hours;

    _token = new ExampleExecutorToken(_TOKEN_NAME, 'EX', _admin);
    _policy = new ExamplePolicy(address(_token), _admin, 10);
    vm.prank(_admin);
    _token.setPolicy(address(_policy), abi.encode(new address[](0))); // no supply yet

    vm.startPrank(_admin);
    _token.grantRole(_token.MINTER_ROLE(), _minter);
    _token.grantRole(_token.ENFORCER_ROLE(), _enforcer);
    _token.grantRole(_token.PAUSER_ROLE(), _pauser);
    _token.grantRole(_token.EXECUTOR_ROLE(), _executor);
    _token.grantRole(_token.EXECUTOR_ROLE(), _secondExecutor);
    for (uint256 _i; _i < _actors.length; ++_i) {
      _policy.setAllowlisted(_actors[_i], true);
    }
    vm.stopPrank();

    vm.startPrank(_minter);
    _token.mint(_actors[0], 1000);
    _token.mint(_actors[1], 1000);
    vm.stopPrank();
  }

  function _instruction(
    address _from,
    address _to,
    uint256 _amount
  ) internal view returns (IExampleExecutorToken.Instruction memory _built) {
    _built = IExampleExecutorToken.Instruction({
      from: _from, to: _to, amount: _amount, instructionRef: _REF, deadline: _deadline
    });
  }

  /// @notice Installs `ExecutedRulesPolicy` with `_executor` allowed and a blocked reference; the deadline may reach a day
  function _installRules() internal returns (ExecutedRulesPolicy _rules) {
    _rules = new ExecutedRulesPolicy(_executor, keccak256('BLOCKED'), block.timestamp + 1 days);
    vm.prank(_admin);
    _token.setPolicy(address(_rules), '');
  }

  /*///////////////////////////////////////////////////////////////
                            PRE-FLIGHT PARITY
  //////////////////////////////////////////////////////////////*/

  /// @notice Applies the policy and token state a fuzz run asks for
  function _applyScenario(
    uint8 _allowMask,
    bool _paused,
    uint256 _frozen,
    uint256 _cap,
    address _from
  ) internal {
    vm.startPrank(_admin);
    for (uint256 _i; _i < _actors.length; ++_i) {
      _policy.setAllowlisted(_actors[_i], (_allowMask >> _i) & 1 == 1);
    }
    _policy.setCap(bound(_cap, 0, 4));
    vm.stopPrank();
    vm.prank(_enforcer);
    // Half the runs freeze nothing: a frozen amount hides a balance shortfall, which `canExecute` must also predict.
    _token.setFrozenTokens(_from, _frozen % 2 == 0 ? 0 : bound(_frozen, 1, 1500));
    if (_paused) {
      vm.prank(_pauser);
      _token.pause();
    }
  }

  /**
   * @notice Over everything that decides an execution, `canExecute` equals the outcome, with no carve-out. At most one
   *         instruction fault per run, and none in most, so that enough runs reach the policy
   */
  function testFuzz_CanExecutePredictsExecute(
    uint8 _allowMask,
    bool _paused,
    uint256 _frozen,
    uint256 _cap,
    uint256 _fromSeed,
    uint256 _toSeed,
    uint256 _amount,
    uint256 _faultSeed
  ) public {
    uint256 _fromIndex = bound(_fromSeed, 0, 3);
    uint256 _toIndex = bound(_toSeed, 0, 4); // 4 is the zero address
    address _to = _toIndex == 4 ? address(0) : _actors[_toIndex];
    uint256 _fault = bound(_faultSeed, 0, 9);

    IExampleExecutorToken.Instruction memory _built = _instruction(_actors[_fromIndex], _to, bound(_amount, 0, 1200));
    bytes memory _signature =
      _sign(_fault == _WRONG_SIGNER ? _keys[(_fromIndex + 1) % 4] : _keys[_fromIndex], address(_token), _built);
    if (_fault == _REFERENCE_USED) _useReference(_actors[_fromIndex], _fromIndex);
    _applyScenario(_allowMask, _paused, _frozen, _cap, _actors[_fromIndex]);
    if (_fault == _EXPIRED) vm.warp(_deadline + 1);
    address _caller = _fault == _NOT_AN_EXECUTOR ? _stranger : _executor;

    bool _predicted = _token.canExecute(_built, _signature, _caller);
    vm.prank(_caller);
    (bool _succeeded,) = address(_token).call(abi.encodeCall(_token.executeInstruction, (_built, _signature)));
    assertEq(_succeeded, _predicted);
    if (_fault >= _NOT_AN_EXECUTOR && _fault <= _WRONG_SIGNER) assertFalse(_predicted);
  }

  /// @notice Carries out a zero-amount instruction with the reference `_REF`, while everything still permits it
  function _useReference(
    address _holder,
    uint256 _holderIndex
  ) internal {
    IExampleExecutorToken.Instruction memory _first = _instruction(_holder, _actors[1], 0);
    bytes memory _signature = _sign(_keys[_holderIndex], address(_token), _first);
    vm.prank(_executor);
    _token.executeInstruction(_first, _signature);
  }

  /// @notice A policy whose answer depends on `operator` and on both words of `data`: the pre-flight must build them right
  function testFuzz_CanExecuteSeesWhatThePolicySees(
    bool _allowedExecutor,
    bool _blockedReference,
    uint256 _deadlineOffset
  ) public {
    ExecutedRulesPolicy _rules = _installRules();
    uint256 _offset = bound(_deadlineOffset, 0, 2 days);
    address _caller = _allowedExecutor ? _executor : _secondExecutor;

    IExampleExecutorToken.Instruction memory _built = _instruction(_actors[0], _actors[1], 1);
    _built.instructionRef = _blockedReference ? keccak256('BLOCKED') : _REF;
    _built.deadline = block.timestamp + _offset;
    bytes memory _signature = _sign(_keys[0], address(_token), _built);
    bool _expected = _allowedExecutor && !_blockedReference && _built.deadline <= _rules.maxDeadline();

    bool _predicted = _token.canExecute(_built, _signature, _caller);
    assertEq(_predicted, _expected);
    vm.prank(_caller);
    (bool _succeeded,) = address(_token).call(abi.encodeCall(_token.executeInstruction, (_built, _signature)));
    assertEq(_succeeded, _predicted);
  }

  /*///////////////////////////////////////////////////////////////
                            THE POLICY'S RULES
  //////////////////////////////////////////////////////////////*/

  /// @notice Policy requirement 4. The executor needs no allowlisting: it only operates
  function test_AnExecutedMovementNeedsBothAccountChecks() public {
    IExampleExecutorToken.Instruction memory _built = _instruction(_actors[0], _actors[1], 1);
    bytes memory _signature = _sign(_keys[0], address(_token), _built);
    assertTrue(_token.canExecute(_built, _signature, _executor));

    bytes32 _senderReason = _policy.SENDER_NOT_ELIGIBLE();
    bytes32 _receiverReason = _policy.RECEIVER_NOT_ELIGIBLE();
    vm.prank(_admin);
    _policy.setAllowlisted(_actors[0], false);
    assertFalse(_token.canExecute(_built, _signature, _executor));
    vm.prank(_executor);
    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _senderReason));
    _token.executeInstruction(_built, _signature);

    vm.startPrank(_admin);
    _policy.setAllowlisted(_actors[0], true);
    _policy.setAllowlisted(_actors[1], false);
    vm.stopPrank();
    assertFalse(_token.canExecute(_built, _signature, _executor));
    vm.prank(_executor);
    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _receiverReason));
    _token.executeInstruction(_built, _signature);
  }

  function test_TheHolderCapCountsExecutedMovements() public {
    vm.prank(_admin);
    _policy.setCap(2);
    bytes32 _maxHolders = _policy.MAX_HOLDERS();

    IExampleExecutorToken.Instruction memory _third = _instruction(_actors[0], _actors[2], 1);
    bytes memory _thirdSignature = _sign(_keys[0], address(_token), _third);
    assertFalse(_token.canExecute(_third, _thirdSignature, _executor));
    vm.prank(_executor);
    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _maxHolders));
    _token.executeInstruction(_third, _thirdSignature);

    // A full exit to a new holder leaves the count where it was, and `afterTransfer` follows it.
    IExampleExecutorToken.Instruction memory _exit = _instruction(_actors[0], _actors[2], 1000);
    bytes memory _exitSignature = _sign(_keys[0], address(_token), _exit);
    vm.prank(_executor);
    _token.executeInstruction(_exit, _exitSignature);
    assertEq(_policy.holderCount(), 2);
    assertEq(_token.balanceOf(_actors[2]), 1000);

    IExampleExecutorToken.Instruction memory _merge = _instruction(_actors[1], _actors[2], 1000);
    _merge.instructionRef = keccak256('REF-2');
    bytes memory _mergeSignature = _sign(_keys[1], address(_token), _merge);
    vm.prank(_executor);
    _token.executeInstruction(_merge, _mergeSignature);
    assertEq(_policy.holderCount(), 1);
  }

  /// @notice Rationale, "What `canTransfer` predicts": a window closed for EXECUTED leaves direct transfers possible
  function test_APolicyCanCloseAWindowForExecutedWhileTransfersContinue() public {
    ExecutedRulesPolicy _rules = _installRules();
    _rules.setWindowClosed(true);
    bytes32 _windowClosed = _rules.WINDOW_CLOSED();
    IExampleExecutorToken.Instruction memory _built = _instruction(_actors[0], _actors[1], 1);
    bytes memory _signature = _sign(_keys[0], address(_token), _built);

    assertFalse(_token.canExecute(_built, _signature, _executor));
    vm.prank(_executor);
    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _windowClosed));
    _token.executeInstruction(_built, _signature);

    assertTrue(_token.canTransfer(_actors[0], _actors[1], 1));
    vm.prank(_actors[0]);
    assertTrue(_token.transfer(_actors[1], 1));
  }

  /// @notice Rationale, "What `canTransfer` predicts": direct transfers can be off entirely while executors settle
  function test_APolicyCanDisableDirectTransfersWhileExecutorsSettle() public {
    ExecutedRulesPolicy _rules = _installRules();
    _rules.setDirectTransfersDisabled(true);
    bytes32 _disabled = _rules.DIRECT_TRANSFERS_DISABLED();
    IExampleExecutorToken.Instruction memory _built = _instruction(_actors[0], _actors[1], 1);
    bytes memory _signature = _sign(_keys[0], address(_token), _built);

    assertFalse(_token.canTransfer(_actors[0], _actors[1], 1));
    vm.prank(_actors[0]);
    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _disabled));
    _token.transfer(_actors[1], 1);

    assertTrue(_token.canExecute(_built, _signature, _executor));
    vm.prank(_executor);
    _token.executeInstruction(_built, _signature);
    assertEq(_token.balanceOf(_actors[1]), 1001);
  }

  /*///////////////////////////////////////////////////////////////
                            THE GUARD
  //////////////////////////////////////////////////////////////*/

  /// @notice `executeInstruction` does not go through `_update`, so this is the guard's own test on this path
  function test_AfterTransferCannotStartAnExecutedMovement() public {
    ReentrantExecutorPolicy _reentrant = new ReentrantExecutorPolicy();
    bytes32 _executorRole = _token.EXECUTOR_ROLE();
    vm.prank(_admin);
    _token.grantRole(_executorRole, address(_reentrant));
    vm.prank(_admin);
    _token.setPolicy(address(_reentrant), '');

    IExampleExecutorToken.Instruction memory _inner = _instruction(_actors[1], _actors[0], 1);
    _reentrant.arm(_inner, _sign(_keys[1], address(_token), _inner));
    IExampleExecutorToken.Instruction memory _outer = _instruction(_actors[0], _actors[1], 1);
    bytes memory _signature = _sign(_keys[0], address(_token), _outer);

    vm.prank(_executor);
    vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
    _token.executeInstruction(_outer, _signature);
  }

  function test_OnInstallCannotStartAnExecutedMovement() public {
    ReentrantExecutorPolicy _reentrant = new ReentrantExecutorPolicy();
    bytes32 _executorRole = _token.EXECUTOR_ROLE();
    vm.prank(_admin);
    _token.grantRole(_executorRole, address(_reentrant));
    IExampleExecutorToken.Instruction memory _inner = _instruction(_actors[0], _actors[1], 1);
    _reentrant.arm(_inner, _sign(_keys[0], address(_token), _inner));

    vm.prank(_admin);
    vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
    _token.setPolicy(address(_reentrant), '');
    assertEq(_token.policy(), address(_policy));
  }

  /*///////////////////////////////////////////////////////////////
                            FAILING CLOSED
  //////////////////////////////////////////////////////////////*/

  /// @notice The token keeps 1/64 of its gas back from the call, enough to answer once the policy has burned the rest
  function test_WhenAnExecutedCheckRunsOutOfGas_ThePreflightIsFalseAndTheMovementReverts() public {
    uint256 _gas = 1_000_000;
    IExampleExecutorToken.Instruction memory _built = _instruction(_actors[0], _actors[1], 1);
    bytes memory _signature = _sign(_keys[0], address(_token), _built);
    // The limit alone does not change the answer.
    assertTrue(_token.canExecute{gas: _gas}(_built, _signature, _executor));

    address _burner = address(new GasBurningPolicy()); // deployed before the prank, which `new` would consume
    vm.prank(_admin);
    _token.setPolicy(_burner, '');
    assertFalse(_token.canExecute{gas: _gas}(_built, _signature, _executor));
    vm.prank(_executor);
    vm.expectRevert();
    _token.executeInstruction{gas: _gas}(_built, _signature);
  }
}
