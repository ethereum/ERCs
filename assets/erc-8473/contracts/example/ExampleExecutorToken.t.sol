// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {IERC20Errors} from '@openzeppelin/contracts/interfaces/draft-IERC6093.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Pausable} from '@openzeppelin/contracts/utils/Pausable.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import {IERC7943Fungible} from 'interfaces/IERC7943Fungible.sol';
import {IERC8473} from 'interfaces/IERC8473.sol';
import {IERC8473Policy, TRANSFER_OK} from 'interfaces/IERC8473Policy.sol';
import {IExampleExecutorToken} from 'interfaces/IExampleExecutorToken.sol';

import {ExampleExecutorToken} from 'contracts/example/ExampleExecutorToken.sol';
import {ContractHolder} from 'contracts/test/ContractHolder.sol';
import {InstructionHelpers} from 'contracts/test/InstructionHelpers.sol';

/// @notice ExampleExecutorToken in isolation: the policy is a mocked address
contract ExampleExecutorTokenUnitTest is InstructionHelpers {
  bytes32 internal constant _REJECT = keccak256('REJECT');
  uint256 internal constant _AMOUNT = 10;

  ExampleExecutorToken internal _token;
  address internal _policy;
  address internal _admin = makeAddr('admin');
  address internal _minter = makeAddr('minter');
  address internal _enforcer = makeAddr('enforcer');
  address internal _pauser = makeAddr('pauser');
  address internal _executor = makeAddr('executor');
  address internal _otherExecutor = makeAddr('otherExecutor');
  address internal _spender = makeAddr('spender');
  address internal _stranger = makeAddr('stranger');
  address internal _bob = makeAddr('bob');
  address internal _alice;
  uint256 internal _aliceKey;
  uint256 internal _deadline;

  function setUp() public {
    (_alice, _aliceKey) = makeAddrAndKey('alice');
    _deadline = block.timestamp + 1 hours;
    _token = new ExampleExecutorToken(_TOKEN_NAME, 'EX', _admin);
    _policy = _mockPolicy('policy');

    vm.startPrank(_admin);
    _token.setPolicy(_policy, '');
    _token.grantRole(_token.MINTER_ROLE(), _minter);
    _token.grantRole(_token.ENFORCER_ROLE(), _enforcer);
    _token.grantRole(_token.PAUSER_ROLE(), _pauser);
    _token.grantRole(_token.EXECUTOR_ROLE(), _executor);
    _token.grantRole(_token.EXECUTOR_ROLE(), _otherExecutor);
    vm.stopPrank();

    vm.prank(_minter);
    _token.mint(_alice, 1000);
    vm.prank(_alice);
    _token.approve(_spender, type(uint256).max);
  }

  /// @notice A policy address that advertises the interface and permits everything until a test says otherwise
  function _mockPolicy(
    string memory _label
  ) internal returns (address _mocked) {
    _mocked = _mockContract(_label);
    vm.mockCall(_mocked, abi.encodeCall(IERC165.supportsInterface, (type(IERC165).interfaceId)), abi.encode(true));
    vm.mockCall(_mocked, abi.encodeCall(IERC165.supportsInterface, (bytes4(0xffffffff))), abi.encode(false));
    vm.mockCall(
      _mocked, abi.encodeCall(IERC165.supportsInterface, (type(IERC8473Policy).interfaceId)), abi.encode(true)
    );
    vm.mockCall(_mocked, abi.encodeWithSelector(IERC8473Policy.checkTransfer.selector), abi.encode(TRANSFER_OK));
    vm.mockCall(_mocked, abi.encodeCall(IERC8473Policy.wantsAfterTransfer, ()), abi.encode(false));
    vm.mockCall(_mocked, abi.encodeWithSelector(IERC8473Policy.onInstall.selector), '');
  }

  /// @notice The instruction most tests use: alice pays bob, with reference `_REF`
  function _instruction() internal view returns (IExampleExecutorToken.Instruction memory _built) {
    _built = IExampleExecutorToken.Instruction({
      from: _alice, to: _bob, amount: _AMOUNT, instructionRef: _REF, deadline: _deadline, executor: address(0)
    });
  }

  function _ctx(
    address _from,
    address _to,
    uint256 _amount,
    address _operator,
    IERC8473Policy.TransferKind _kind,
    bytes memory _data
  ) internal view returns (IERC8473Policy.TransferContext memory _context) {
    _context = IERC8473Policy.TransferContext({
      token: address(_token),
      from: _from,
      to: _to,
      tokenId: 0,
      amount: _amount,
      operator: _operator,
      kind: _kind,
      data: _data
    });
  }

  /// @notice The context the default instruction's movement carries when `_operator` carries it out
  function _executedCtx(
    address _operator
  ) internal view returns (IERC8473Policy.TransferContext memory _context) {
    _context = _ctx(_alice, _bob, _AMOUNT, _operator, IERC8473Policy.TransferKind.EXECUTED, abi.encode(_REF, _deadline));
  }

  function _rejectTransfers() internal {
    vm.mockCall(_policy, abi.encodeWithSelector(IERC8473Policy.checkTransfer.selector), abi.encode(_REJECT));
  }

  /*///////////////////////////////////////////////////////////////
                            THE MOVEMENT
  //////////////////////////////////////////////////////////////*/

  function test_WhenConstructed_ItExposesTheRoleTheTypeHashAndTheDomain() public view {
    assertEq(_token.EXECUTOR_ROLE(), keccak256('EXECUTOR_ROLE'));
    assertEq(
      _token.INSTRUCTION_TYPEHASH(),
      keccak256(
        'Instruction(address from,address to,uint256 amount,bytes32 instructionRef,uint256 deadline,address executor)'
      )
    );
    (, string memory _name, string memory _version, uint256 _chainId, address _verifyingContract,,) =
      _token.eip712Domain();
    assertEq(_name, _TOKEN_NAME);
    assertEq(_version, '1');
    assertEq(_chainId, block.chainid);
    assertEq(_verifyingContract, address(_token));
  }

  function test_WhenAnExecutorCarriesOutAnInstruction_ItAsksOnceWithTheExecutedContext() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    IERC8473Policy.TransferContext memory _expected = _executedCtx(_executor);

    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.checkTransfer, (_expected)), 1);
    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.wantsAfterTransfer, ()), 1);
    vm.expectCall(_policy, abi.encodeWithSelector(IERC8473Policy.afterTransfer.selector), 0);
    vm.expectEmit(address(_token));
    emit IExampleExecutorToken.InstructionExecuted(_alice, _REF, _executor);
    vm.expectEmit(address(_token));
    emit IERC20.Transfer(_alice, _bob, _AMOUNT);
    vm.prank(_executor);
    _token.executeInstruction(_built, _signature);

    assertEq(_token.balanceOf(_alice), 1000 - _AMOUNT);
    assertEq(_token.balanceOf(_bob), _AMOUNT);
    assertTrue(_token.instructionUsed(_alice, _REF));
  }

  function test_WhenThePolicyWantsTheCallback_ItGetsTheSameContext() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    IERC8473Policy.TransferContext memory _expected = _executedCtx(_executor);
    vm.mockCall(_policy, abi.encodeCall(IERC8473Policy.wantsAfterTransfer, ()), abi.encode(true));
    vm.mockCall(_policy, abi.encodeWithSelector(IERC8473Policy.afterTransfer.selector), '');

    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.afterTransfer, (_expected)), 1);
    vm.prank(_executor);
    _token.executeInstruction(_built, _signature);
  }

  function test_WhenTheAmountIsZero_ItIsAMovementAndUsesTheReference() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.amount = 0;
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    IERC8473Policy.TransferContext memory _expected =
      _ctx(_alice, _bob, 0, _executor, IERC8473Policy.TransferKind.EXECUTED, abi.encode(_REF, _deadline));

    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.checkTransfer, (_expected)), 1);
    vm.expectEmit(address(_token));
    emit IERC20.Transfer(_alice, _bob, 0);
    vm.prank(_executor);
    _token.executeInstruction(_built, _signature);
    assertTrue(_token.instructionUsed(_alice, _REF));
  }

  /*///////////////////////////////////////////////////////////////
                            THE KINDS
  //////////////////////////////////////////////////////////////*/

  /// @notice The role changes nothing on the base standard's functions: they MUST NOT cause an EXECUTED movement
  function test_WhenAnExecutorTransfers_TheKindIsStillTransfer() public {
    vm.prank(_alice);
    _token.approve(_executor, 100);
    vm.prank(_minter);
    _token.mint(_executor, 100);

    IERC8473Policy.TransferContext memory _own =
      _ctx(_executor, _bob, 1, _executor, IERC8473Policy.TransferKind.TRANSFER, '');
    IERC8473Policy.TransferContext memory _allowed =
      _ctx(_alice, _bob, 1, _executor, IERC8473Policy.TransferKind.TRANSFER, '');
    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.checkTransfer, (_own)), 1);
    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.checkTransfer, (_allowed)), 1);
    vm.startPrank(_executor);
    _token.transfer(_bob, 1);
    _token.transferFrom(_alice, _bob, 1);
    vm.stopPrank();
  }

  /// @notice The smoke test of the inherited paths on this token
  function test_WhenAnExecutorForcesMintsOrBurns_ThoseKindsAreUnchanged() public {
    bytes32 _enforcerRole = _token.ENFORCER_ROLE();
    bytes32 _minterRole = _token.MINTER_ROLE();
    vm.startPrank(_admin);
    _token.grantRole(_enforcerRole, _executor);
    _token.grantRole(_minterRole, _executor);
    vm.stopPrank();

    IERC8473Policy.TransferContext memory _forced =
      _ctx(_alice, _bob, 1, _executor, IERC8473Policy.TransferKind.FORCED, '');
    IERC8473Policy.TransferContext memory _minted =
      _ctx(address(0), _executor, 5, _executor, IERC8473Policy.TransferKind.MINT, '');
    IERC8473Policy.TransferContext memory _burned =
      _ctx(_executor, address(0), 2, _executor, IERC8473Policy.TransferKind.BURN, '');
    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.checkTransfer, (_forced)), 1);
    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.checkTransfer, (_minted)), 1);
    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.checkTransfer, (_burned)), 1);
    vm.startPrank(_executor);
    _token.forcedTransfer(_alice, _bob, 1);
    _token.mint(_executor, 5);
    _token.burn(2);
    vm.stopPrank();
  }

  /*///////////////////////////////////////////////////////////////
                            WHO MAY CALL
  //////////////////////////////////////////////////////////////*/

  /// @notice Kind rule 4: a function that any account, or an account the instruction names without the role, may call does not qualify
  function test_WhenTheCallerIsNotAnExecutor_ItReverts() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    bytes32 _executorRole = _token.EXECUTOR_ROLE();
    address[3] memory _callers = [_stranger, _alice, _bob];

    for (uint256 _i; _i < _callers.length; ++_i) {
      vm.prank(_callers[_i]);
      vm.expectRevert(
        abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _callers[_i], _executorRole)
      );
      _token.executeInstruction(_built, _signature);
    }
    assertEq(_token.balanceOf(_bob), 0);
  }

  /*///////////////////////////////////////////////////////////////
                            THE INSTRUCTION
  //////////////////////////////////////////////////////////////*/

  /// @notice Under the kind order a zero `to` would be a BURN; this path refuses it instead of burning
  function test_WhenTheReceiverIsZero_ItRevertsWithoutAskingThePolicy() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.to = address(0);
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    uint256 _supply = _token.totalSupply();

    vm.expectCall(_policy, abi.encodeWithSelector(IERC8473Policy.checkTransfer.selector), 0);
    assertFalse(_token.canExecute(_built, _signature, _executor));
    vm.prank(_executor);
    vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    _token.executeInstruction(_built, _signature);
    assertEq(_token.totalSupply(), _supply);
  }

  function test_WhenTheDeadlineHasPassed_ItReverts() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    vm.warp(_deadline + 1);

    vm.prank(_executor);
    vm.expectRevert(
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InstructionExpired.selector, _deadline)
    );
    _token.executeInstruction(_built, _signature);
  }

  function test_WhenTheDeadlineIsNow_ItExecutes() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    vm.warp(_deadline);

    assertTrue(_token.canExecute(_built, _signature, _executor));
    vm.prank(_executor);
    _token.executeInstruction(_built, _signature);
    assertEq(_token.balanceOf(_bob), _AMOUNT);
  }

  /// @notice The reference is what is used, not the signature: a different instruction with it reverts too
  function test_WhenTheReferenceWasUsed_ItReverts() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    IExampleExecutorToken.Instruction memory _other = _instruction();
    _other.amount = _AMOUNT + 1;
    bytes memory _otherSignature = _sign(_aliceKey, address(_token), _other);
    bytes memory _used =
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InstructionUsed.selector, _alice, _REF);

    vm.startPrank(_executor);
    _token.executeInstruction(_built, _signature);
    vm.expectRevert(_used);
    _token.executeInstruction(_built, _signature);
    vm.expectRevert(_used);
    _token.executeInstruction(_other, _otherSignature);
    vm.stopPrank();
    assertEq(_token.balanceOf(_bob), _AMOUNT);
  }

  function test_WhenTwoHoldersUseOneReference_BothExecute() public {
    (address _carol, uint256 _carolKey) = makeAddrAndKey('carol');
    vm.prank(_minter);
    _token.mint(_carol, 1000);
    IExampleExecutorToken.Instruction memory _first = _instruction();
    IExampleExecutorToken.Instruction memory _second = _instruction();
    _second.from = _carol;
    bytes memory _firstSignature = _sign(_aliceKey, address(_token), _first);
    bytes memory _secondSignature = _sign(_carolKey, address(_token), _second);

    vm.startPrank(_executor);
    _token.executeInstruction(_first, _firstSignature);
    _token.executeInstruction(_second, _secondSignature);
    vm.stopPrank();
    assertEq(_token.balanceOf(_bob), 2 * _AMOUNT);
  }

  function test_WhenInstructionsArriveOutOfOrder_BothExecute() public {
    IExampleExecutorToken.Instruction memory _earlier = _instruction();
    IExampleExecutorToken.Instruction memory _later = _instruction();
    _later.instructionRef = keccak256('REF-2');
    bytes memory _earlierSignature = _sign(_aliceKey, address(_token), _earlier);
    bytes memory _laterSignature = _sign(_aliceKey, address(_token), _later);

    vm.startPrank(_executor);
    _token.executeInstruction(_later, _laterSignature);
    _token.executeInstruction(_earlier, _earlierSignature);
    vm.stopPrank();
    assertEq(_token.balanceOf(_bob), 2 * _AMOUNT);
  }

  /// @notice The signature covers every field, so the executor can change none of them
  function testFuzz_WhenAnyFieldChangesAfterSigning_ItReverts(
    uint256 _fieldSeed
  ) public {
    IExampleExecutorToken.Instruction memory _altered = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _altered);
    uint256 _field = bound(_fieldSeed, 0, 5);
    if (_field == 0) _altered.from = _stranger;
    if (_field == 1) _altered.to = _stranger;
    if (_field == 2) _altered.amount = _AMOUNT + 1;
    if (_field == 3) _altered.instructionRef = keccak256('REF-2');
    if (_field == 4) _altered.deadline = _deadline + 1;
    if (_field == 5) _altered.executor = _executor; // the caller, so only the signature can refuse it

    assertFalse(_token.canExecute(_altered, _signature, _executor));
    vm.prank(_executor);
    vm.expectRevert(
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InvalidSignature.selector, _altered.from)
    );
    _token.executeInstruction(_altered, _signature);
  }

  function test_WhenAnotherAccountSigned_ItReverts() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    (, uint256 _executorKey) = makeAddrAndKey('executor');
    (, uint256 _bobKey) = makeAddrAndKey('bob');
    bytes memory _byExecutor = _sign(_executorKey, address(_token), _built);
    bytes memory _byPayee = _sign(_bobKey, address(_token), _built);
    bytes memory _invalid =
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InvalidSignature.selector, _alice);

    vm.startPrank(_executor);
    vm.expectRevert(_invalid);
    _token.executeInstruction(_built, _byExecutor);
    vm.expectRevert(_invalid);
    _token.executeInstruction(_built, _byPayee);
    vm.stopPrank();
  }

  function test_WhenTheSignatureIsForAnotherTokenOrChain_ItReverts() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    ExampleExecutorToken _otherToken = new ExampleExecutorToken(_TOKEN_NAME, 'EX', _admin);
    bytes memory _forOtherToken = _sign(_aliceKey, address(_otherToken), _built);
    bytes memory _forThisChain = _sign(_aliceKey, address(_token), _built);
    bytes memory _invalid =
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InvalidSignature.selector, _alice);

    vm.prank(_executor);
    vm.expectRevert(_invalid);
    _token.executeInstruction(_built, _forOtherToken);

    vm.chainId(block.chainid + 1);
    vm.prank(_executor);
    vm.expectRevert(_invalid);
    _token.executeInstruction(_built, _forThisChain);
  }

  /// @notice No signature can stand for the zero address, so an instruction can never be a mint
  function test_WhenFromIsZero_ItReverts() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.from = address(0);
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    bytes memory _invalid =
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InvalidSignature.selector, address(0));

    vm.startPrank(_executor);
    vm.expectRevert(_invalid);
    _token.executeInstruction(_built, _signature);
    vm.expectRevert(_invalid);
    _token.executeInstruction(_built, hex'00');
    vm.stopPrank();
  }

  function test_WhenTheSignatureIsMalformed_ItRevertsWithTheError() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_aliceKey, _digest(address(_token), _built));
    uint256 _order = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    bytes memory _highS = abi.encodePacked(_r, bytes32(_order - uint256(_s)), _v == 27 ? uint8(28) : uint8(27));
    bytes[3] memory _malformed = [bytes(''), bytes(hex'c0ffee'), _highS];
    bytes memory _invalid =
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InvalidSignature.selector, _alice);

    for (uint256 _i; _i < _malformed.length; ++_i) {
      assertFalse(_token.canExecute(_built, _malformed[_i], _executor));
      vm.prank(_executor);
      vm.expectRevert(_invalid);
      _token.executeInstruction(_built, _malformed[_i]);
    }
  }

  /// @notice The wallet approves the digest the test computed, so the token must ask about exactly that one
  function test_WhenAContractHolderApproves_ItExecutes() public {
    ContractHolder _wallet = new ContractHolder();
    vm.prank(_minter);
    _token.mint(address(_wallet), 100);
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.from = address(_wallet);
    _wallet.approve(_digest(address(_token), _built));

    assertTrue(_token.canExecute(_built, hex'c0ffee', _executor));
    vm.prank(_executor);
    _token.executeInstruction(_built, hex'c0ffee');
    assertEq(_token.balanceOf(_bob), _AMOUNT);
  }

  function test_WhenAContractHolderRefusesOrReverts_ItReverts() public {
    ContractHolder _wallet = new ContractHolder();
    vm.prank(_minter);
    _token.mint(address(_wallet), 100);
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.from = address(_wallet);
    bytes memory _invalid =
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InvalidSignature.selector, address(_wallet));

    assertFalse(_token.canExecute(_built, '', _executor));
    vm.prank(_executor);
    vm.expectRevert(_invalid);
    _token.executeInstruction(_built, '');

    _wallet.approve(_digest(address(_token), _built));
    _wallet.setReverts(true);
    assertFalse(_token.canExecute(_built, '', _executor));
    vm.prank(_executor);
    vm.expectRevert(_invalid);
    _token.executeInstruction(_built, '');
  }

  /*///////////////////////////////////////////////////////////////
                            THE NAMED EXECUTOR
  //////////////////////////////////////////////////////////////*/

  function test_WhenTheInstructionNamesTheCaller_ItExecutes() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.executor = _executor;
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);

    vm.prank(_executor);
    _token.executeInstruction(_built, _signature);
    assertEq(_token.balanceOf(_bob), _AMOUNT);
  }

  /// @notice The revert leaves the reference free, so the wrong executor cannot use up the holder's instruction
  function test_WhenTheInstructionNamesAnotherExecutor_ItRevertsAndStaysUsable() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.executor = _executor;
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);

    vm.prank(_otherExecutor);
    vm.expectRevert(
      abi.encodeWithSelector(
        IExampleExecutorToken.ExampleExecutorToken_WrongExecutor.selector, _executor, _otherExecutor
      )
    );
    _token.executeInstruction(_built, _signature);
    assertFalse(_token.instructionUsed(_alice, _REF));

    vm.prank(_executor);
    _token.executeInstruction(_built, _signature);
    assertEq(_token.balanceOf(_bob), _AMOUNT);
  }

  /// @notice Kind rule 4: the name limits which granted account may call, and grants nothing
  function test_WhenTheNamedAccountLacksTheRole_ItReverts() public {
    bytes32 _executorRole = _token.EXECUTOR_ROLE();
    address[3] memory _named = [_stranger, _alice, _bob];

    for (uint256 _i; _i < _named.length; ++_i) {
      IExampleExecutorToken.Instruction memory _built = _instruction();
      _built.executor = _named[_i];
      bytes memory _signature = _sign(_aliceKey, address(_token), _built);

      assertFalse(_token.canExecute(_built, _signature, _named[_i]));
      vm.prank(_named[_i]);
      vm.expectRevert(
        abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _named[_i], _executorRole)
      );
      _token.executeInstruction(_built, _signature);
    }
    assertEq(_token.balanceOf(_bob), 0);
  }

  /// @notice The signature covers the name, so another executor can neither clear it nor put itself there
  function test_WhenAnExecutorClearsOrChangesTheName_ItReverts() public {
    IExampleExecutorToken.Instruction memory _signed = _instruction();
    _signed.executor = _executor;
    bytes memory _signature = _sign(_aliceKey, address(_token), _signed);
    IExampleExecutorToken.Instruction memory _cleared = _instruction();
    IExampleExecutorToken.Instruction memory _changed = _instruction();
    _changed.executor = _otherExecutor;
    bytes memory _invalid =
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InvalidSignature.selector, _alice);

    vm.startPrank(_otherExecutor);
    vm.expectRevert(_invalid);
    _token.executeInstruction(_cleared, _signature);
    vm.expectRevert(_invalid);
    _token.executeInstruction(_changed, _signature);
    vm.stopPrank();
    assertEq(_token.balanceOf(_bob), 0);
  }

  /// @notice The answer follows the argument, whoever runs the simulation
  function test_CanExecute_WhenAnotherExecutorIsNamed_ItIsFalseWithoutAsking() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.executor = _executor;
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    address[3] memory _callers = [_executor, _otherExecutor, _stranger];

    vm.expectCall(_policy, abi.encodeWithSelector(IERC8473Policy.checkTransfer.selector), 0);
    for (uint256 _i; _i < _callers.length; ++_i) {
      vm.prank(_callers[_i]);
      assertFalse(_token.canExecute(_built, _signature, _otherExecutor));
    }
  }

  /// @notice The answer follows the argument, whoever runs the simulation
  function test_CanExecute_WhenTheNamedExecutorIsAsked_ItIsTrueWhoeverRunsIt() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.executor = _executor;
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    address[3] memory _callers = [_executor, _otherExecutor, _stranger];

    for (uint256 _i; _i < _callers.length; ++_i) {
      vm.prank(_callers[_i]);
      assertTrue(_token.canExecute(_built, _signature, _executor));
    }
  }

  /*///////////////////////////////////////////////////////////////
                            CANCELLING
  //////////////////////////////////////////////////////////////*/

  function test_WhenTheHolderCancels_ItEmitsAndTheInstructionCannotExecute() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    assertTrue(_token.canExecute(_built, _signature, _executor));

    vm.expectEmit(address(_token));
    emit IExampleExecutorToken.InstructionCancelled(_alice, _REF);
    vm.prank(_alice);
    _token.cancelInstruction(_REF);

    assertTrue(_token.instructionUsed(_alice, _REF));
    assertFalse(_token.canExecute(_built, _signature, _executor));
    vm.prank(_executor);
    vm.expectRevert(
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InstructionUsed.selector, _alice, _REF)
    );
    _token.executeInstruction(_built, _signature);
    assertEq(_token.balanceOf(_bob), 0);
  }

  /// @notice A holder whose cancel lost the race finds out, and one reference is never both executed and cancelled
  function test_WhenTheReferenceWasUsedOrCancelled_CancelReverts() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    bytes32 _otherRef = keccak256('REF-2');
    vm.prank(_executor);
    _token.executeInstruction(_built, _signature);

    vm.startPrank(_alice);
    vm.expectRevert(
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InstructionUsed.selector, _alice, _REF)
    );
    _token.cancelInstruction(_REF);

    _token.cancelInstruction(_otherRef);
    vm.expectRevert(
      abi.encodeWithSelector(IExampleExecutorToken.ExampleExecutorToken_InstructionUsed.selector, _alice, _otherRef)
    );
    _token.cancelInstruction(_otherRef);
    vm.stopPrank();
  }

  /// @notice The record is the caller's own, so nobody else can stop a holder's instruction
  function test_WhenAnotherAccountCancelsTheReference_TheHoldersIsUntouched() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    address[2] memory _callers = [_stranger, _executor];

    for (uint256 _i; _i < _callers.length; ++_i) {
      vm.prank(_callers[_i]);
      _token.cancelInstruction(_REF);
      assertTrue(_token.instructionUsed(_callers[_i], _REF));
    }
    assertFalse(_token.instructionUsed(_alice, _REF));

    vm.prank(_executor);
    _token.executeInstruction(_built, _signature);
    assertEq(_token.balanceOf(_bob), _AMOUNT);
  }

  /// @notice The wallet still approves the digest, so only the record can refuse it
  function test_WhenAContractHolderCancels_ItsRecordIsSet() public {
    ContractHolder _wallet = new ContractHolder();
    vm.prank(_minter);
    _token.mint(address(_wallet), 100);
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.from = address(_wallet);
    _wallet.approve(_digest(address(_token), _built));
    assertTrue(_token.canExecute(_built, hex'c0ffee', _executor));

    vm.prank(address(_wallet));
    _token.cancelInstruction(_REF);

    assertFalse(_token.canExecute(_built, hex'c0ffee', _executor));
    vm.prank(_executor);
    vm.expectRevert(
      abi.encodeWithSelector(
        IExampleExecutorToken.ExampleExecutorToken_InstructionUsed.selector, address(_wallet), _REF
      )
    );
    _token.executeInstruction(_built, hex'c0ffee');
  }

  /// @notice It is not a movement: the pause does not apply and the policy is not asked
  function test_WhenPaused_CancelStillWorksWithoutAskingThePolicy() public {
    vm.prank(_pauser);
    _token.pause();

    vm.expectCall(_policy, abi.encodeWithSelector(IERC8473Policy.checkTransfer.selector), 0);
    vm.prank(_alice);
    _token.cancelInstruction(_REF);
    assertTrue(_token.instructionUsed(_alice, _REF));
  }

  /*///////////////////////////////////////////////////////////////
                            THE TOKEN'S CHECKS AND THE POLICY
  //////////////////////////////////////////////////////////////*/

  function test_WhenPaused_ItRevertsAndCanExecuteIsFalse() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    vm.prank(_pauser);
    _token.pause();

    assertFalse(_token.canExecute(_built, _signature, _executor));
    vm.prank(_executor);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    _token.executeInstruction(_built, _signature);
  }

  function test_WhenFrozen_ItRevertsWithTheERC7943ErrorAndAnOverdraftWithTheERC20Error() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.amount = 51;
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    vm.prank(_enforcer);
    _token.setFrozenTokens(_alice, 950);

    assertFalse(_token.canExecute(_built, _signature, _executor));
    vm.prank(_executor);
    vm.expectRevert(
      abi.encodeWithSelector(IERC7943Fungible.ERC7943InsufficientUnfrozenBalance.selector, _alice, 51, 50)
    );
    _token.executeInstruction(_built, _signature);

    _built.amount = 1001;
    _signature = _sign(_aliceKey, address(_token), _built);
    vm.prank(_executor);
    vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, _alice, 1000, 1001));
    _token.executeInstruction(_built, _signature);
  }

  /// @notice The revert undoes the record of the reference, so the instruction can be retried until its deadline
  function test_WhenThePolicyRejects_ItRevertsWithTheReasonAndTheInstructionStaysUsable() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    _rejectTransfers();

    assertFalse(_token.canExecute(_built, _signature, _executor));
    vm.prank(_executor);
    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _REJECT));
    _token.executeInstruction(_built, _signature);
    assertFalse(_token.instructionUsed(_alice, _REF));

    vm.mockCall(_policy, abi.encodeWithSelector(IERC8473Policy.checkTransfer.selector), abi.encode(TRANSFER_OK));
    vm.prank(_executor);
    _token.executeInstruction(_built, _signature);
    assertEq(_token.balanceOf(_bob), _AMOUNT);
  }

  /*///////////////////////////////////////////////////////////////
                            THE PRE-FLIGHT
  //////////////////////////////////////////////////////////////*/

  /// @notice Check rule 6: the same context as the execution. `operator` is the argument, whoever runs the simulation
  function test_CanExecute_WhenEverythingPasses_ItAsksWithTheExecutionContext() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    IERC8473Policy.TransferContext memory _expected = _executedCtx(_executor);

    vm.expectCall(_policy, abi.encodeCall(IERC8473Policy.checkTransfer, (_expected)), 2);
    vm.prank(_stranger);
    assertTrue(_token.canExecute(_built, _signature, _executor));
    vm.prank(_alice);
    assertTrue(_token.canExecute(_built, _signature, _executor));
  }

  function test_CanExecute_WhenTheExecutorLacksTheRole_ItIsFalseWithoutAsking() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);

    vm.expectCall(_policy, abi.encodeWithSelector(IERC8473Policy.checkTransfer.selector), 0);
    assertFalse(_token.canExecute(_built, _signature, _stranger));
    assertFalse(_token.canExecute(_built, _signature, _alice));
    assertFalse(_token.canExecute(_built, _signature, address(0)));
  }

  function test_CanExecute_WhenTheInstructionIsInvalid_ItIsFalseWithoutAsking() public {
    IExampleExecutorToken.Instruction memory _valid = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _valid);
    (, uint256 _bobKey) = makeAddrAndKey('bob');
    bytes memory _wrongSigner = _sign(_bobKey, address(_token), _valid);
    IExampleExecutorToken.Instruction memory _zeroReceiver = _instruction();
    _zeroReceiver.to = address(0);
    bytes memory _zeroReceiverSignature = _sign(_aliceKey, address(_token), _zeroReceiver);
    IExampleExecutorToken.Instruction memory _used = _instruction();
    _used.instructionRef = keccak256('REF-2');
    bytes memory _usedSignature = _sign(_aliceKey, address(_token), _used);
    vm.prank(_executor);
    _token.executeInstruction(_used, _usedSignature);
    assertTrue(_token.canExecute(_valid, _signature, _executor));

    vm.expectCall(_policy, abi.encodeWithSelector(IERC8473Policy.checkTransfer.selector), 0);
    assertFalse(_token.canExecute(_zeroReceiver, _zeroReceiverSignature, _executor));
    assertFalse(_token.canExecute(_used, _usedSignature, _executor));
    assertFalse(_token.canExecute(_valid, _wrongSigner, _executor));
    vm.warp(_deadline + 1);
    assertFalse(_token.canExecute(_valid, _signature, _executor));
  }

  /// @notice Unlike `canTransfer`, which ERC-7943 leaves blind to the balance, this answer is the whole outcome
  function test_CanExecute_WhenTheAmountExceedsTheBalance_ItIsFalse() public view {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    _built.amount = 1001;
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);
    assertFalse(_token.canExecute(_built, _signature, _executor));
    assertTrue(_token.canTransfer(_alice, _bob, 1001));
  }

  function test_CanExecute_WhenThePolicyFails_ItIsFalseWithoutReverting() public {
    IExampleExecutorToken.Instruction memory _built = _instruction();
    bytes memory _signature = _sign(_aliceKey, address(_token), _built);

    vm.mockCallRevert(_policy, abi.encodeWithSelector(IERC8473Policy.checkTransfer.selector), 'failure');
    assertFalse(_token.canExecute(_built, _signature, _executor));

    vm.mockCall(
      _policy, abi.encodeWithSelector(IERC8473Policy.checkTransfer.selector), abi.encodePacked(bytes31(TRANSFER_OK))
    );
    assertFalse(_token.canExecute(_built, _signature, _executor));

    vm.clearMockedCalls(); // mocks would otherwise answer for the address even without code
    vm.etch(_policy, '');
    assertFalse(_token.canExecute(_built, _signature, _executor));

    ExampleExecutorToken _noPolicy = new ExampleExecutorToken(_TOKEN_NAME, 'EX', _admin);
    bytes32 _executorRole = _noPolicy.EXECUTOR_ROLE();
    vm.prank(_admin);
    _noPolicy.grantRole(_executorRole, _executor);
    _built.amount = 0; // this token has no supply; a zero amount reaches the policy question
    bytes memory _noPolicySignature = _sign(_aliceKey, address(_noPolicy), _built);
    assertFalse(_noPolicy.canExecute(_built, _noPolicySignature, _executor));
  }
}
