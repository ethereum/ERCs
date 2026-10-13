// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {AssetLimit, ISpendGrantRegistry, NATIVE, SpendGrant} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {SpendGrantAuthorizationExecutor} from "../src/SpendGrantAuthorizationExecutor.sol";
import {IDelegationManagerLike, SpendGrantRedemptionEnforcer} from "../src/SpendGrantRedemptionEnforcer.sol";
import {SpendGrantRedemptionExecutor} from "../src/SpendGrantRedemptionExecutor.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev The two reads the enforcer makes of MetaMask's DelegationManager v1.3.0: a delegation's hash, which commits
/// to its delegate, delegator, authority, each caveat's enforcer and keccak256(terms) (never args), and salt; and
/// ROOT_AUTHORITY. Nothing else of the manager is modelled: these tests call the hooks themselves.
contract MinimalDelegationManager {
    bytes32 public constant ROOT_AUTHORITY = bytes32(type(uint256).max);

    function getDelegationHash(IDelegationManagerLike.Delegation calldata d) external pure returns (bytes32) {
        bytes32[] memory caveatHashes = new bytes32[](d.caveats.length);
        for (uint256 c = 0; c < d.caveats.length; c++) {
            caveatHashes[c] = keccak256(abi.encode(d.caveats[c].enforcer, keccak256(d.caveats[c].terms)));
        }
        return keccak256(
            abi.encode(d.delegate, d.delegator, d.authority, keccak256(abi.encodePacked(caveatHashes)), d.salt)
        );
    }
}

/// @dev One principal, one delegate, one fixed payee and one token; grants are registered on a real registry.
abstract contract SmokeBase is Test {
    bytes4 internal constant SPEND_GRANT_ERROR = bytes4(keccak256("SpendGrantError(uint8)"));
    uint256 internal constant DELEGATE_PK = 0xB0B;

    MockERC20 internal token;
    address internal principal;
    address internal delegate;
    address internal payee;
    address internal stranger;

    function _actors() internal {
        vm.warp(1_700_000_000);
        principal = makeAddr("principal");
        delegate = vm.addr(DELEGATE_PK);
        payee = makeAddr("payee");
        stranger = makeAddr("stranger");
        token = new MockERC20();
    }

    function _terms() internal view returns (SpendGrant memory g) {
        uint64 t = uint64(vm.getBlockTimestamp());
        g.principal = principal;
        g.delegate = delegate;
        g.recipientMode = 0;
        g.recipient = payee;
        g.windowSeconds = 1 days;
        g.assets = new AssetLimit[](1);
        g.assets[0] = AssetLimit(address(token), 100, 1000, 5000);
        g.validAfter = t;
        g.validUntil = t + 30 days;
        g.salt = 1;
    }

    function _register(SpendGrantRegistry registry, SpendGrant memory g) internal returns (bytes32 id) {
        vm.prank(g.principal);
        id = registry.register(g);
    }

    function _fund(address executor) internal {
        token.mint(principal, 1e6);
        vm.prank(principal);
        token.approve(executor, type(uint256).max);
    }

    /// `SpendGrantError(uint8)` carrying the literal reason number.
    function _err(uint8 reason) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SPEND_GRANT_ERROR, reason);
    }
}

/// @notice The base executor: the delegate calls `spend(grantId, asset, amount, recipient)` itself.
contract SpendGrantDirectSmokeTest is SmokeBase {
    SpendGrantRegistry internal registry;
    SpendGrantExecutor internal executor;

    function setUp() public {
        _actors();
        uint64 nonce = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), nonce + 1);
        registry = new SpendGrantRegistry(predicted);
        executor = new SpendGrantExecutor(registry);
        assertEq(address(executor), predicted);
        _fund(address(executor));
    }

    /// The delegate holds only the id; the executor reads the principal from the registry and moves from it.
    function test_direct_delegateSpendsById() public {
        bytes32 id = _register(registry, _terms());
        uint256 before = token.balanceOf(principal);

        vm.expectCall(
            address(registry), abi.encodeCall(ISpendGrantRegistry.consume, (id, delegate, address(token), 40, payee)), 1
        );
        vm.prank(delegate);
        executor.spend(id, address(token), 40, payee);

        assertEq(before - token.balanceOf(principal), 40);
        assertEq(token.balanceOf(payee), 40);
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 40);
        assertEq(calls, 1);
    }

    /// An id the registry does not know is rejected by the executor itself (reason 14), never reaching consume.
    function test_direct_unknownIdIsNonexistent() public {
        bytes32 unknown = keccak256("unknown");
        vm.expectCall(address(registry), abi.encodeWithSelector(ISpendGrantRegistry.consume.selector), 0);
        vm.prank(delegate);
        vm.expectRevert(_err(14));
        executor.spend(unknown, address(token), 1, payee);
    }

    /// NATIVE is refused before the id is looked up, and even when the registry would accept the spend.
    function test_direct_nativeRequiresAccountAdapter() public {
        bytes memory nativeRefused = abi.encodeWithSelector(SpendGrantExecutor.NativeRequiresAccountAdapter.selector);
        bytes memory unknownNative =
            abi.encodeCall(SpendGrantExecutor.spend, (keccak256("unknown"), NATIVE, uint256(1), payee));
        vm.prank(delegate);
        (bool ok, bytes memory ret) = address(executor).call(unknownNative);
        assertFalse(ok);
        assertEq(ret, nativeRefused);

        SpendGrant memory g = _terms();
        g.assets[0] = AssetLimit(NATIVE, 100, 1000, 5000);
        bytes32 id = _register(registry, g);
        (bool accepted,) = registry.check(id, delegate, NATIVE, 1, payee);
        assertTrue(accepted);

        vm.prank(delegate);
        vm.expectRevert(nativeRefused);
        executor.spend(id, NATIVE, 1, payee);
    }

    /// A registry rejection reaches the caller as its exact revert data: REVOKED (5).
    function test_direct_revokedBubbles() public {
        bytes32 id = _register(registry, _terms());
        vm.prank(principal);
        registry.revoke(id);

        vm.prank(delegate);
        vm.expectRevert(_err(5));
        executor.spend(id, address(token), 1, payee);
    }

    /// A registry rejection reaches the caller as its exact revert data: WRONG_RECIPIENT (7).
    function test_direct_wrongRecipientBubbles() public {
        bytes32 id = _register(registry, _terms());
        vm.prank(delegate);
        vm.expectRevert(_err(7));
        executor.spend(id, address(token), 1, stranger);
    }

    /// Any caller but the delegate, the principal included, is passed to consume as the authorizer and rejected
    /// there with UNAUTHORIZED_DELEGATE (13).
    function test_direct_nonDelegateCallerIsUnauthorized() public {
        bytes32 id = _register(registry, _terms());
        bytes memory call = abi.encodeCall(SpendGrantExecutor.spend, (id, address(token), uint256(1), payee));
        vm.expectCall(
            address(registry), abi.encodeCall(ISpendGrantRegistry.consume, (id, principal, address(token), 1, payee)), 1
        );
        vm.prank(principal);
        (bool ok, bytes memory ret) = address(executor).call(call);
        assertFalse(ok);
        assertEq(ret, _err(13));

        vm.expectCall(
            address(registry), abi.encodeCall(ISpendGrantRegistry.consume, (id, stranger, address(token), 1, payee)), 1
        );
        vm.prank(stranger);
        vm.expectRevert(_err(13));
        executor.spend(id, address(token), 1, payee);
    }

    /// `registry()` names the registry the executor fixed at deployment, the only one it calls `consume` on.
    function test_direct_registryGetterNamesItsRegistry() public view {
        assertEq(address(executor.registry()), address(registry));
    }

    /// An executor does not deploy for a registry whose `executor()` is another address: UNAUTHORIZED_EXECUTOR (12).
    function test_direct_constructorRejectsRegistryOfAnotherExecutor() public {
        SpendGrantRegistry other = new SpendGrantRegistry(stranger);
        vm.expectRevert(_err(12));
        new SpendGrantExecutor(other);
    }
}

/// @notice The authorization executor: the delegate signs a `SpendAuthorization` over the grant id; anyone relays it.
contract SpendGrantAuthorizationSmokeTest is SmokeBase {
    uint256 internal constant STRANGER_PK = 0xBAD;
    bytes32 internal constant TYPEHASH = keccak256(
        "SpendAuthorization(bytes32 grantId,address asset,uint256 amount,address recipient,uint256 nonce,uint256 deadline)"
    );

    SpendGrantRegistry internal registry;
    SpendGrantAuthorizationExecutor internal executor;
    address internal relayer;

    event NonceCancelled(address indexed authorizer, uint256 indexed nonce);

    function setUp() public {
        _actors();
        relayer = makeAddr("relayer");
        uint64 nonce = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), nonce + 1);
        registry = new SpendGrantRegistry(predicted);
        executor = new SpendGrantAuthorizationExecutor(registry);
        assertEq(address(executor), predicted);
        _fund(address(executor));
    }

    /// The type hash is keccak256 of the literal type string, under the domain (SpendAuthorization, 1, chain,
    /// executor), and the executor's digest is the EIP-712 digest built from those here.
    function test_authorization_typehashIsTheLiteralTypeString() public view {
        assertEq(
            executor.authorizationTypehash(),
            keccak256(
                "SpendAuthorization(bytes32 grantId,address asset,uint256 amount,address recipient,uint256 nonce,uint256 deadline)"
            )
        );
        assertEq(executor.domainSeparator(), _domain());
        bytes32 id = keccak256("any id");
        assertEq(
            executor.authorizationDigest(id, address(token), 40, payee, 7, 1_700_000_600),
            _digest(id, address(token), 40, payee, 7, 1_700_000_600)
        );
    }

    /// A third party relays the delegate's signature; the token moves from the principal, the nonce is spent, and
    /// AuthorizationUsed is emitted before consume runs (it precedes the registry's GrantConsumed).
    function test_authorization_relayedDelegateSignatureSpends() public {
        bytes32 id = _register(registry, _terms());
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _sign(DELEGATE_PK, _digest(id, address(token), 40, payee, 7, deadline));
        uint256 before = token.balanceOf(principal);

        vm.recordLogs();
        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 40, payee, 7, deadline, auth);

        assertEq(before - token.balanceOf(principal), 40);
        assertEq(token.balanceOf(payee), 40);
        assertTrue(executor.nonceUsed(delegate, 7));
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 40);
        assertEq(calls, 1);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].emitter, address(executor));
        assertEq(logs[0].topics[0], keccak256("AuthorizationUsed(address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(delegate))));
        assertEq(logs[0].topics[2], bytes32(uint256(7)));
        assertEq(logs[1].emitter, address(registry));
        assertEq(logs[1].topics[0], keccak256("GrantConsumed(bytes32,address,address,uint256,address)"));
        assertEq(logs[1].topics[1], id);
    }

    /// An unknown id is NONEXISTENT (14) before any signature work: a malformed signature does not change it.
    function test_authorization_unknownIdIsNonexistent() public {
        bytes32 unknown = keccak256("unknown");
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory garbage = hex"1234";
        vm.expectCall(address(registry), abi.encodeWithSelector(ISpendGrantRegistry.consume.selector), 0);
        vm.prank(relayer);
        vm.expectRevert(_err(14));
        executor.spendWithAuthorization(unknown, address(token), 1, payee, 1, deadline, garbage);
    }

    /// NATIVE masks the deadline, and the deadline masks the id lookup.
    function test_authorization_nativeThenDeadlineThenId() public {
        bytes32 unknown = keccak256("unknown");
        uint256 deadline = vm.getBlockTimestamp();
        bytes memory garbage = hex"1234";
        bytes memory call = abi.encodeCall(
            SpendGrantAuthorizationExecutor.spendWithAuthorization,
            (unknown, NATIVE, uint256(1), payee, uint256(1), deadline, garbage)
        );
        vm.prank(relayer);
        (bool ok, bytes memory ret) = address(executor).call(call);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(SpendGrantExecutor.NativeRequiresAccountAdapter.selector));

        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.AuthorizationExpired.selector);
        executor.spendWithAuthorization(unknown, address(token), 1, payee, 1, deadline, garbage);
    }

    /// The nonce pre-check runs before signature validation: the garbage signature that is BadAuthorization on a
    /// fresh nonce is NonceAlreadyUsed on a nonce that already ran.
    function test_authorization_usedNonceRevertsBeforeSignatureValidation() public {
        bytes32 id = _register(registry, _terms());
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _sign(DELEGATE_PK, _digest(id, address(token), 1, payee, 7, deadline));
        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 1, payee, 7, deadline, auth);

        bytes memory garbage = hex"1234";
        bytes memory fresh = abi.encodeCall(
            SpendGrantAuthorizationExecutor.spendWithAuthorization,
            (id, address(token), uint256(1), payee, uint256(8), deadline, garbage)
        );
        vm.prank(relayer);
        (bool ok, bytes memory ret) = address(executor).call(fresh);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(SpendGrantAuthorizationExecutor.BadAuthorization.selector));

        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.NonceAlreadyUsed.selector);
        executor.spendWithAuthorization(id, address(token), 1, payee, 7, deadline, garbage);
    }

    /// A valid signature by someone other than the delegate. The delegate has no code, so the Signatures rules
    /// return the recovered signer (the stranger) as the authorizer instead of failing; the executor passes it to
    /// consume, which rejects it at step 2 with UNAUTHORIZED_DELEGATE (13), not BadAuthorization. The stranger's
    /// nonce write is undone with the revert, and the delegate's nonce stays unused.
    function test_authorization_strangerSignatureIsUnauthorizedDelegate() public {
        bytes32 id = _register(registry, _terms());
        uint256 deadline = vm.getBlockTimestamp() + 600;
        address signer = vm.addr(STRANGER_PK);
        bytes memory auth = _sign(STRANGER_PK, _digest(id, address(token), 1, payee, 3, deadline));
        bytes memory call = abi.encodeCall(
            SpendGrantAuthorizationExecutor.spendWithAuthorization,
            (id, address(token), uint256(1), payee, uint256(3), deadline, auth)
        );
        // Both submissions below reach consume with the stranger as authorizer.
        vm.expectCall(
            address(registry), abi.encodeCall(ISpendGrantRegistry.consume, (id, signer, address(token), 1, payee)), 2
        );
        vm.prank(relayer);
        (bool ok, bytes memory ret) = address(executor).call(call);
        assertFalse(ok);
        assertEq(ret, _err(13));
        assertFalse(executor.nonceUsed(signer, 3));
        assertFalse(executor.nonceUsed(delegate, 3));

        vm.prank(relayer);
        vm.expectRevert(_err(13));
        executor.spendWithAuthorization(id, address(token), 1, payee, 3, deadline, auth);
    }

    /// cancelNonce is unchanged: the delegate burns an unused nonce, which then cannot run; a nonce that ran or was
    /// already cancelled cannot be cancelled.
    function test_authorization_cancelNonceUnchanged() public {
        bytes32 id = _register(registry, _terms());
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory ran = _sign(DELEGATE_PK, _digest(id, address(token), 1, payee, 7, deadline));
        bytes memory cancelled = _sign(DELEGATE_PK, _digest(id, address(token), 1, payee, 9, deadline));
        bytes memory nonceUsedError = abi.encodeWithSelector(SpendGrantAuthorizationExecutor.NonceAlreadyUsed.selector);

        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 1, payee, 7, deadline, ran);
        vm.prank(delegate);
        (bool ok, bytes memory ret) =
            address(executor).call(abi.encodeCall(SpendGrantAuthorizationExecutor.cancelNonce, (7)));
        assertFalse(ok);
        assertEq(ret, nonceUsedError);

        vm.expectEmit(true, true, false, true, address(executor));
        emit NonceCancelled(delegate, 9);
        vm.prank(delegate);
        executor.cancelNonce(9);
        assertTrue(executor.nonceUsed(delegate, 9));

        vm.prank(delegate);
        (ok, ret) = address(executor).call(abi.encodeCall(SpendGrantAuthorizationExecutor.cancelNonce, (9)));
        assertFalse(ok);
        assertEq(ret, nonceUsedError);

        vm.prank(relayer);
        vm.expectRevert(nonceUsedError);
        executor.spendWithAuthorization(id, address(token), 1, payee, 9, deadline, cancelled);
    }

    /// `registry()` names the registry the executor fixed at deployment, the only one it calls `consume` on.
    function test_authorization_registryGetterNamesItsRegistry() public view {
        assertEq(address(executor.registry()), address(registry));
    }

    function _domain() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("SpendAuthorization"),
                keccak256("1"),
                block.chainid,
                address(executor)
            )
        );
    }

    function _digest(bytes32 id, address asset, uint256 amount, address recipient, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, id, asset, amount, recipient, nonce, deadline));
        return keccak256(abi.encodePacked(hex"1901", _domain(), structHash));
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}

/// @notice The redemption executor and its enforcer, without a manager: the test calls the hooks as the manager
/// would, then calls `spend` as the principal's account, which is what performs an ERC-7710 execution.
contract SpendGrantRedemptionSmokeTest is SmokeBase {
    MinimalDelegationManager internal manager;
    SpendGrantRegistry internal registry;
    SpendGrantRedemptionEnforcer internal enforcer;
    SpendGrantRedemptionExecutor internal executor;

    function setUp() public {
        _actors();
        manager = new MinimalDelegationManager();
        uint64 nonce = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), nonce + 2);
        registry = new SpendGrantRegistry(predicted);
        enforcer = new SpendGrantRedemptionEnforcer(address(manager), predicted, address(registry));
        executor = new SpendGrantRedemptionExecutor(registry, enforcer);
        assertEq(address(executor), predicted);
        _fund(address(executor));
    }

    /// The hook records the redeemer for the principal's root delegation; the principal's account calls spend; the
    /// executor takes the record and passes the recorded redeemer (the delegate) to consume; the token moves.
    function test_redemption_recordedRedeemerSpends() public {
        bytes32 id = _register(registry, _terms());
        bytes memory execution = _execution(id, 40);
        assertEq(execution.length, 184);
        _before(_delegation(true, 1), execution, delegate);
        assertEq(enforcer.recorded(principal, id, address(token), 40, payee), delegate);
        // Keyed by the executing account: the record is not another account's.
        assertEq(enforcer.recorded(stranger, id, address(token), 40, payee), address(0));
        uint256 before = token.balanceOf(principal);

        vm.expectCall(
            address(registry), abi.encodeCall(ISpendGrantRegistry.consume, (id, delegate, address(token), 40, payee)), 1
        );
        vm.prank(principal);
        executor.spend(id, address(token), 40, payee);

        assertEq(before - token.balanceOf(principal), 40);
        assertEq(token.balanceOf(payee), 40);
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 40);
        assertEq(calls, 1);
        assertEq(enforcer.recorded(principal, id, address(token), 40, payee), address(0));
    }

    /// The hook reverts for a redeemer that is not the grant's delegate (WrongRedeemer) and records nothing, so the
    /// principal's spend finds no record and is rejected (13) before consume.
    function test_redemption_redeemerNotDelegateReverts() public {
        bytes32 id = _register(registry, _terms());
        bytes memory execution = _execution(id, 40);
        (bytes memory args, bytes32 h) = _hookInputs(_delegation(true, 1));
        vm.prank(address(manager));
        (bool ok, bytes memory ret) = address(enforcer).call(
            abi.encodeCall(enforcer.beforeHook, ("", args, bytes32(0), execution, h, principal, stranger))
        );
        assertFalse(ok, "the hook did not revert");
        assertEq(
            ret, abi.encodeWithSelector(bytes4(keccak256("WrongRedeemer()"))), "the hook reverted for another reason"
        );
        assertEq(enforcer.recorded(principal, id, address(token), 40, payee), address(0));

        vm.expectCall(address(registry), abi.encodeWithSelector(ISpendGrantRegistry.consume.selector), 0);
        vm.prank(principal);
        vm.expectRevert(_err(13));
        executor.spend(id, address(token), 40, payee);
    }

    /// An id the registry does not know has no principal: the hooks record nothing and do not revert, even for a
    /// zero delegator with no args (which a zero principal must not match), and the principal's spend is
    /// NONEXISTENT (14) before any record is consulted.
    function test_redemption_unknownIdRecordsNothing() public {
        bytes32 unknown = keccak256("unknown");
        bytes memory execution = _execution(unknown, 40);
        _before(_delegation(true, 1), execution, delegate);
        assertEq(enforcer.recorded(principal, unknown, address(token), 40, payee), address(0));

        vm.prank(address(manager));
        enforcer.beforeHook("", "", bytes32(0), execution, bytes32(0), address(0), delegate);
        assertEq(enforcer.recorded(address(0), unknown, address(token), 40, payee), address(0));
        vm.prank(address(manager));
        enforcer.afterHook("", "", bytes32(0), execution, bytes32(0), principal, delegate);

        vm.expectCall(address(enforcer), abi.encodeWithSelector(SpendGrantRedemptionEnforcer.take.selector), 0);
        vm.prank(principal);
        vm.expectRevert(_err(14));
        executor.spend(unknown, address(token), 40, payee);
    }

    /// The execution must hold target, value, selector and all four argument words: 184 bytes are accepted and 183
    /// are MalformedExecution (183 passed the previous 56-byte minimum).
    function test_redemption_shortExecutionIsMalformed() public {
        bytes32 id = _register(registry, _terms());
        bytes memory execution = _execution(id, 40);
        assertEq(execution.length, 184);
        IDelegationManagerLike.Delegation memory root = _delegation(true, 1);
        _before(root, execution, delegate);
        assertEq(enforcer.recorded(principal, id, address(token), 40, payee), delegate);

        bytes memory short = new bytes(183);
        for (uint256 i = 0; i < short.length; i++) {
            short[i] = execution[i];
        }
        (bytes memory args, bytes32 h) = _hookInputs(root);
        vm.prank(address(manager));
        vm.expectRevert(SpendGrantRedemptionEnforcer.MalformedExecution.selector);
        enforcer.beforeHook("", args, bytes32(0), short, h, principal, delegate);
    }

    /// The hook reverts for a delegation of the principal's that is not the root (NotRoot) and records nothing; the
    /// principal's spend then finds no record and is rejected (13) before consume.
    function test_redemption_nonRootPrincipalDelegationReverts() public {
        bytes32 id = _register(registry, _terms());
        bytes memory execution = _execution(id, 40);
        (bytes memory args, bytes32 h) = _hookInputs(_delegation(false, 1));
        vm.prank(address(manager));
        (bool ok, bytes memory ret) = address(enforcer).call(
            abi.encodeCall(enforcer.beforeHook, ("", args, bytes32(0), execution, h, principal, delegate))
        );
        assertFalse(ok, "the hook did not revert");
        assertEq(ret, abi.encodeWithSelector(bytes4(keccak256("NotRoot()"))), "the hook reverted for another reason");
        assertEq(enforcer.recorded(principal, id, address(token), 40, payee), address(0));

        vm.expectCall(address(registry), abi.encodeWithSelector(ISpendGrantRegistry.consume.selector), 0);
        vm.prank(principal);
        vm.expectRevert(_err(13));
        executor.spend(id, address(token), 40, payee);
    }

    /// A root that carries this caveat twice is rejected.
    function test_redemption_rootCarryingCaveatTwiceReverts() public {
        bytes32 id = _register(registry, _terms());
        bytes memory execution = _execution(id, 40);
        (bytes memory args, bytes32 h) = _hookInputs(_delegation(true, 2));
        vm.prank(address(manager));
        vm.expectRevert(SpendGrantRedemptionEnforcer.CaveatNotOnce.selector);
        enforcer.beforeHook("", args, bytes32(0), execution, h, principal, delegate);
    }

    /// afterHook clears a record the execution did not take; a later spend finds none (13).
    function test_redemption_afterHookClearsUntakenRecord() public {
        bytes32 id = _register(registry, _terms());
        bytes memory execution = _execution(id, 40);
        IDelegationManagerLike.Delegation memory root = _delegation(true, 1);
        _before(root, execution, delegate);
        assertEq(enforcer.recorded(principal, id, address(token), 40, payee), delegate);

        (bytes memory args, bytes32 h) = _hookInputs(root);
        vm.prank(address(manager));
        enforcer.afterHook("", args, bytes32(0), execution, h, principal, delegate);
        assertEq(enforcer.recorded(principal, id, address(token), 40, payee), address(0));

        vm.prank(principal);
        vm.expectRevert(_err(13));
        executor.spend(id, address(token), 40, payee);
    }

    /// The delegate may still call directly; no record is consulted.
    function test_redemption_delegateCallsDirectly() public {
        bytes32 id = _register(registry, _terms());
        vm.expectCall(address(enforcer), abi.encodeWithSelector(SpendGrantRedemptionEnforcer.take.selector), 0);
        vm.prank(delegate);
        executor.spend(id, address(token), 40, payee);
        assertEq(token.balanceOf(payee), 40);
    }

    /// A caller that is neither the delegate nor the principal is rejected (13) before any record is consulted.
    function test_redemption_strangerIsRejectedBeforeAnyRecord() public {
        bytes32 id = _register(registry, _terms());
        _before(_delegation(true, 1), _execution(id, 40), delegate);
        vm.expectCall(address(enforcer), abi.encodeWithSelector(SpendGrantRedemptionEnforcer.take.selector), 0);
        vm.prank(stranger);
        vm.expectRevert(_err(13));
        executor.spend(id, address(token), 40, payee);
    }

    /// The getters name the wiring fixed at deployment: the executor's registry and the enforcer it trusts by address,
    /// and the enforcer's trusted manager, the one executor that may take its records, and the registry it reads.
    function test_redemption_gettersNameTheWiring() public view {
        assertEq(address(executor.registry()), address(registry));
        assertEq(address(executor.enforcer()), address(enforcer));
        assertEq(enforcer.manager(), address(manager));
        assertEq(enforcer.executor(), address(executor));
        assertEq(enforcer.registry(), address(registry));
    }

    /// The enforcer is wired to a nonzero manager, executor and registry: a zero manager reverts ZeroAddress().
    function test_redemption_enforcerRejectsZeroManager() public {
        vm.expectRevert(SpendGrantRedemptionEnforcer.ZeroAddress.selector);
        new SpendGrantRedemptionEnforcer(address(0), address(executor), address(registry));
    }

    /// A zero executor reverts ZeroAddress(). The manager is the suite's stub, whose ROOT_AUTHORITY the constructor can
    /// read, so it is the zero check that refuses the deployment.
    function test_redemption_enforcerRejectsZeroExecutor() public {
        vm.expectRevert(SpendGrantRedemptionEnforcer.ZeroAddress.selector);
        new SpendGrantRedemptionEnforcer(address(manager), address(0), address(registry));
    }

    /// A zero registry reverts ZeroAddress(), with the same stub manager.
    function test_redemption_enforcerRejectsZeroRegistry() public {
        vm.expectRevert(SpendGrantRedemptionEnforcer.ZeroAddress.selector);
        new SpendGrantRedemptionEnforcer(address(manager), address(executor), address(0));
    }

    /// ERC-7579 single execution, no value, of `spend(bytes32,address,uint256,address)` on the executor.
    function _execution(bytes32 id, uint256 amount) internal view returns (bytes memory) {
        return abi.encodePacked(
            address(executor),
            uint256(0),
            abi.encodeWithSignature("spend(bytes32,address,uint256,address)", id, address(token), amount, payee)
        );
    }

    /// The principal's delegation to the delegate, carrying this enforcer `copies` times; the root when `root`.
    function _delegation(bool root, uint256 copies)
        internal
        view
        returns (IDelegationManagerLike.Delegation memory d)
    {
        d.delegate = delegate;
        d.delegator = principal;
        d.authority = root ? manager.ROOT_AUTHORITY() : keccak256("parent");
        d.caveats = new IDelegationManagerLike.Caveat[](copies);
        for (uint256 i = 0; i < copies; i++) {
            d.caveats[i] = IDelegationManagerLike.Caveat({enforcer: address(enforcer), terms: "", args: ""});
        }
    }

    /// The delegation itself as this caveat's args, and the manager's hash of it.
    function _hookInputs(IDelegationManagerLike.Delegation memory d)
        internal
        view
        returns (bytes memory args, bytes32 delegationHash)
    {
        args = abi.encode(d);
        delegationHash = manager.getDelegationHash(d);
    }

    /// Runs beforeHook as the manager does for `d`.
    function _before(IDelegationManagerLike.Delegation memory d, bytes memory execution, address redeemer) internal {
        (bytes memory args, bytes32 h) = _hookInputs(d);
        vm.prank(address(manager));
        enforcer.beforeHook("", args, bytes32(0), execution, h, d.delegator, redeemer);
    }
}
