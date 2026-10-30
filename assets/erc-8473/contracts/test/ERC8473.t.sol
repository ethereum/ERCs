// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from '@openzeppelin/contracts/interfaces/draft-IERC6093.sol';
import {Pausable} from '@openzeppelin/contracts/utils/Pausable.sol';
import {ReentrancyGuardTransient} from '@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol';

import {IERC7943Fungible} from 'interfaces/IERC7943Fungible.sol';
import {IERC8473} from 'interfaces/IERC8473.sol';
import {IERC8473Policy, TRANSFER_OK} from 'interfaces/IERC8473Policy.sol';
import {IExamplePolicy} from 'interfaces/IExamplePolicy.sol';

import {ExamplePolicy} from 'contracts/example/ExamplePolicy.sol';
import {ExampleToken} from 'contracts/example/ExampleToken.sol';
import {
  BadBoolPolicy,
  EchoContract,
  ForgetfulPolicy,
  GasBurningPolicy,
  InstallRecorderPolicy,
  ReentrantInstallPolicy,
  ReentrantPolicy,
  RevertingInstallPolicy,
  RevertingPolicy,
  ShortBoolPolicy,
  ShortReturnPolicy
} from 'contracts/test/FaultyPolicies.sol';
import {ForcedThenTransfer} from 'contracts/test/ForcedThenTransfer.sol';
import {Helpers} from 'contracts/test/Helpers.sol';

/// @notice The ERC-20 Transfer event, for `vm.expectEmit`
interface IERC20Events {
  event Transfer(address indexed from, address indexed to, uint256 value);
}

/// @notice ERC-8473 conformance: the example token and policy together, and the token against faulty policies
contract ERC8473IntegrationTest is Helpers {
  struct Scenario {
    uint8 allowMask;
    bool paused;
    uint256 frozen;
    uint256 cap;
  }

  address internal _admin = makeAddr('admin');
  address internal _minter = makeAddr('minter');
  address internal _enforcer = makeAddr('enforcer');
  address internal _pauser = makeAddr('pauser');
  address internal _spender = makeAddr('spender');
  address[4] internal _actors = [makeAddr('a'), makeAddr('b'), makeAddr('c'), makeAddr('d')];

  ExamplePolicy internal _policy;
  ExampleToken internal _token;

  function setUp() public {
    _token = new ExampleToken('Example', 'EX', _admin);
    _policy = new ExamplePolicy(address(_token), _admin, 10);
    _installWithHolders(address(_policy), new address[](0)); // no supply yet

    vm.startPrank(_admin);
    _token.grantRole(_token.MINTER_ROLE(), _minter);
    _token.grantRole(_token.ENFORCER_ROLE(), _enforcer);
    _token.grantRole(_token.PAUSER_ROLE(), _pauser);
    for (uint256 _i; _i < _actors.length; ++_i) {
      _policy.setAllowlisted(_actors[_i], true);
    }
    vm.stopPrank();

    vm.startPrank(_minter);
    _token.mint(_actors[0], 1000);
    _token.mint(_actors[1], 1000);
    vm.stopPrank();
    assertEq(_policy.holderCount(), 2);

    for (uint256 _i; _i < _actors.length; ++_i) {
      vm.prank(_actors[_i]);
      _token.approve(_spender, type(uint256).max);
    }
  }

  function _install(
    address _newPolicy
  ) internal {
    vm.prank(_admin);
    _token.setPolicy(_newPolicy, '');
  }

  /**
   * @notice Installs a policy with a holder list, sorted here, as its `onInstall` data
   * @param _newPolicy The policy
   * @param _holders The accounts, in any order
   */
  function _installWithHolders(
    address _newPolicy,
    address[] memory _holders
  ) internal {
    vm.prank(_admin);
    _token.setPolicy(_newPolicy, abi.encode(_ascending(_holders)));
  }

  /// @notice Every actor: a list that covers every account the example policy lets hold the token
  function _everyActor() internal view returns (address[] memory _list) {
    _list = new address[](_actors.length);
    for (uint256 _i; _i < _actors.length; ++_i) {
      _list[_i] = _actors[_i];
    }
  }

  function _transferContext() internal view returns (IERC8473Policy.TransferContext memory _context) {
    _context = IERC8473Policy.TransferContext({
      token: address(_token),
      from: _actors[0],
      to: _actors[1],
      tokenId: 0,
      amount: 1,
      operator: _actors[0],
      kind: IERC8473Policy.TransferKind.TRANSFER,
      data: ''
    });
  }

  /*///////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  function test_SelectorsInterfaceIdsAndTheSuccessValue() public pure {
    assertEq(TRANSFER_OK, keccak256('TRANSFER_OK'));
    assertEq(TRANSFER_OK, 0xf059ed422c5a003e2d831cdef17f0af416cf22aae18c781d82aaacaa5c77fd3f);
    assertEq(IERC8473Policy.checkSend.selector, bytes4(0xec1cb5d7));
    assertEq(IERC8473Policy.checkReceive.selector, bytes4(0x8b203e96));
    assertEq(IERC8473Policy.checkTransfer.selector, bytes4(0x64a1a08e));
    assertEq(IERC8473Policy.wantsAfterTransfer.selector, bytes4(0x38bff1a5));
    assertEq(IERC8473Policy.afterTransfer.selector, bytes4(0x2595b359));
    assertEq(IERC8473Policy.onInstall.selector, bytes4(0x820203aa));
    assertEq(IERC8473.policy.selector, bytes4(0x0505c8c9));
    assertEq(IERC8473.ERC8473PolicyRejected.selector, bytes4(0x295e60b5));
    assertEq(
      IERC8473Policy.checkTransfer.selector,
      bytes4(keccak256('checkTransfer((address,address,address,uint256,uint256,address,uint8,bytes))'))
    );
    assertEq(type(IERC8473Policy).interfaceId, bytes4(0x9cb56a99));
    assertEq(type(IERC8473).interfaceId, bytes4(0x0505c8c9));
    assertEq(type(IERC7943Fungible).interfaceId, bytes4(0x3edbb4c4)); // as stated in ERC-7943
  }

  /*///////////////////////////////////////////////////////////////
                            FAILING CLOSED
  //////////////////////////////////////////////////////////////*/

  /// @notice A forgotten branch returns zero. Zero is not success, so the movement is rejected and the pre-flight agrees
  function test_WhenAPolicyForgetsAKind_ItsZeroRejects() public {
    _install(address(new ForgetfulPolicy()));

    assertFalse(_token.canTransfer(address(0), _actors[2], 1));
    vm.prank(_minter);
    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, bytes32(0)));
    _token.mint(_actors[2], 1);

    assertTrue(_token.canTransfer(_actors[0], _actors[1], 1)); // the branch the author wrote still works
  }

  function test_WhenThePolicyReverts_ThePreflightIsFalseAndTheMovementReverts() public {
    _install(address(new RevertingPolicy()));

    assertFalse(_token.canTransfer(_actors[0], _actors[1], 1));
    vm.prank(_actors[0]);
    vm.expectRevert(RevertingPolicy.RevertingPolicy_Failure.selector);
    _token.transfer(_actors[1], 1);
  }

  /// @notice The token keeps 1/64 of its gas back from the call, enough to answer once the policy has burned the rest
  function test_WhenACheckRunsOutOfGas_ThePreflightIsFalseAndTheMovementReverts() public {
    uint256 _gas = 1_000_000;
    // The limit alone does not change the answer.
    assertTrue(_token.canTransfer{gas: _gas}(_actors[0], _actors[1], 1));
    _install(address(new GasBurningPolicy()));

    assertFalse(_token.canSend{gas: _gas}(_actors[0]));
    assertFalse(_token.canReceive{gas: _gas}(_actors[1]));
    assertFalse(_token.canTransfer{gas: _gas}(_actors[0], _actors[1], 1));
    vm.prank(_actors[0]);
    vm.expectRevert();
    _token.transfer{gas: _gas}(_actors[1], 1);
  }

  function test_WhenTheAnswerIsShorterThanAWord_ThePreflightIsFalseAndTheMovementReverts() public {
    _install(address(new ShortReturnPolicy()));

    assertFalse(_token.canTransfer(_actors[0], _actors[1], 1));
    vm.prank(_actors[0]);
    vm.expectRevert();
    _token.transfer(_actors[1], 1);
  }

  /// @notice A malformed `wantsAfterTransfer` answer must not be read as `false`: the callback could be skipped
  function test_WhenWantsAfterTransferIsMalformed_TheMovementReverts() public {
    _install(address(new BadBoolPolicy()));
    vm.prank(_actors[0]);
    vm.expectRevert();
    _token.transfer(_actors[1], 1);

    _install(address(new ShortBoolPolicy()));
    vm.prank(_actors[0]);
    vm.expectRevert();
    _token.transfer(_actors[1], 1);
  }

  /// @notice Why the success value is not a selector: an echo of `checkTransfer` calldata is `bytes32(selector)`,
  ///         because the first argument word of a call with one dynamic tuple is the offset 0x20
  function test_AnEchoingContractReturnsTheSelectorWord() public {
    EchoContract _echo = new EchoContract();
    bytes32 _answer = IERC8473Policy(address(_echo)).checkTransfer(_transferContext());
    assertEq(_answer, bytes32(IERC8473Policy.checkTransfer.selector));
    assertTrue(_answer != TRANSFER_OK);
  }

  /*///////////////////////////////////////////////////////////////
                            CALLBACK
  //////////////////////////////////////////////////////////////*/

  function test_AfterTransferCannotStartAnotherMovement() public {
    ReentrantPolicy _reentrant = new ReentrantPolicy();
    // Fund it while the example policy is installed, then install it.
    vm.prank(_admin);
    _policy.setAllowlisted(address(_reentrant), true);
    vm.prank(_minter);
    _token.mint(address(_reentrant), 10);
    _install(address(_reentrant));

    vm.prank(_actors[0]);
    vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
    _token.transfer(_actors[1], 1);
  }

  /*///////////////////////////////////////////////////////////////
                            INSTALLATION
  //////////////////////////////////////////////////////////////*/

  function test_OnInstallRunsAfterThePolicySwitchesWithThePreviousPolicyAndTheData() public {
    InstallRecorderPolicy _recorder = new InstallRecorderPolicy();
    vm.prank(_admin);
    _token.setPolicy(address(_recorder), hex'c0ffee');
    assertEq(_recorder.seenPolicy(), address(_recorder));
    assertEq(_recorder.seenPrevious(), address(_policy));
    assertEq(_recorder.seenData(), hex'c0ffee');
  }

  function test_WhenOnInstallReverts_ThePreviousPolicyStays() public {
    address _reverting = address(new RevertingInstallPolicy());
    vm.prank(_admin);
    vm.expectRevert(RevertingInstallPolicy.RevertingInstallPolicy_Failure.selector);
    _token.setPolicy(_reverting, '');
    assertEq(_token.policy(), address(_policy));
  }

  function test_OnInstallCannotStartAMovementOrAnotherInstallation() public {
    address _mover = address(new ReentrantInstallPolicy(address(0)));
    vm.prank(_admin);
    vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
    _token.setPolicy(_mover, '');

    address _installer = address(new ReentrantInstallPolicy(address(new ForgetfulPolicy())));
    bytes32 _adminRole = _token.DEFAULT_ADMIN_ROLE();
    vm.startPrank(_admin);
    _token.grantRole(_adminRole, _installer);
    vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
    _token.setPolicy(_installer, '');
    vm.stopPrank();
    assertEq(_token.policy(), address(_policy));
  }

  /*///////////////////////////////////////////////////////////////
                            ERC-7943 CHECKS
  //////////////////////////////////////////////////////////////*/

  function test_CanSendAndCanReceiveFollowThePolicy() public {
    assertTrue(_token.canSend(_actors[0]));
    assertTrue(_token.canReceive(_actors[0]));
    vm.prank(_admin);
    _policy.setAllowlisted(_actors[0], false);
    assertFalse(_token.canSend(_actors[0]));
    assertFalse(_token.canReceive(_actors[0]));
    // ERC-7943: canTransfer performs both checks; here they arrive through checkTransfer.
    assertFalse(_token.canTransfer(_actors[0], _actors[1], 1));
    assertFalse(_token.canTransfer(_actors[1], _actors[0], 1));
  }

  /// @notice ERC-7943: canTransfer performs canSend on `from` and canReceive on `to`, zero included. The zero address
  ///         passes both, so the account checks of a mint fall on `to` alone and those of a burn on `from` alone
  function test_TheZeroAddressPassesBothAccountChecks() public {
    vm.prank(_admin);
    _policy.setAllowlisted(_actors[0], false);
    assertTrue(_token.canSend(address(0)));
    assertTrue(_token.canReceive(address(0)));
    assertTrue(_token.canTransfer(address(0), _actors[1], 1));
    assertFalse(_token.canTransfer(address(0), _actors[0], 1));
    assertTrue(_token.canTransfer(_actors[1], address(0), 1));
    assertFalse(_token.canTransfer(_actors[0], address(0), 1));
  }

  /// @notice Passing canReceive does not make the zero address a destination: the base token still rejects it
  function test_APlainTransferToTheZeroAddressStillReverts() public {
    assertTrue(_token.canReceive(address(0)));
    vm.prank(_actors[0]);
    vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    _token.transfer(address(0), 1);
  }

  /*///////////////////////////////////////////////////////////////
                            PRE-FLIGHT PARITY
  //////////////////////////////////////////////////////////////*/

  function _scenario(
    uint8 _allowMask,
    bool _paused,
    uint256 _frozen,
    uint256 _cap
  ) internal pure returns (Scenario memory _s) {
    _s = Scenario({allowMask: _allowMask, paused: _paused, frozen: bound(_frozen, 0, 1500), cap: bound(_cap, 0, 4)});
  }

  function _apply(
    Scenario memory _s,
    address _from
  ) internal {
    vm.startPrank(_admin);
    for (uint256 _i; _i < _actors.length; ++_i) {
      _policy.setAllowlisted(_actors[_i], (_s.allowMask >> _i) & 1 == 1);
    }
    _policy.setCap(_s.cap);
    vm.stopPrank();
    if (_from != address(0)) {
      vm.prank(_enforcer);
      _token.setFrozenTokens(_from, _s.frozen);
    }
    if (_s.paused) {
      vm.prank(_pauser);
      _token.pause();
    }
  }

  function testFuzz_CanTransferPredictsTransfer(
    uint8 _allowMask,
    bool _paused,
    uint256 _frozen,
    uint256 _cap,
    uint256 _fromSeed,
    uint256 _toSeed,
    uint256 _amount
  ) public {
    address _from = _actors[bound(_fromSeed, 0, 3)];
    address _to = _actors[bound(_toSeed, 0, 3)];
    _amount = bound(_amount, 0, 1200);
    _apply(_scenario(_allowMask, _paused, _frozen, _cap), _from);

    bool _predicted = _token.canTransfer(_from, _to, _amount);
    // ERC-7943 leaves a balance shortfall to the base standard, so `canTransfer` does not predict it.
    bool _withinBalance = _amount <= _token.balanceOf(_from);
    vm.prank(_from);
    (bool _succeeded,) = address(_token).call(abi.encodeCall(_token.transfer, (_to, _amount)));
    assertEq(_succeeded, _predicted && _withinBalance);
  }

  /// @notice The same decision when a spender submits: TRANSFER does not depend on `operator`
  function testFuzz_CanTransferPredictsTransferFrom(
    uint8 _allowMask,
    bool _paused,
    uint256 _frozen,
    uint256 _cap,
    uint256 _fromSeed,
    uint256 _toSeed,
    uint256 _amount
  ) public {
    address _from = _actors[bound(_fromSeed, 0, 3)];
    address _to = _actors[bound(_toSeed, 0, 3)];
    _amount = bound(_amount, 0, 1200);
    _apply(_scenario(_allowMask, _paused, _frozen, _cap), _from);

    bool _predicted = _token.canTransfer(_from, _to, _amount);
    bool _withinBalance = _amount <= _token.balanceOf(_from);
    vm.prank(_spender);
    (bool _succeeded,) = address(_token).call(abi.encodeCall(_token.transferFrom, (_from, _to, _amount)));
    assertEq(_succeeded, _predicted && _withinBalance);
  }

  function testFuzz_CanTransferPredictsMint(
    uint8 _allowMask,
    bool _paused,
    uint256 _cap,
    uint256 _toSeed,
    uint256 _amount
  ) public {
    address _to = _actors[bound(_toSeed, 0, 3)];
    _amount = bound(_amount, 0, 1200);
    _apply(_scenario(_allowMask, _paused, 0, _cap), address(0));

    bool _predicted = _token.canTransfer(address(0), _to, _amount);
    vm.prank(_minter);
    (bool _succeeded,) = address(_token).call(abi.encodeCall(_token.mint, (_to, _amount)));
    assertEq(_succeeded, _predicted);
  }

  function testFuzz_CanTransferPredictsBurn(
    uint8 _allowMask,
    bool _paused,
    uint256 _frozen,
    uint256 _cap,
    uint256 _fromSeed,
    uint256 _amount
  ) public {
    address _from = _actors[bound(_fromSeed, 0, 3)];
    _amount = bound(_amount, 0, 1200);
    _apply(_scenario(_allowMask, _paused, _frozen, _cap), _from);

    bool _predicted = _token.canTransfer(_from, address(0), _amount);
    bool _withinBalance = _amount <= _token.balanceOf(_from);
    vm.prank(_from);
    (bool _succeeded,) = address(_token).call(abi.encodeCall(_token.burn, (_amount)));
    assertEq(_succeeded, _predicted && _withinBalance);
  }

  /*///////////////////////////////////////////////////////////////
                            HOLDER CAP
  //////////////////////////////////////////////////////////////*/

  function test_AFullBalanceMoveToANewHolderPassesAtTheCap() public {
    vm.prank(_admin);
    _policy.setCap(2);
    assertFalse(_token.canTransfer(_actors[0], _actors[2], 999)); // a third holder
    assertTrue(_token.canTransfer(_actors[0], _actors[2], 1000)); // net zero: actors[0] leaves
    vm.prank(_actors[0]);
    _token.transfer(_actors[2], 1000);
    assertEq(_policy.holderCount(), 2);
  }

  function test_ALoweredCapIsARatchet() public {
    vm.prank(_admin);
    _policy.setCap(1);
    assertFalse(_token.canTransfer(_actors[0], _actors[2], 1000)); // net zero, but the count is above the cap
    assertTrue(_token.canTransfer(_actors[0], _actors[1], 1)); // existing holders still transact
    assertTrue(_token.canTransfer(_actors[0], address(0), 1000)); // and can exit
  }

  /*///////////////////////////////////////////////////////////////
                            REPLACING THE POLICY ON A LIVE TOKEN
  //////////////////////////////////////////////////////////////*/

  /// @notice A second example policy for the same token, allowlisting every actor
  function _secondPolicy() internal returns (ExamplePolicy _second) {
    _second = new ExamplePolicy(address(_token), _admin, 10);
    vm.startPrank(_admin);
    for (uint256 _i; _i < _actors.length; ++_i) {
      _second.setAllowlisted(_actors[_i], true);
    }
    vm.stopPrank();
  }

  function test_AReplacementInstalledWithTheHolderListLetsAHolderExit() public {
    ExamplePolicy _second = _secondPolicy();
    _installWithHolders(address(_second), _everyActor());
    assertEq(_second.holderCount(), 2); // actors[0] and actors[1]

    vm.prank(_actors[0]);
    _token.transfer(_actors[1], 1000); // a full exit to an existing holder
    assertEq(_second.holderCount(), 1);
  }

  /// @notice A replacement that is not given the holders fails closed when it is installed, not at the first exit
  function test_AReplacementInstalledWithoutTheHolderListReverts() public {
    ExamplePolicy _second = _secondPolicy();
    uint256 _supply = _token.totalSupply();
    vm.prank(_admin);
    vm.expectRevert(abi.encodeWithSelector(IExamplePolicy.ExamplePolicy_HoldersIncomplete.selector, 0, _supply));
    _token.setPolicy(address(_second), abi.encode(new address[](0)));
    assertEq(_token.policy(), address(_policy));
  }

  /// @notice A→B→A, steps 1–3: B is installed with the holders, then two holders arrive that A never sees
  function _swapAwayAndMintTwoHolders() internal returns (ExamplePolicy _b) {
    _b = _secondPolicy();
    _installWithHolders(address(_b), _everyActor());
    vm.startPrank(_minter);
    _token.mint(_actors[2], 10);
    _token.mint(_actors[3], 10);
    vm.stopPrank();
    assertEq(_b.holderCount(), 4);
  }

  /// @notice Reinstalling is an installation: A counts again, so its cap holds
  function test_AReinstalledPolicyCountsAgain() public {
    _swapAwayAndMintTwoHolders();
    vm.prank(_admin);
    _policy.setCap(4);
    _installWithHolders(address(_policy), _everyActor());
    assertEq(_policy.holderCount(), 4);

    address _fifth = makeAddr('fifth');
    bytes32 _maxHolders = _policy.MAX_HOLDERS();
    vm.prank(_admin);
    _policy.setAllowlisted(_fifth, true);
    vm.prank(_minter);
    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _maxHolders));
    _token.mint(_fifth, 10);

    vm.prank(_actors[2]);
    _token.transfer(_actors[3], 10); // a full exit to an existing holder
    assertEq(_policy.holderCount(), 3);
  }

  /// @notice A list of the holders A knew of misses the two that arrived under B, so A cannot come back with it
  function test_WhenAReinstallMissesAHolder_ItRevertsAndTheOtherPolicyStays() public {
    ExamplePolicy _b = _swapAwayAndMintTwoHolders();
    address[] memory _stale = new address[](2);
    _stale[0] = _actors[0];
    _stale[1] = _actors[1];
    uint256 _sum = _token.balanceOf(_actors[0]) + _token.balanceOf(_actors[1]);
    uint256 _supply = _token.totalSupply();

    vm.prank(_admin);
    vm.expectRevert(abi.encodeWithSelector(IExamplePolicy.ExamplePolicy_HoldersIncomplete.selector, _sum, _supply));
    _token.setPolicy(address(_policy), abi.encode(_ascending(_stale)));
    assertEq(_token.policy(), address(_b));
  }

  /**
   * @notice The snapshot window: the list is made with two holders, a third arrives before the installation runs, and
   *         the policy to install has a cap of 3
   */
  function _aHolderArrivesAfterTheListIsMade() internal returns (ExamplePolicy _b) {
    _b = _secondPolicy();
    vm.prank(_admin);
    _b.setCap(3);
    vm.prank(_actors[0]);
    _token.transfer(_actors[2], 10); // a new holder, before the installation executes
    assertEq(_policy.holderCount(), 3);
  }

  /// @notice A holder list fixed in advance fails closed when an unlisted holder arrives first
  function test_WhenAHolderArrivesBeforeTheInstallation_AListThatMissesItReverts() public {
    ExamplePolicy _b = _aHolderArrivesAfterTheListIsMade();
    address[] memory _listed = new address[](2); // the holders when the list was made
    _listed[0] = _actors[0];
    _listed[1] = _actors[1];
    uint256 _sum = _token.balanceOf(_actors[0]) + _token.balanceOf(_actors[1]);
    uint256 _supply = _token.totalSupply();

    vm.prank(_admin);
    vm.expectRevert(abi.encodeWithSelector(IExamplePolicy.ExamplePolicy_HoldersIncomplete.selector, _sum, _supply));
    _token.setPolicy(address(_b), abi.encode(_ascending(_listed)));
    assertEq(_token.policy(), address(_policy)); // nothing was installed
  }

  /// @notice A list that also names accounts that may hold by then installs the true count, however old it is
  function test_WhenAHolderArrivesBeforeTheInstallation_AListCoveringItInstallsTheTrueCount() public {
    ExamplePolicy _b = _aHolderArrivesAfterTheListIsMade();
    _installWithHolders(address(_b), _everyActor()); // actors[3] holds nothing
    assertEq(_b.holderCount(), 3);

    bytes32 _maxHolders = _b.MAX_HOLDERS();
    vm.prank(_minter);
    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _maxHolders));
    _token.mint(_actors[3], 10);
  }

  /*///////////////////////////////////////////////////////////////
                            ENFORCEMENT
  //////////////////////////////////////////////////////////////*/

  function test_AForcedTransferWorksWhilePausedAndAboveTheCapAndIsCounted() public {
    vm.prank(_admin);
    _policy.setCap(2);
    vm.prank(_enforcer);
    _token.setFrozenTokens(_actors[0], 1500); // more than the balance: also withholds future receipts
    vm.prank(_pauser);
    _token.pause();

    vm.expectEmit(address(_token));
    emit IERC7943Fungible.Frozen(_actors[0], 1400);
    vm.expectEmit(address(_token));
    emit IERC20Events.Transfer(_actors[0], _actors[2], 100);
    vm.expectEmit(address(_token));
    emit IERC7943Fungible.ForcedTransfer(_actors[0], _actors[2], 100);
    vm.prank(_enforcer);
    _token.forcedTransfer(_actors[0], _actors[2], 100);

    assertEq(_token.getFrozenTokens(_actors[0]), 1400);
    assertEq(_policy.holderCount(), 3); // exempt from the cap, still counted
  }

  /// @notice Only the frozen part of what moves is unfrozen: 1000 held, 950 frozen, 50 free; moving 100 unfreezes 50
  function test_AForcedTransferUnfreezesOnlyTheFrozenPart() public {
    vm.prank(_enforcer);
    _token.setFrozenTokens(_actors[0], 950);
    vm.expectEmit(address(_token));
    emit IERC7943Fungible.Frozen(_actors[0], 900);
    vm.prank(_enforcer);
    _token.forcedTransfer(_actors[0], _actors[2], 100);
    assertEq(_token.getFrozenTokens(_actors[0]), 900);
  }

  /// @notice While paused, a forced transfer goes through, but an ordinary transfer right after it, in the same call, does not
  function test_AForcedTransferDoesNotLeakItsKindToTheNextMovement() public {
    ForcedThenTransfer _helper = new ForcedThenTransfer();
    bytes32 _enforcerRole = _token.ENFORCER_ROLE();
    vm.startPrank(_admin);
    _token.grantRole(_enforcerRole, address(_helper));
    _policy.setAllowlisted(address(_helper), true);
    vm.stopPrank();
    vm.prank(_minter);
    _token.mint(address(_helper), 10);
    vm.prank(_pauser);
    _token.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);
    _helper.run(address(_token), _actors[0], _actors[1], 5, _actors[1], 3);
  }

  function test_AForcedTransferStillNeedsAnEligibleReceiver() public {
    vm.prank(_admin);
    _policy.setAllowlisted(_actors[2], false);
    bytes32 _reason = _policy.RECEIVER_NOT_ELIGIBLE(); // read before the prank, which the next call would consume
    vm.prank(_enforcer);
    vm.expectRevert(abi.encodeWithSelector(IERC8473.ERC8473PolicyRejected.selector, _reason));
    _token.forcedTransfer(_actors[0], _actors[2], 100);
  }

  function test_AFrozenAmountRevertsWithTheERC7943ErrorAndAnOverdraftWithTheERC20Error() public {
    vm.prank(_enforcer);
    _token.setFrozenTokens(_actors[0], 950);
    vm.prank(_actors[0]);
    vm.expectRevert(
      abi.encodeWithSelector(IERC7943Fungible.ERC7943InsufficientUnfrozenBalance.selector, _actors[0], 51, 50)
    );
    _token.transfer(_actors[1], 51);

    vm.prank(_actors[0]);
    vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, _actors[0], 1000, 1001));
    _token.transfer(_actors[1], 1001);
  }
}
