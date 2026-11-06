// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {
    AssetLimit,
    FixedField,
    GrantExists,
    GrantIsRevoked,
    ISpendGrantRegistry,
    MAX_ASSETS,
    NATIVE,
    NotPrincipal,
    Reason,
    SpendGrant,
    SpendGrantError,
    StaleVersion,
    UnknownGrant
} from "../src/SpendGrantTypes.sol";
import {SpendGrantHash} from "../src/SpendGrantHash.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice register, update and revoke: their checks in order, their effects and events, what an update
/// does to spends that follow it, and the two per-party lists.
contract SpendGrantLifecycleTest is Test {
    uint64 internal constant WINDOW = 1 days;

    // Structural rules (register and update), then the registration rule.
    uint256 internal constant R_PRINCIPAL_ZERO = 0;
    uint256 internal constant R_DELEGATE_ZERO = 1;
    uint256 internal constant R_DELEGATE_IS_PRINCIPAL = 2;
    uint256 internal constant R_MODE_ABOVE_ONE = 3;
    uint256 internal constant R_ASSET_COMBINE = 4;
    uint256 internal constant R_FIXED_RECIPIENT_ZERO = 5;
    uint256 internal constant R_FIXED_RECIPIENT_PRINCIPAL = 6;
    uint256 internal constant R_OPEN_RECIPIENT_NONZERO = 7;
    uint256 internal constant R_WINDOW_ZERO = 8;
    uint256 internal constant R_VALIDITY_EMPTY = 9;
    uint256 internal constant R_VALIDITY_INVERTED = 10;
    uint256 internal constant R_NO_ASSETS = 11;
    uint256 internal constant R_TOO_MANY_ASSETS = 12;
    uint256 internal constant R_DUPLICATE_ASSET = 13;
    uint256 internal constant R_DESCENDING_ASSETS = 14;
    uint256 internal constant R_ZERO_PER_CALL = 15;
    uint256 internal constant R_ZERO_PER_WINDOW = 16;
    uint256 internal constant R_ZERO_TOTAL = 17;
    uint256 internal constant R_PER_CALL_ABOVE_WINDOW = 18;
    uint256 internal constant R_WINDOW_ABOVE_TOTAL = 19;
    uint256 internal constant R_ZERO_ASSET = 20;
    uint256 internal constant R_RECIPIENT_REGISTRY = 21;
    uint256 internal constant R_RECIPIENT_EXECUTOR = 22;
    uint256 internal constant R_RECIPIENT_LISTED_TOKEN = 23;
    uint256 internal constant R_RECIPIENT_LISTED_NATIVE = 24;
    // recipientMode 2 and 255 with the zero recipient that mode 1 requires, so that only the mode rule fails.
    uint256 internal constant R_MODE_TWO_ZERO_RECIPIENT = 25;
    uint256 internal constant R_MODE_255_ZERO_RECIPIENT = 26;

    SpendGrantRegistry internal registry;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    address internal executor;
    address internal principal;
    address internal delegate;
    address internal delegate2;
    address internal payee;
    address internal payee2;
    address internal stranger;

    function setUp() public {
        vm.warp(1_700_000_000);
        executor = makeAddr("executor");
        principal = makeAddr("principal");
        delegate = makeAddr("delegate");
        delegate2 = makeAddr("delegate2");
        payee = makeAddr("payee");
        payee2 = makeAddr("payee2");
        stranger = makeAddr("stranger");
        registry = new SpendGrantRegistry(executor);
        tokenA = new MockERC20();
        tokenB = new MockERC20();
    }

    // ---------------------------------------------------------------- register

    function test_register_storesTermsListsAndEmits() public {
        uint256 t = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        g.assets = _two(AssetLimit(address(tokenA), 100, 1000, 5000), AssetLimit(address(tokenB), 7, 70, 700));
        bytes32 expected = registry.hashGrant(g);

        vm.expectEmit(true, true, true, true, address(registry));
        emit ISpendGrantRegistry.GrantRegistered(expected, principal, delegate, g);
        vm.prank(principal);
        bytes32 id = registry.register(g);

        assertEq(id, expected);
        (SpendGrant memory stored, uint256 version, uint256 createdAt, uint256 updatedAt, bool isRevoked) =
            registry.getGrant(id);
        assertEq(abi.encode(stored), abi.encode(g));
        assertEq(version, 1);
        assertEq(createdAt, t);
        assertEq(updatedAt, t);
        assertFalse(isRevoked);
        assertFalse(registry.revoked(id));
        (address p, address d) = registry.parties(id);
        assertEq(p, principal);
        assertEq(d, delegate);
        assertEq(registry.executor(), executor);
        _assertList(true, principal, _one(id));
        _assertList(false, delegate, _one(id));
    }

    /// The id is the EIP-712 digest under this registry's domain. Chain ids are literals: via-IR may
    /// re-read CHAINID in place of a saved local.
    function test_register_idIsTheDomainSeparatedDigest() public {
        vm.chainId(31337);
        SpendGrant memory g = _base();
        bytes32 digest = SpendGrantHash.digest(31337, address(registry), g);
        assertEq(registry.hashGrant(g), digest);
        SpendGrantRegistry other = new SpendGrantRegistry(executor);
        assertEq(other.hashGrant(g), SpendGrantHash.digest(31337, address(other), g));
        assertTrue(other.hashGrant(g) != digest);
        vm.chainId(1);
        assertEq(registry.hashGrant(g), SpendGrantHash.digest(1, address(registry), g));
        assertTrue(registry.hashGrant(g) != digest);
        vm.chainId(31337);
        assertEq(_register(g), digest);
    }

    function test_hashGrant_validatesNothing() public view {
        SpendGrant memory g = _base();
        g.principal = address(0);
        g.recipientMode = 7;
        g.assets = new AssetLimit[](0);
        g.validUntil = 0;
        assertEq(registry.hashGrant(g), SpendGrantHash.digest(block.chainid, address(registry), g));
    }

    function test_register_revertsNotPrincipal() public {
        SpendGrant memory g = _base();
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(NotPrincipal.selector));
        registry.register(g);
    }

    function test_register_notPrincipalPrecedesStructure() public {
        SpendGrant memory g = _base();
        g.assets = new AssetLimit[](0);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotPrincipal.selector));
        registry.register(g);
    }

    function test_register_revertsGrantExists() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(GrantExists.selector, id));
        registry.register(g);
    }

    function test_register_revokedIdStaysOccupied() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        _revoke(id);
        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(GrantExists.selector, id));
        registry.register(g);
    }

    function test_register_newSaltIsANewGrant() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        _revoke(id);
        g.salt = 2;
        bytes32 id2 = _register(g);
        assertTrue(id2 != id);
        assertFalse(registry.revoked(id2));
        _assertReason(id2, address(tokenA), 1, payee, Reason.OK);
        _assertReason(id, address(tokenA), 1, payee, Reason.REVOKED);
    }

    function test_register_acceptsBoundaryTerms() public {
        SpendGrant memory g = _base();
        g.assets = _manyAssets(MAX_ASSETS);
        g.validUntil = g.validAfter + 1;
        _register(g);

        SpendGrant memory h = _base();
        h.recipientMode = 1;
        h.recipient = address(0);
        h.assets[0] = AssetLimit(address(tokenA), 9, 9, 9);
        _register(h);

        // A fixed recipient may be a token the grant does not list.
        SpendGrant memory k = _base();
        k.recipient = address(tokenB);
        bytes32 id = _register(k);
        _assertReason(id, address(tokenA), 1, address(tokenB), Reason.OK);
    }

    // ---------------------------------------------------------------- structure, on register and on update

    function test_structure_principalZero() public {
        _assertRule(R_PRINCIPAL_ZERO, abi.encodeWithSelector(FixedField.selector));
    }

    function test_structure_delegateZero() public {
        _assertRule(R_DELEGATE_ZERO, abi.encodeWithSelector(FixedField.selector));
    }

    function test_structure_delegateIsPrincipal() public {
        _assertRule(R_DELEGATE_IS_PRINCIPAL, abi.encodeWithSelector(FixedField.selector));
    }

    function test_structure_recipientModeAboveOne() public {
        _assertRule(R_MODE_ABOVE_ONE, _err(Reason.INVALID_GRANT));
    }

    /// An unknown recipientMode fails closed by itself: mode 2 with the zero recipient of an open recipient, which
    /// every recipient rule accepts, is INVALID_GRANT on register and on update.
    function test_structure_recipientModeTwoWithZeroRecipient() public {
        _assertRule(R_MODE_TWO_ZERO_RECIPIENT, _err(Reason.INVALID_GRANT));
    }

    /// The same for mode 255, the largest value.
    function test_structure_recipientMode255WithZeroRecipient() public {
        _assertRule(R_MODE_255_ZERO_RECIPIENT, _err(Reason.INVALID_GRANT));
    }

    function test_structure_assetCombineNonzero() public {
        _assertRule(R_ASSET_COMBINE, _err(Reason.INVALID_GRANT));
    }

    function test_structure_fixedRecipientZero() public {
        _assertRule(R_FIXED_RECIPIENT_ZERO, _err(Reason.INVALID_GRANT));
    }

    function test_structure_fixedRecipientIsPrincipal() public {
        _assertRule(R_FIXED_RECIPIENT_PRINCIPAL, _err(Reason.INVALID_GRANT));
    }

    function test_structure_openRecipientNonzero() public {
        _assertRule(R_OPEN_RECIPIENT_NONZERO, _err(Reason.INVALID_GRANT));
    }

    function test_structure_windowZero() public {
        _assertRule(R_WINDOW_ZERO, abi.encodeWithSelector(FixedField.selector));
    }

    function test_structure_validityEmpty() public {
        _assertRule(R_VALIDITY_EMPTY, _err(Reason.INVALID_GRANT));
    }

    function test_structure_validityInverted() public {
        _assertRule(R_VALIDITY_INVERTED, _err(Reason.INVALID_GRANT));
    }

    function test_structure_noAssets() public {
        _assertRule(R_NO_ASSETS, _err(Reason.INVALID_GRANT));
    }

    function test_structure_tooManyAssets() public {
        _assertRule(R_TOO_MANY_ASSETS, _err(Reason.INVALID_GRANT));
    }

    function test_structure_duplicateAsset() public {
        _assertRule(R_DUPLICATE_ASSET, _err(Reason.INVALID_GRANT));
    }

    function test_structure_descendingAssets() public {
        _assertRule(R_DESCENDING_ASSETS, _err(Reason.INVALID_GRANT));
    }

    function test_structure_zeroMaxPerCall() public {
        _assertRule(R_ZERO_PER_CALL, _err(Reason.INVALID_GRANT));
    }

    function test_structure_zeroMaxPerWindow() public {
        _assertRule(R_ZERO_PER_WINDOW, _err(Reason.INVALID_GRANT));
    }

    function test_structure_zeroMaxTotal() public {
        _assertRule(R_ZERO_TOTAL, _err(Reason.INVALID_GRANT));
    }

    function test_structure_perCallAboveWindow() public {
        _assertRule(R_PER_CALL_ABOVE_WINDOW, _err(Reason.INVALID_GRANT));
    }

    function test_structure_windowAboveTotal() public {
        _assertRule(R_WINDOW_ABOVE_TOTAL, _err(Reason.INVALID_GRANT));
    }

    function test_structure_zeroAsset() public {
        _assertRule(R_ZERO_ASSET, _err(Reason.INVALID_GRANT));
    }

    function test_registrationRule_recipientIsRegistry() public {
        _assertRule(R_RECIPIENT_REGISTRY, _err(Reason.INVALID_GRANT));
    }

    function test_registrationRule_recipientIsExecutor() public {
        _assertRule(R_RECIPIENT_EXECUTOR, _err(Reason.INVALID_GRANT));
    }

    function test_registrationRule_recipientIsListedToken() public {
        _assertRule(R_RECIPIENT_LISTED_TOKEN, _err(Reason.INVALID_GRANT));
    }

    function test_registrationRule_recipientIsListedNative() public {
        _assertRule(R_RECIPIENT_LISTED_NATIVE, _err(Reason.INVALID_GRANT));
    }

    // ---------------------------------------------------------------- update: checks in order

    function test_update_revertsUnknownGrant() public {
        bytes32 unknown = keccak256("unknown");
        SpendGrant memory g = _base();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(UnknownGrant.selector, unknown));
        registry.update(unknown, 1, g);
    }

    function test_update_revertsNotPrincipal() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(NotPrincipal.selector));
        registry.update(id, 1, g);
    }

    function test_update_notPrincipalPrecedesRevoked() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        _revoke(id);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotPrincipal.selector));
        registry.update(id, 7, g);
    }

    function test_update_revertsGrantIsRevoked() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        _revoke(id);
        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(GrantIsRevoked.selector, id));
        registry.update(id, 1, g);
    }

    function test_update_revokedPrecedesStaleVersion() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        _revoke(id);
        g.delegate = stranger;
        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(GrantIsRevoked.selector, id));
        registry.update(id, 9, g);
    }

    /// An update built from an older version cannot undo a newer one.
    function test_update_revertsStaleVersion() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        SpendGrant memory lowered = _base();
        lowered.assets[0] = AssetLimit(address(tokenA), 10, 100, 500);
        _update(id, 1, lowered);

        SpendGrant memory raised = _base();
        raised.assets[0] = AssetLimit(address(tokenA), 1000, 10_000, 50_000);
        (bool ok, bytes memory ret) = _tryUpdate(id, 0, raised);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(StaleVersion.selector, 2));
        (ok, ret) = _tryUpdate(id, 3, raised);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(StaleVersion.selector, 2));
        (SpendGrant memory stored,,,,) = registry.getGrant(id);
        assertEq(stored.assets[0].maxTotal, 500);

        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(StaleVersion.selector, 2));
        registry.update(id, 1, raised);
    }

    function test_update_staleVersionPrecedesFixedField() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        g.delegate = stranger;
        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(StaleVersion.selector, 1));
        registry.update(id, 2, g);
    }

    function test_update_revertsFixedField_principal() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        g.principal = stranger;
        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(FixedField.selector));
        registry.update(id, 1, g);
    }

    function test_update_revertsFixedField_delegate() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        g.delegate = delegate2;
        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(FixedField.selector));
        registry.update(id, 1, g);
    }

    function test_update_revertsFixedField_windowSeconds() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        g.windowSeconds = WINDOW + 1;
        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(FixedField.selector));
        registry.update(id, 1, g);
    }

    function test_update_fixedFieldPrecedesStructure() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        g.delegate = delegate2;
        g.assets = new AssetLimit[](0);
        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(FixedField.selector));
        registry.update(id, 1, g);
    }

    // ---------------------------------------------------------------- update: effects

    function test_update_replacesTermsBumpsVersionAndEmits() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        vm.warp(t0 + 100);

        SpendGrant memory n = _base();
        n.recipientMode = 1;
        n.recipient = address(0);
        n.validAfter = uint64(t0 - 10);
        n.validUntil = uint64(t0 + 60 days);
        n.assets = _two(AssetLimit(address(tokenA), 50, 500, 2500), AssetLimit(NATIVE, 1, 2, 3));
        n.salt = 777;
        SpendGrant memory expected = _copy(n);
        expected.salt = g.salt;

        vm.expectEmit(true, true, true, true, address(registry));
        emit ISpendGrantRegistry.GrantUpdated(id, principal, delegate, 2, expected);
        vm.prank(principal);
        registry.update(id, 1, n);

        (SpendGrant memory stored, uint256 version, uint256 createdAt, uint256 updatedAt, bool isRevoked) =
            registry.getGrant(id);
        assertEq(abi.encode(stored), abi.encode(expected));
        assertEq(version, 2);
        assertEq(createdAt, t0);
        assertEq(updatedAt, t0 + 100);
        assertFalse(isRevoked);
        (address p, address d) = registry.parties(id);
        assertEq(p, principal);
        assertEq(d, delegate);
    }

    function test_update_versionAndTimestampsAcrossUpdates() public {
        uint256 t0 = vm.getBlockTimestamp();
        bytes32 id = _register(_base());
        for (uint256 i = 1; i <= 3; i++) {
            vm.warp(t0 + 1000 * i);
            SpendGrant memory n = _base();
            n.validAfter = uint64(t0);
            n.assets[0].maxTotal = 5000 + i;
            _update(id, i, n);
            (, uint256 version, uint256 createdAt, uint256 updatedAt,) = registry.getGrant(id);
            assertEq(version, i + 1);
            assertEq(createdAt, t0);
            assertEq(updatedAt, t0 + 1000 * i);
        }
    }

    /// The stored registration salt is kept, the id never changes, and the id is not the hash of the current terms.
    function test_update_ignoresSalt() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        SpendGrant memory saltOnly = _base();
        saltOnly.salt = 999;
        _update(id, 1, saltOnly);
        (SpendGrant memory stored, uint256 version,,,) = registry.getGrant(id);
        assertEq(abi.encode(stored), abi.encode(g));
        assertEq(version, 2);
        assertEq(registry.hashGrant(stored), id);

        SpendGrant memory changed = _base();
        changed.assets[0].maxTotal = 4000;
        changed.salt = 5;
        _update(id, 2, changed);
        (stored,,,,) = registry.getGrant(id);
        assertEq(stored.salt, g.salt);
        assertTrue(registry.hashGrant(stored) != id);
        (address p,) = registry.parties(id);
        assertEq(p, principal);

        // The original terms' id stays occupied after the update.
        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(GrantExists.selector, id));
        registry.register(g);
    }

    function test_update_leavesUsageUntouched() public {
        uint256 t0 = vm.getBlockTimestamp();
        bytes32 id = _register(_base());
        _spend(id, address(tokenA), 30, payee);
        vm.warp(t0 + 10);
        _spend(id, address(tokenA), 20, payee);
        (uint256 spent, uint256 calls) = registry.usage(id, address(tokenA));
        (uint256 wSpent, uint256 wCalls) = registry.rollingUsage(id, address(tokenA));
        (uint256[] memory exp, uint256[] memory amt) = registry.liveDebits(id, address(tokenA), 10);

        SpendGrant memory n = _base();
        n.validAfter = uint64(t0);
        n.recipient = payee2;
        n.assets = _two(AssetLimit(address(tokenA), 60, 600, 6000), AssetLimit(address(tokenB), 1, 1, 1));
        _update(id, 1, n);

        (uint256 spent2, uint256 calls2) = registry.usage(id, address(tokenA));
        (uint256 wSpent2, uint256 wCalls2) = registry.rollingUsage(id, address(tokenA));
        (uint256[] memory exp2, uint256[] memory amt2) = registry.liveDebits(id, address(tokenA), 10);
        assertEq(spent2, spent);
        assertEq(calls2, calls);
        assertEq(spent2, 50);
        assertEq(calls2, 2);
        assertEq(wSpent2, wSpent);
        assertEq(wCalls2, wCalls);
        assertEq(abi.encode(exp2), abi.encode(exp));
        assertEq(abi.encode(amt2), abi.encode(amt));
        assertEq(exp2.length, 2);
    }

    function test_update_shrinkingListLeavesNoStaleEntries() public {
        SpendGrant memory g = _base();
        g.assets = _sorted3(
            AssetLimit(address(tokenA), 100, 1000, 5000),
            AssetLimit(address(tokenB), 20, 200, 2000),
            AssetLimit(NATIVE, 30, 300, 3000)
        );
        bytes32 id = _register(g);

        SpendGrant memory shrunk = _base();
        shrunk.assets[0] = AssetLimit(address(tokenA), 11, 111, 1111);
        _update(id, 1, shrunk);
        (SpendGrant memory stored,,,,) = registry.getGrant(id);
        assertEq(abi.encode(stored.assets), abi.encode(shrunk.assets));
        _assertReason(id, address(tokenB), 1, payee, Reason.WRONG_ASSET);
        _assertReason(id, NATIVE, 1, payee, Reason.WRONG_ASSET);

        // Growing again lists only the new entries, with the new caps.
        SpendGrant memory regrown = _base();
        regrown.assets = _two(AssetLimit(address(tokenA), 11, 111, 1111), AssetLimit(address(tokenB), 5, 50, 500));
        _update(id, 2, regrown);
        (stored,,,,) = registry.getGrant(id);
        assertEq(abi.encode(stored.assets), abi.encode(regrown.assets));
        _assertReason(id, address(tokenB), 5, payee, Reason.OK);
        _assertReason(id, address(tokenB), 6, payee, Reason.OVER_TX_CAP);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.WRONG_ASSET));
        registry.consume(id, delegate, NATIVE, 1, payee);
    }

    function test_update_doesNotRelist() public {
        bytes32 id = _register(_base());
        SpendGrant memory n = _base();
        n.assets[0].maxTotal = 4000;
        _update(id, 1, n);
        _assertList(true, principal, _one(id));
        _assertList(false, delegate, _one(id));
    }

    // ---------------------------------------------------------------- update: consequences for later spends

    function test_update_lowerMaxTotalToSpentExhausts() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        g.assets[0] = AssetLimit(address(tokenA), 1000, 1000, 1000);
        bytes32 id = _register(g);
        _spend(id, address(tokenA), 700, payee);
        vm.warp(t0 + WINDOW);
        _setCaps(id, g, 1, 700, 700, 700);
        _assertReason(id, address(tokenA), 1, payee, Reason.OVER_CUMULATIVE_CAP);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.OVER_CUMULATIVE_CAP));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    function test_update_lowerMaxTotalBelowSpentExhausts() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        g.assets[0] = AssetLimit(address(tokenA), 1000, 1000, 1000);
        bytes32 id = _register(g);
        _spend(id, address(tokenA), 700, payee);
        vm.warp(t0 + WINDOW);
        _setCaps(id, g, 1, 600, 600, 600);
        _assertReason(id, address(tokenA), 1, payee, Reason.OVER_CUMULATIVE_CAP);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.OVER_CUMULATIVE_CAP));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    function test_update_raiseMaxTotalCountsAllUsage() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        g.assets[0] = AssetLimit(address(tokenA), 1000, 1000, 1000);
        bytes32 id = _register(g);
        _spend(id, address(tokenA), 1000, payee);
        vm.warp(t0 + WINDOW);
        _assertReason(id, address(tokenA), 1, payee, Reason.OVER_CUMULATIVE_CAP);
        _setCaps(id, g, 1, 1000, 1000, 1500);
        _assertReason(id, address(tokenA), 500, payee, Reason.OK);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.OVER_CUMULATIVE_CAP));
        registry.consume(id, delegate, address(tokenA), 501, payee);
    }

    function test_update_lowerMaxPerWindowBlocksUntilExpiry() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        _spend(id, address(tokenA), 100, payee);
        vm.warp(t0 + 100);
        _spend(id, address(tokenA), 100, payee);
        _setCaps(id, g, 1, 100, 200, 5000);
        _assertReason(id, address(tokenA), 1, payee, Reason.OVER_WINDOW_CAP);
        _setCaps(id, g, 2, 100, 150, 5000);
        _assertReason(id, address(tokenA), 1, payee, Reason.OVER_WINDOW_CAP);
        vm.warp(t0 + WINDOW - 1);
        _assertReason(id, address(tokenA), 1, payee, Reason.OVER_WINDOW_CAP);
        vm.warp(t0 + WINDOW);
        _assertReason(id, address(tokenA), 50, payee, Reason.OK);
        _assertReason(id, address(tokenA), 51, payee, Reason.OVER_WINDOW_CAP);
        _spend(id, address(tokenA), 50, payee);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.OVER_WINDOW_CAP));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    function test_update_removedAssetRejectsAndReaddedResumesUsage() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        g.assets = _two(AssetLimit(address(tokenA), 100, 1000, 5000), AssetLimit(address(tokenB), 200, 1000, 1000));
        bytes32 id = _register(g);
        _spend(id, address(tokenB), 100, payee);
        vm.warp(t0 + 1);
        _spend(id, address(tokenB), 100, payee);

        _update(id, 1, _base());
        _assertReason(id, address(tokenB), 1, payee, Reason.WRONG_ASSET);
        (uint256 spent, uint256 calls) = registry.usage(id, address(tokenB));
        assertEq(spent, 200);
        assertEq(calls, 2);
        (uint256 wSpent, uint256 wCalls) = registry.rollingUsage(id, address(tokenB));
        assertEq(wSpent, 200);
        assertEq(wCalls, 2);

        // Re-added within the window: the window's spend still counts.
        SpendGrant memory back = _base();
        back.assets = _two(AssetLimit(address(tokenA), 100, 1000, 5000), AssetLimit(address(tokenB), 200, 250, 1000));
        _update(id, 2, back);
        _assertReason(id, address(tokenB), 50, payee, Reason.OK);
        _assertReason(id, address(tokenB), 51, payee, Reason.OVER_WINDOW_CAP);

        // After the window: the lifetime spend still counts.
        vm.warp(t0 + 1 + WINDOW);
        back.assets = _two(AssetLimit(address(tokenA), 100, 1000, 5000), AssetLimit(address(tokenB), 200, 300, 300));
        _update(id, 3, back);
        _assertReason(id, address(tokenB), 100, payee, Reason.OK);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.OVER_CUMULATIVE_CAP));
        registry.consume(id, delegate, address(tokenB), 101, payee);
    }

    function test_update_extendValidUntilRevives() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        g.validUntil = uint64(t0 + 100);
        bytes32 id = _register(g);
        vm.warp(t0 + 100);
        _assertReason(id, address(tokenA), 1, payee, Reason.EXPIRED);
        g.validUntil = uint64(t0 + 1000);
        _update(id, 1, g);
        _assertReason(id, address(tokenA), 1, payee, Reason.OK);
        vm.warp(t0 + 1000);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.EXPIRED));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    function test_update_validAfterForwardPausesAndBackResumes() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        g.validAfter = uint64(t0 + 500);
        _update(id, 1, g);
        _assertReason(id, address(tokenA), 1, payee, Reason.NOT_YET_VALID);
        g.validAfter = uint64(t0);
        _update(id, 2, g);
        _assertReason(id, address(tokenA), 1, payee, Reason.OK);
        g.validAfter = uint64(t0 + 1);
        _update(id, 3, g);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.NOT_YET_VALID));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    function test_update_validUntilAtNowExpires() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        g.validAfter = uint64(t0 - 10);
        g.validUntil = uint64(t0);
        _update(id, 1, g);
        _assertReason(id, address(tokenA), 1, payee, Reason.EXPIRED);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.EXPIRED));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    function test_update_validUntilBeforeNowExpires() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        g.validAfter = uint64(t0 - 10);
        g.validUntil = uint64(t0 - 1);
        _update(id, 1, g);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.EXPIRED));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    function test_update_recipientChangeAppliesToNextSpend() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        _spend(id, address(tokenA), 1, payee);
        g.recipient = payee2;
        _update(id, 1, g);
        _assertReason(id, address(tokenA), 1, payee2, Reason.OK);
        _assertReason(id, address(tokenA), 1, payee, Reason.WRONG_RECIPIENT);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.WRONG_RECIPIENT));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    function test_update_recipientModeChangeAppliesToNextSpend() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        _assertReason(id, address(tokenA), 1, stranger, Reason.WRONG_RECIPIENT);
        g.recipientMode = 1;
        g.recipient = address(0);
        _update(id, 1, g);
        _assertReason(id, address(tokenA), 1, stranger, Reason.OK);
        _assertReason(id, address(tokenA), 1, payee, Reason.OK);
        g.recipientMode = 0;
        g.recipient = stranger;
        _update(id, 2, g);
        _assertReason(id, address(tokenA), 1, stranger, Reason.OK);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.WRONG_RECIPIENT));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    /// Regression: an update does not restart the rolling window.
    function test_update_windowDoesNotRestart() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        g.assets[0] = AssetLimit(address(tokenA), 200, 200, 5000);
        bytes32 id = _register(g);
        _spend(id, address(tokenA), 100, payee);
        vm.warp(t0 + 100);
        _spend(id, address(tokenA), 100, payee);
        vm.warp(t0 + 200);
        g.validUntil = uint64(t0 + 90 days);
        g.recipient = payee2;
        _update(id, 1, g);
        _assertReason(id, address(tokenA), 1, payee2, Reason.OVER_WINDOW_CAP);
        (uint256 wSpent, uint256 wCalls) = registry.rollingUsage(id, address(tokenA));
        assertEq(wSpent, 200);
        assertEq(wCalls, 2);
        vm.warp(t0 + WINDOW - 1);
        _assertReason(id, address(tokenA), 1, payee2, Reason.OVER_WINDOW_CAP);
        vm.warp(t0 + WINDOW);
        _assertReason(id, address(tokenA), 100, payee2, Reason.OK);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.OVER_WINDOW_CAP));
        registry.consume(id, delegate, address(tokenA), 101, payee2);
    }

    /// Regression (ted0x's case): maxTotal 1000, 700 spent, update to 800: at most 100 more, with no sizing
    /// arithmetic by the principal.
    function test_update_lifetimeTotalHoldsAcrossLoweringUpdate() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        g.assets[0] = AssetLimit(address(tokenA), 1000, 1000, 1000);
        bytes32 id = _register(g);
        _spend(id, address(tokenA), 700, payee);
        vm.warp(t0 + WINDOW);
        _setCaps(id, g, 1, 800, 800, 800);
        _assertReason(id, address(tokenA), 101, payee, Reason.OVER_CUMULATIVE_CAP);
        _spend(id, address(tokenA), 100, payee);
        (uint256 spent,) = registry.usage(id, address(tokenA));
        assertEq(spent, 800);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.OVER_CUMULATIVE_CAP));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    // ---------------------------------------------------------------- revoke

    function test_revoke_revertsUnknownGrant() public {
        bytes32 unknown = keccak256("unknown");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(UnknownGrant.selector, unknown));
        registry.revoke(unknown);
    }

    function test_revoke_revertsNotPrincipal() public {
        bytes32 id = _register(_base());
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(NotPrincipal.selector));
        registry.revoke(id);
    }

    function test_revoke_notPrincipalEvenWhenRevoked() public {
        bytes32 id = _register(_base());
        _revoke(id);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotPrincipal.selector));
        registry.revoke(id);
    }

    function test_revoke_setsFlagAndEmits() public {
        uint256 t0 = vm.getBlockTimestamp();
        bytes32 id = _register(_base());
        vm.warp(t0 + 50);
        vm.expectEmit(true, true, true, true, address(registry));
        emit ISpendGrantRegistry.GrantRevoked(id, principal, delegate);
        vm.prank(principal);
        registry.revoke(id);

        assertTrue(registry.revoked(id));
        (, uint256 version, uint256 createdAt, uint256 updatedAt, bool isRevoked) = registry.getGrant(id);
        assertTrue(isRevoked);
        assertEq(version, 1);
        assertEq(createdAt, t0);
        assertEq(updatedAt, t0);
        _assertReason(id, address(tokenA), 1, payee, Reason.REVOKED);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.REVOKED));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    function test_revoke_againIsASilentNoOp() public {
        bytes32 id = _register(_base());
        _revoke(id);
        vm.recordLogs();
        vm.prank(principal);
        registry.revoke(id);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
        assertTrue(registry.revoked(id));
    }

    function test_views_unknownIdIsZero() public {
        bytes32 unknown = keccak256("unknown");
        (SpendGrant memory t, uint256 version, uint256 createdAt, uint256 updatedAt, bool isRevoked) =
            registry.getGrant(unknown);
        SpendGrant memory empty;
        assertEq(abi.encode(t), abi.encode(empty));
        assertEq(version, 0);
        assertEq(createdAt, 0);
        assertEq(updatedAt, 0);
        assertFalse(isRevoked);
        assertFalse(registry.revoked(unknown));
        (address p, address d) = registry.parties(unknown);
        assertEq(p, address(0));
        assertEq(d, address(0));
        (uint256 spent, uint256 calls) = registry.usage(unknown, address(tokenA));
        assertEq(spent + calls, 0);
        (spent, calls) = registry.rollingUsage(unknown, address(tokenA));
        assertEq(spent + calls, 0);
        (uint256[] memory exp, uint256[] memory amt) = registry.liveDebits(unknown, address(tokenA), 10);
        assertEq(exp.length + amt.length, 0);
        registry.evict(unknown, address(tokenA), 10);
    }

    // ---------------------------------------------------------------- lists

    function test_lists_recordRegistrationsInOrder() public {
        SpendGrant memory g = _base();
        bytes32 a = _register(g);
        g.delegate = delegate2;
        bytes32 b = _register(g);
        g.delegate = delegate;
        g.salt = 2;
        bytes32 c = _register(g);
        _assertList(true, principal, _three(a, b, c));
        _assertList(false, delegate, _pair(a, c));
        _assertList(false, delegate2, _one(b));
        _assertList(true, delegate, new bytes32[](0));
    }

    function test_lists_revokedStaysListed() public {
        bytes32 a = _register(_base());
        _revoke(a);
        _assertList(true, principal, _one(a));
        _assertList(false, delegate, _one(a));
        (,,,, bool isRevoked) = registry.getGrant(a);
        assertTrue(isRevoked);
    }

    /// Anyone can add an entry to a delegate's list by registering their own grant that names it; the entry
    /// is theirs (its principal is them) and gives them nothing over other grants.
    function test_lists_anyoneCanAddToADelegatesList() public {
        bytes32 mine = _register(_base());
        SpendGrant memory spam = _base();
        spam.principal = stranger;
        bytes32 theirs = _register(spam);
        _assertList(false, delegate, _pair(mine, theirs));
        _assertList(true, principal, _one(mine));
        _assertList(true, stranger, _one(theirs));
        (address p,) = registry.parties(theirs);
        assertEq(p, stranger);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NotPrincipal.selector));
        registry.revoke(mine);
    }

    function test_page_emptyList() public view {
        bytes32[] memory none = new bytes32[](0);
        _assertPage(stranger, none, 0, 10, 0, 0);
        _assertPage(stranger, none, 0, type(uint256).max, 0, 0);
        _assertPage(stranger, none, type(uint256).max, type(uint256).max, 0, 0);
    }

    function test_page_offsetAtOrPastTotal() public {
        bytes32[] memory ids = _five();
        _assertPage(principal, ids, 5, 10, 0, 0);
        _assertPage(principal, ids, 6, 1, 0, 0);
        _assertPage(principal, ids, type(uint256).max, type(uint256).max, 0, 0);
    }

    function test_page_limitZero() public {
        bytes32[] memory ids = _five();
        _assertPage(principal, ids, 0, 0, 0, 0);
        _assertPage(principal, ids, 2, 0, 0, 0);
    }

    function test_page_maxLimitWithOffset() public {
        bytes32[] memory ids = _five();
        _assertPage(principal, ids, 1, type(uint256).max, 1, 5);
        _assertPage(principal, ids, 4, type(uint256).max, 4, 5);
        _assertPage(principal, ids, 0, type(uint256).max, 0, 5);
        _assertPage(principal, ids, 3, type(uint256).max - 2, 3, 5);
    }

    function test_page_windows() public {
        bytes32[] memory ids = _five();
        _assertPage(principal, ids, 1, 2, 1, 3);
        _assertPage(principal, ids, 3, 5, 3, 5);
        _assertPage(principal, ids, 0, 5, 0, 5);
        _assertPage(principal, ids, 4, 1, 4, 5);
    }

    function testFuzz_page_matchesModel(uint256 offset, uint256 limit) public {
        bytes32[] memory ids = _five();
        uint256 begin = offset;
        uint256 end;
        if (offset >= 5 || limit == 0) {
            begin = 0;
            end = 0;
        } else {
            end = limit > 5 - offset ? 5 : offset + limit;
        }
        _assertPage(principal, ids, offset, limit, begin, end);
    }

    // ---------------------------------------------------------------- lifecycle error encoding

    function test_encoding_lifecycleErrors() public {
        assertEq(NotPrincipal.selector, bytes4(keccak256("NotPrincipal()")));
        assertEq(GrantExists.selector, bytes4(keccak256("GrantExists(bytes32)")));
        assertEq(UnknownGrant.selector, bytes4(keccak256("UnknownGrant(bytes32)")));
        assertEq(GrantIsRevoked.selector, bytes4(keccak256("GrantIsRevoked(bytes32)")));
        assertEq(StaleVersion.selector, bytes4(keccak256("StaleVersion(uint256)")));
        assertEq(FixedField.selector, bytes4(keccak256("FixedField()")));

        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        vm.prank(principal);
        (bool ok, bytes memory ret) = address(registry).call(abi.encodeCall(ISpendGrantRegistry.register, (g)));
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(bytes4(keccak256("GrantExists(bytes32)")), id));
        (ok, ret) = _tryUpdate(id, 4, g);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(bytes4(keccak256("StaleVersion(uint256)")), uint256(1)));
        (ok, ret) = _tryUpdate(keccak256("x"), 1, g);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(bytes4(keccak256("UnknownGrant(bytes32)")), keccak256("x")));
        SpendGrant memory empty = _base();
        empty.assets = new AssetLimit[](0);
        vm.prank(principal);
        (ok, ret) = address(registry).call(abi.encodeCall(ISpendGrantRegistry.register, (empty)));
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(bytes4(keccak256("SpendGrantError(uint8)")), uint8(1)));
        _revoke(id);

        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("GrantIsRevoked(bytes32)")), id));
        registry.update(id, 1, g);
    }

    // ---------------------------------------------------------------- helpers

    function _base() internal view returns (SpendGrant memory g) {
        uint64 t = uint64(vm.getBlockTimestamp());
        g.principal = principal;
        g.delegate = delegate;
        g.recipientMode = 0;
        g.recipient = payee;
        g.windowSeconds = WINDOW;
        g.assets = new AssetLimit[](1);
        g.assets[0] = AssetLimit(address(tokenA), 100, 1000, 5000);
        g.validAfter = t;
        g.validUntil = t + 30 days;
        g.salt = 1;
    }

    function _mutate(SpendGrant memory g, uint256 rule) internal view returns (SpendGrant memory) {
        if (rule == R_PRINCIPAL_ZERO) {
            g.principal = address(0);
        } else if (rule == R_DELEGATE_ZERO) {
            g.delegate = address(0);
        } else if (rule == R_DELEGATE_IS_PRINCIPAL) {
            g.delegate = g.principal;
        } else if (rule == R_MODE_ABOVE_ONE) {
            g.recipientMode = 2;
        } else if (rule == R_MODE_TWO_ZERO_RECIPIENT) {
            g.recipientMode = 2;
            g.recipient = address(0);
        } else if (rule == R_MODE_255_ZERO_RECIPIENT) {
            g.recipientMode = 255;
            g.recipient = address(0);
        } else if (rule == R_ASSET_COMBINE) {
            g.assetCombine = 1;
        } else if (rule == R_FIXED_RECIPIENT_ZERO) {
            g.recipient = address(0);
        } else if (rule == R_FIXED_RECIPIENT_PRINCIPAL) {
            g.recipient = g.principal;
        } else if (rule == R_OPEN_RECIPIENT_NONZERO) {
            g.recipientMode = 1;
        } else if (rule == R_WINDOW_ZERO) {
            g.windowSeconds = 0;
        } else if (rule == R_VALIDITY_EMPTY) {
            g.validUntil = g.validAfter;
        } else if (rule == R_VALIDITY_INVERTED) {
            g.validUntil = g.validAfter - 1;
        } else if (rule == R_NO_ASSETS) {
            g.assets = new AssetLimit[](0);
        } else if (rule == R_TOO_MANY_ASSETS) {
            g.assets = _manyAssets(MAX_ASSETS + 1);
        } else if (rule == R_DUPLICATE_ASSET) {
            g.assets = _pairOf(g.assets[0], g.assets[0]);
        } else if (rule == R_DESCENDING_ASSETS) {
            g.assets = _descending();
        } else if (rule == R_ZERO_PER_CALL) {
            g.assets[0].maxPerCall = 0;
        } else if (rule == R_ZERO_PER_WINDOW) {
            g.assets[0].maxPerWindow = 0;
        } else if (rule == R_ZERO_TOTAL) {
            g.assets[0].maxTotal = 0;
        } else if (rule == R_PER_CALL_ABOVE_WINDOW) {
            g.assets[0].maxPerCall = g.assets[0].maxPerWindow + 1;
        } else if (rule == R_WINDOW_ABOVE_TOTAL) {
            g.assets[0].maxPerWindow = g.assets[0].maxTotal + 1;
        } else if (rule == R_ZERO_ASSET) {
            g.assets[0].asset = address(0);
        } else if (rule == R_RECIPIENT_REGISTRY) {
            g.recipient = address(registry);
        } else if (rule == R_RECIPIENT_EXECUTOR) {
            g.recipient = executor;
        } else if (rule == R_RECIPIENT_LISTED_TOKEN) {
            g.recipient = address(tokenA);
        } else if (rule == R_RECIPIENT_LISTED_NATIVE) {
            g.assets = _two(AssetLimit(address(tokenA), 100, 1000, 5000), AssetLimit(NATIVE, 1, 1, 1));
            g.recipient = NATIVE;
        }
        return g;
    }

    /// `register` rejects the rule's terms with INVALID_GRANT; `update` of a registered grant to them ends
    /// on `updateError` (FixedField where the rule changes principal, delegate or window).
    function _assertRule(uint256 rule, bytes memory updateError) internal {
        SpendGrant memory bad = _mutate(_base(), rule);
        vm.prank(bad.principal);
        (bool ok, bytes memory ret) = address(registry).call(abi.encodeCall(ISpendGrantRegistry.register, (bad)));
        assertFalse(ok, "register accepted");
        assertEq(ret, _err(Reason.INVALID_GRANT));

        bytes32 id = _register(_base());
        SpendGrant memory badUpdate = _mutate(_base(), rule);
        vm.prank(principal);
        vm.expectRevert(updateError);
        registry.update(id, 1, badUpdate);
    }

    function _setCaps(
        bytes32 id,
        SpendGrant memory g,
        uint256 version,
        uint256 perCall,
        uint256 perWindow,
        uint256 total
    ) internal {
        g.assets[0] = AssetLimit(g.assets[0].asset, perCall, perWindow, total);
        _update(id, version, g);
    }

    function _register(SpendGrant memory g) internal returns (bytes32 id) {
        vm.prank(g.principal);
        id = registry.register(g);
    }

    function _update(bytes32 id, uint256 version, SpendGrant memory g) internal {
        vm.prank(g.principal);
        registry.update(id, version, g);
    }

    function _tryUpdate(bytes32 id, uint256 version, SpendGrant memory g)
        internal
        returns (bool ok, bytes memory ret)
    {
        vm.prank(g.principal);
        (ok, ret) = address(registry).call(abi.encodeCall(ISpendGrantRegistry.update, (id, version, g)));
    }

    function _revoke(bytes32 id) internal {
        (address p,) = registry.parties(id);
        vm.prank(p);
        registry.revoke(id);
    }

    function _spend(bytes32 id, address asset, uint256 amount, address to) internal {
        vm.prank(executor);
        registry.consume(id, delegate, asset, amount, to);
    }

    function _assertReason(bytes32 id, address asset, uint256 amount, address to, Reason expected) internal view {
        (bool ok, Reason r) = registry.check(id, delegate, asset, amount, to);
        assertEq(uint8(r), uint8(expected));
        assertEq(ok, expected == Reason.OK);
    }

    function _err(Reason r) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SpendGrantError.selector, r);
    }

    function _five() internal returns (bytes32[] memory list) {
        SpendGrant memory g = _base();
        list = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            g.salt = 100 + i;
            list[i] = _register(g);
        }
    }

    /// `grantsOf` (and `grantsTo` for the shared delegate) at (offset, limit) is `ids[begin:end]` with total
    /// `ids.length`, where `ids` are the ids `register` returned (`_five`), not what the registry lists.
    function _assertPage(address who, bytes32[] memory ids, uint256 offset, uint256 limit, uint256 begin, uint256 end)
        internal
        view
    {
        (bytes32[] memory page, uint256 n) = registry.grantsOf(who, offset, limit);
        assertEq(n, ids.length, "total");
        assertEq(page.length, end - begin, "length");
        for (uint256 i = 0; i < page.length; i++) {
            assertEq(page[i], ids[begin + i], "entry");
        }
        if (who == principal) {
            (bytes32[] memory toPage, uint256 toTotal) = registry.grantsTo(delegate, offset, limit);
            assertEq(toTotal, ids.length, "grantsTo total");
            assertEq(abi.encode(toPage), abi.encode(page), "grantsTo page");
        }
    }

    function _assertList(bool ofPrincipal, address who, bytes32[] memory expected) internal view {
        (bytes32[] memory list, uint256 total) =
            ofPrincipal ? registry.grantsOf(who, 0, type(uint256).max) : registry.grantsTo(who, 0, type(uint256).max);
        assertEq(total, expected.length);
        assertEq(abi.encode(list), abi.encode(expected));
    }

    function _copy(SpendGrant memory g) internal pure returns (SpendGrant memory) {
        return abi.decode(abi.encode(g), (SpendGrant));
    }

    function _manyAssets(uint256 n) internal pure returns (AssetLimit[] memory list) {
        list = new AssetLimit[](n);
        for (uint256 i = 0; i < n; i++) {
            list[i] = AssetLimit(address(uint160(0x1000 + i)), 1, 1, 1);
        }
    }

    function _descending() internal view returns (AssetLimit[] memory list) {
        list = _two(AssetLimit(address(tokenA), 1, 1, 1), AssetLimit(address(tokenB), 1, 1, 1));
        (list[0], list[1]) = (list[1], list[0]);
    }

    function _pairOf(AssetLimit memory a, AssetLimit memory b) internal pure returns (AssetLimit[] memory list) {
        list = new AssetLimit[](2);
        list[0] = a;
        list[1] = b;
    }

    function _two(AssetLimit memory a, AssetLimit memory b) internal pure returns (AssetLimit[] memory list) {
        list = new AssetLimit[](2);
        (list[0], list[1]) = a.asset < b.asset ? (a, b) : (b, a);
    }

    function _sorted3(AssetLimit memory a, AssetLimit memory b, AssetLimit memory c)
        internal
        pure
        returns (AssetLimit[] memory list)
    {
        list = new AssetLimit[](3);
        list[0] = a;
        list[1] = b;
        list[2] = c;
        for (uint256 i = 1; i < 3; i++) {
            for (uint256 j = i; j > 0 && list[j - 1].asset > list[j].asset; j--) {
                (list[j - 1], list[j]) = (list[j], list[j - 1]);
            }
        }
    }

    function _one(bytes32 a) internal pure returns (bytes32[] memory list) {
        list = new bytes32[](1);
        list[0] = a;
    }

    function _pair(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory list) {
        list = new bytes32[](2);
        list[0] = a;
        list[1] = b;
    }

    function _three(bytes32 a, bytes32 b, bytes32 c) internal pure returns (bytes32[] memory list) {
        list = new bytes32[](3);
        list[0] = a;
        list[1] = b;
        list[2] = c;
    }
}
