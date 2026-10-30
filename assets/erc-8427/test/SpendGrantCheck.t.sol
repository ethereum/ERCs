// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {
    AssetLimit,
    ISpendGrantRegistry,
    MAX_LIVE_DEBITS,
    NATIVE,
    REASON_BAD_SIGNATURE,
    REASON_NONEXISTENT,
    Reason,
    SpendGrant,
    SpendGrantError
} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice `consume` and `check` share one evaluator: the order of its steps, the revert encoding, and the
/// property that `check` returns OK exactly when `consume` succeeds and otherwise the reason `consume`
/// reverts with (P-EQ).
contract SpendGrantCheckTest is Test {
    bytes4 internal constant SPEND_GRANT_ERROR = bytes4(keccak256("SpendGrantError(uint8)"));
    uint64 internal constant WINDOW = 1 days;
    uint256 internal constant DIFFERENTIAL_CASES = 2400;

    SpendGrantRegistry internal registry;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;

    address internal executor;
    address internal principal;
    address internal delegate;
    address internal payee;
    address internal stranger;
    address internal noCode;
    address internal designator;

    // Differential state.
    address[3] internal principals;
    address[2] internal delegates;
    address[2] internal payees;
    address[] internal pool;
    bytes32[] internal ids;
    bytes32 internal fullId;
    bytes32 internal invalidId;
    uint256[15] internal hits;

    function setUp() public {
        vm.warp(1_700_000_000);
        executor = makeAddr("executor");
        principal = makeAddr("principal");
        delegate = makeAddr("delegate");
        payee = makeAddr("payee");
        stranger = makeAddr("stranger");
        noCode = makeAddr("noCode");
        designator = makeAddr("designator");
        vm.etch(designator, abi.encodePacked(hex"ef0100", address(0xC0DE1E55)));

        registry = new SpendGrantRegistry(executor);
        tokenA = new MockERC20();
        tokenB = new MockERC20();
        tokenC = new MockERC20();

        principals = [principal, makeAddr("principal1"), makeAddr("principal2")];
        delegates = [delegate, makeAddr("delegate1")];
        payees = [payee, makeAddr("payee1")];
        address[5] memory p = [address(tokenA), address(tokenB), NATIVE, noCode, designator];
        for (uint256 i = 0; i < p.length; i++) {
            pool.push(p[i]);
        }
        // Sorted ascending, so any in-order subset is a valid asset list.
        for (uint256 i = 1; i < pool.length; i++) {
            for (uint256 j = i; j > 0 && pool[j - 1] > pool[j]; j--) {
                (pool[j - 1], pool[j]) = (pool[j], pool[j - 1]);
            }
        }
    }

    // ---------------------------------------------------------------- order: one test per step

    /// The executor check precedes every evaluation step.
    function test_order_executorCheckMasksEverything() public {
        bytes32 unknown = keccak256("unknown");
        _assertReason(unknown, stranger, noCode, 0, address(0), Reason.NONEXISTENT);
        (bool ok, bytes memory ret) = _tryConsume(unknown, stranger, noCode, 0, address(0));
        assertFalse(ok);
        assertEq(ret, _err(Reason.NONEXISTENT));

        vm.prank(stranger);
        vm.expectRevert(_err(Reason.UNAUTHORIZED_EXECUTOR));
        registry.consume(unknown, stranger, noCode, 0, address(0));
    }

    function test_consume_onlyTheExecutor() public {
        bytes32 id = _register(_base());
        _assertReason(id, delegate, address(tokenA), 1, payee, Reason.OK);
        vm.prank(delegate);
        (bool ok, bytes memory ret) = address(registry).call(
            abi.encodeCall(ISpendGrantRegistry.consume, (id, delegate, address(tokenA), 1, payee))
        );
        assertFalse(ok);
        assertEq(ret, _err(Reason.UNAUTHORIZED_EXECUTOR));

        vm.prank(principal);
        vm.expectRevert(_err(Reason.UNAUTHORIZED_EXECUTOR));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    /// Step 1 (NONEXISTENT) masks step 2, including the zero authorizer that equals an unknown id's zero delegate.
    function test_order_nonexistentMasksDelegate() public {
        bytes32 id = _register(_base());
        bytes32 unknown = keccak256("unknown");
        _assertReason(unknown, stranger, noCode, 0, address(0), Reason.NONEXISTENT);
        _assertReason(unknown, address(0), noCode, 0, address(0), Reason.NONEXISTENT);
        _assertReason(id, stranger, noCode, 0, address(0), Reason.UNAUTHORIZED_DELEGATE);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.NONEXISTENT));
        registry.consume(unknown, address(0), noCode, 0, address(0));
    }

    /// Step 2 (UNAUTHORIZED_DELEGATE) masks steps 3 and later; the principal is not the delegate.
    function test_order_delegateMasksNotYetValid() public {
        uint64 t = uint64(vm.getBlockTimestamp());
        SpendGrant memory g = _base();
        g.validAfter = t + 100;
        g.validUntil = t + 1000;
        bytes32 id = _register(g);
        _revoke(id);

        _assertReason(id, stranger, noCode, 0, address(0), Reason.UNAUTHORIZED_DELEGATE);
        _assertReason(id, principal, noCode, 0, address(0), Reason.UNAUTHORIZED_DELEGATE);
        _assertReason(id, delegate, noCode, 0, address(0), Reason.NOT_YET_VALID);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.UNAUTHORIZED_DELEGATE));
        registry.consume(id, principal, noCode, 0, address(0));
    }

    /// Step 3 (NOT_YET_VALID) masks step 5 and later. Step 4 cannot fail with it, since validAfter < validUntil.
    function test_order_notYetValidMasksRevoked() public {
        uint64 t = uint64(vm.getBlockTimestamp());
        SpendGrant memory g = _base();
        g.validAfter = t + 100;
        g.validUntil = t + 1000;
        bytes32 id = _register(g);
        _revoke(id);
        SpendGrant memory twin = _base();
        twin.salt = 2;
        bytes32 twinId = _register(twin);
        _revoke(twinId);

        _assertReason(id, delegate, noCode, 0, address(0), Reason.NOT_YET_VALID);
        _assertReason(twinId, delegate, noCode, 0, address(0), Reason.REVOKED);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.NOT_YET_VALID));
        registry.consume(id, delegate, noCode, 0, address(0));
    }

    /// Step 4 (EXPIRED) masks step 5 and later.
    function test_order_expiredMasksRevoked() public {
        uint64 t = uint64(vm.getBlockTimestamp());
        SpendGrant memory g = _base();
        g.validUntil = t + 10;
        bytes32 id = _register(g);
        _revoke(id);
        SpendGrant memory twin = _base();
        twin.salt = 2;
        bytes32 twinId = _register(twin);
        _revoke(twinId);
        vm.warp(t + 10);

        _assertReason(id, delegate, noCode, 0, address(0), Reason.EXPIRED);
        _assertReason(twinId, delegate, noCode, 0, address(0), Reason.REVOKED);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.EXPIRED));
        registry.consume(id, delegate, noCode, 0, address(0));
    }

    /// Step 5 (REVOKED) masks step 6 and later.
    function test_order_revokedMasksRecipient() public {
        bytes32 id = _register(_base());
        _revoke(id);
        SpendGrant memory twin = _base();
        twin.salt = 2;
        bytes32 twinId = _register(twin);

        _assertReason(id, delegate, noCode, 0, address(0), Reason.REVOKED);
        _assertReason(twinId, delegate, noCode, 0, address(0), Reason.WRONG_RECIPIENT);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.REVOKED));
        registry.consume(id, delegate, noCode, 0, address(0));
    }

    /// Step 6 (WRONG_RECIPIENT) masks step 7 and later: paying the (unlisted) asset itself.
    function test_order_recipientMasksAsset() public {
        bytes32 id = _register(_base());
        _assertReason(id, delegate, noCode, 0, noCode, Reason.WRONG_RECIPIENT);
        _assertReason(id, delegate, noCode, 0, payee, Reason.WRONG_ASSET);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.WRONG_RECIPIENT));
        registry.consume(id, delegate, noCode, 0, noCode);
    }

    /// Step 7 (WRONG_ASSET) masks step 8 and later; listing the asset exposes step 8.
    function test_order_assetMasksCodeCheck() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        _assertReason(id, delegate, noCode, 0, payee, Reason.WRONG_ASSET);

        SpendGrant memory listed = _base();
        listed.assets = _two(AssetLimit(address(tokenA), 100, 1000, 5000), AssetLimit(noCode, 100, 1000, 5000));
        _update(id, 1, listed);
        _assertReason(id, delegate, noCode, 0, payee, Reason.INVALID_GRANT);

        _update(id, 2, _base());
        vm.prank(executor);
        vm.expectRevert(_err(Reason.WRONG_ASSET));
        registry.consume(id, delegate, noCode, 0, payee);
    }

    /// Step 8 (INVALID_GRANT: no code, or an EIP-7702 designator) masks step 9 and later.
    function test_order_codeCheckMasksTxCap() public {
        SpendGrant memory g = _base();
        g.assets = _sorted3(
            AssetLimit(address(tokenA), 100, 1000, 5000),
            AssetLimit(noCode, 100, 1000, 5000),
            AssetLimit(designator, 100, 1000, 5000)
        );
        bytes32 id = _register(g);
        _assertReason(id, delegate, noCode, 0, payee, Reason.INVALID_GRANT);
        _assertReason(id, delegate, designator, 0, payee, Reason.INVALID_GRANT);

        vm.etch(noCode, address(tokenB).code);
        _assertReason(id, delegate, noCode, 0, payee, Reason.OVER_TX_CAP);
        // 23 bytes that are not a designator are ordinary code.
        bytes memory designatorCode = designator.code;
        vm.etch(designator, new bytes(23));
        _assertReason(id, delegate, designator, 0, payee, Reason.OVER_TX_CAP);
        vm.etch(designator, designatorCode);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.INVALID_GRANT));
        registry.consume(id, delegate, designator, 0, payee);
    }

    /// Step 9 (OVER_TX_CAP) masks steps 10-12 when all three fail.
    function test_order_txCapMasksWindowTotalAndFull() public {
        (bytes32 id, SpendGrant memory g) = _fullRingFixture();
        _setCaps(id, g, 1, 10, 1024, 2024);
        _assertReason(id, delegate, address(tokenA), 0, payee, Reason.OVER_TX_CAP);
        _assertReason(id, delegate, address(tokenA), 11, payee, Reason.OVER_TX_CAP);
        _assertReason(id, delegate, address(tokenA), 1, payee, Reason.OVER_WINDOW_CAP);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.OVER_TX_CAP));
        registry.consume(id, delegate, address(tokenA), 11, payee);
    }

    /// Step 10 (OVER_WINDOW_CAP) masks steps 11 and 12.
    function test_order_windowMasksTotalAndFull() public {
        (bytes32 id, SpendGrant memory g) = _fullRingFixture();
        _setCaps(id, g, 1, 10, 2000, 2024);
        _assertReason(id, delegate, address(tokenA), 1, payee, Reason.OVER_CUMULATIVE_CAP);
        _setCaps(id, g, 2, 10, 1024, 2024);
        _assertReason(id, delegate, address(tokenA), 1, payee, Reason.OVER_WINDOW_CAP);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.OVER_WINDOW_CAP));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    /// Step 11 (OVER_CUMULATIVE_CAP) masks step 12.
    function test_order_totalMasksWindowFull() public {
        (bytes32 id, SpendGrant memory g) = _fullRingFixture();
        _setCaps(id, g, 1, 10, 2000, 3000);
        _assertReason(id, delegate, address(tokenA), 1, payee, Reason.WINDOW_FULL);
        _setCaps(id, g, 2, 10, 2000, 2024);
        _assertReason(id, delegate, address(tokenA), 1, payee, Reason.OVER_CUMULATIVE_CAP);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.OVER_CUMULATIVE_CAP));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    /// Step 12 (WINDOW_FULL) is reported only when steps 1-11 pass, and clears when the live debits expire.
    function test_order_windowFullIsLast() public {
        (bytes32 id,) = _fullRingFixture();
        uint256 filledAt = vm.getBlockTimestamp();
        _assertReason(id, delegate, address(tokenA), 1, payee, Reason.WINDOW_FULL);
        vm.warp(filledAt + WINDOW);
        _assertReason(id, delegate, address(tokenA), 1, payee, Reason.OK);
        vm.warp(filledAt + WINDOW - 1);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.WINDOW_FULL));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    // ---------------------------------------------------------------- step details

    function test_recipient_excludedInEveryMode() public {
        bytes32 fixedId = _register(_base());
        SpendGrant memory open = _base();
        open.recipientMode = 1;
        open.recipient = address(0);
        bytes32 openId = _register(open);

        address[5] memory excluded = [address(0), principal, address(registry), executor, address(tokenA)];
        for (uint256 i = 0; i < excluded.length; i++) {
            _assertReason(fixedId, delegate, address(tokenA), 1, excluded[i], Reason.WRONG_RECIPIENT);
            _assertReason(openId, delegate, address(tokenA), 1, excluded[i], Reason.WRONG_RECIPIENT);
        }
        _assertReason(fixedId, delegate, address(tokenA), 1, stranger, Reason.WRONG_RECIPIENT);
        _assertReason(fixedId, delegate, address(tokenA), 1, payee, Reason.OK);
        _assertReason(openId, delegate, address(tokenA), 1, stranger, Reason.OK);
        _assertReason(openId, delegate, address(tokenA), 1, delegate, Reason.OK);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.WRONG_RECIPIENT));
        registry.consume(openId, delegate, address(tokenA), 1, address(tokenA));
    }

    /// NATIVE skips the code check; 23 bytes of code that are not a designator are ordinary code.
    function test_codeCheck_nativeAndOrdinaryCodePass() public {
        SpendGrant memory g = _base();
        g.assets = _two(AssetLimit(address(tokenA), 100, 1000, 5000), AssetLimit(NATIVE, 100, 1000, 5000));
        bytes32 id = _register(g);
        _assertReason(id, delegate, NATIVE, 1, payee, Reason.OK);
        _assertReason(id, delegate, address(tokenA), 1, payee, Reason.OK);
        vm.etch(address(tokenA), new bytes(23));
        _assertReason(id, delegate, address(tokenA), 1, payee, Reason.OK);
        vm.etch(address(tokenA), abi.encodePacked(hex"ef0100", address(0xC0DE1E55)));

        vm.prank(executor);
        vm.expectRevert(_err(Reason.INVALID_GRANT));
        registry.consume(id, delegate, address(tokenA), 1, payee);
    }

    function test_txCap_amountBounds() public {
        SpendGrant memory g = _base();
        uint256 max = type(uint256).max;
        g.assets[0] = AssetLimit(address(tokenA), max, max, max);
        bytes32 id = _register(g);
        uint256 bound = type(uint192).max;
        _assertReason(id, delegate, address(tokenA), 0, payee, Reason.OVER_TX_CAP);
        _assertReason(id, delegate, address(tokenA), bound, payee, Reason.OK);
        _assertReason(id, delegate, address(tokenA), bound + 1, payee, Reason.OVER_TX_CAP);
        _assertReason(id, delegate, address(tokenA), max, payee, Reason.OVER_TX_CAP);

        vm.prank(executor);
        vm.expectRevert(_err(Reason.OVER_TX_CAP));
        registry.consume(id, delegate, address(tokenA), bound + 1, payee);
    }

    function test_consume_recordsDebitAndEmits() public {
        bytes32 id = _register(_base());
        vm.expectEmit(true, true, true, true, address(registry));
        emit ISpendGrantRegistry.GrantConsumed(id, principal, address(tokenA), 40, payee);
        vm.prank(executor);
        registry.consume(id, delegate, address(tokenA), 40, payee);

        (uint256 spent, uint256 calls) = registry.usage(id, address(tokenA));
        assertEq(spent, 40);
        assertEq(calls, 1);
        (spent, calls) = registry.rollingUsage(id, address(tokenA));
        assertEq(spent, 40);
        assertEq(calls, 1);
        (uint256[] memory expiresAt, uint256[] memory amounts) = registry.liveDebits(id, address(tokenA), 10);
        assertEq(expiresAt.length, 1);
        assertEq(expiresAt[0], vm.getBlockTimestamp() + WINDOW);
        assertEq(amounts[0], 40);
    }

    // ---------------------------------------------------------------- encoding

    function test_encoding_enumNumbersAndNames() public pure {
        assertEq(SPEND_GRANT_ERROR, bytes4(0xed54f3ee));
        assertEq(SpendGrantError.selector, bytes4(0xed54f3ee));
        assertEq(uint8(Reason.OK), 0);
        assertEq(uint8(Reason.INVALID_GRANT), 1);
        assertEq(uint8(Reason.BAD_SIGNATURE), 2);
        assertEq(uint8(Reason.NOT_YET_VALID), 3);
        assertEq(uint8(Reason.EXPIRED), 4);
        assertEq(uint8(Reason.REVOKED), 5);
        assertEq(uint8(Reason.WRONG_ASSET), 6);
        assertEq(uint8(Reason.WRONG_RECIPIENT), 7);
        assertEq(uint8(Reason.OVER_TX_CAP), 8);
        assertEq(uint8(Reason.OVER_WINDOW_CAP), 9);
        assertEq(uint8(Reason.OVER_CUMULATIVE_CAP), 10);
        assertEq(uint8(Reason.WINDOW_FULL), 11);
        assertEq(uint8(Reason.UNAUTHORIZED_EXECUTOR), 12);
        assertEq(uint8(Reason.UNAUTHORIZED_DELEGATE), 13);
        assertEq(uint8(Reason.NONEXISTENT), 14);
        assertEq(uint8(type(Reason).max), 14);
        assertEq(REASON_BAD_SIGNATURE, bytes32("BAD_SIGNATURE"));
        assertEq(REASON_NONEXISTENT, bytes32("NONEXISTENT"));
    }

    /// Every reason `consume` can revert with, against the literal selector and number.
    function test_encoding_consumeRevertData() public {
        uint64 t = uint64(vm.getBlockTimestamp());
        SpendGrant memory g = _base();
        g.assets = _two(AssetLimit(address(tokenA), 100, 1000, 5000), AssetLimit(noCode, 100, 1000, 5000));
        bytes32 id = _register(g);

        SpendGrant memory later = _base();
        later.validAfter = t + 100;
        later.validUntil = t + 200;
        bytes32 laterId = _register(later);
        SpendGrant memory brief = _base();
        brief.validUntil = t + 1;
        bytes32 briefId = _register(brief);
        SpendGrant memory gone = _base();
        gone.salt = 9;
        bytes32 goneId = _register(gone);
        _revoke(goneId);
        SpendGrant memory small = _base();
        small.assets[0] = AssetLimit(address(tokenA), 100, 100, 150);
        small.windowSeconds = 10;
        bytes32 smallId = _register(small);
        SpendGrant memory roomy = _base();
        roomy.assets[0] = AssetLimit(address(tokenA), 10, 1e6, 1e6);
        bytes32 roomyId = _register(roomy);
        vm.warp(t + 1);

        (bool ok, Reason r) = registry.check(id, delegate, address(tokenA), 1, payee);
        assertTrue(ok);
        assertEq(uint8(r), 0);

        _assertConsumeData(keccak256("unknown"), delegate, address(tokenA), 1, payee, uint8(14));
        _assertConsumeData(id, stranger, address(tokenA), 1, payee, uint8(13));
        _assertConsumeData(laterId, delegate, address(tokenA), 1, payee, uint8(3));
        _assertConsumeData(briefId, delegate, address(tokenA), 1, payee, uint8(4));
        _assertConsumeData(goneId, delegate, address(tokenA), 1, payee, uint8(5));
        _assertConsumeData(id, delegate, address(tokenB), 1, payee, uint8(6));
        _assertConsumeData(id, delegate, address(tokenA), 1, stranger, uint8(7));
        _assertConsumeData(id, delegate, noCode, 1, payee, uint8(1));
        _assertConsumeData(id, delegate, address(tokenA), 101, payee, uint8(8));
        _spend(smallId, address(tokenA), 100);
        _assertConsumeData(smallId, delegate, address(tokenA), 1, payee, uint8(9));
        vm.warp(t + 11);
        _spend(smallId, address(tokenA), 50);
        _assertConsumeData(smallId, delegate, address(tokenA), 1, payee, uint8(10));

        vm.prank(stranger);
        (bool success, bytes memory ret) = address(registry).call(
            abi.encodeCall(ISpendGrantRegistry.consume, (id, delegate, address(tokenA), 1, payee))
        );
        assertFalse(success);
        assertEq(ret, abi.encodeWithSelector(bytes4(keccak256("SpendGrantError(uint8)")), uint8(12)));
        assertEq(ret.length, 36);

        _fill(roomyId, address(tokenA), MAX_LIVE_DEBITS, 1);
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("SpendGrantError(uint8)")), uint8(11)));
        registry.consume(roomyId, delegate, address(tokenA), 1, payee);
    }

    // ---------------------------------------------------------------- P-EQ

    /// Deterministic model-free differential: >= 2000 pseudo-random cases, each comparing `check` (from an
    /// arbitrary caller) with `consume` called by the executor, plus non-executor `consume` attempts.
    function test_differential_checkMatchesConsume() public {
        _fixtures(true);
        bytes32 seed = keccak256("ERC-8427 v3 check/consume differential");
        for (uint256 i = 0; i < DIFFERENTIAL_CASES; i++) {
            seed = keccak256(abi.encode(seed, i));
            this.runCase(uint256(seed));
        }
        for (uint256 i = 0; i < hits.length; i++) {
            console2.log(_reasonName(i), hits[i]);
        }
        assertEq(hits[uint8(Reason.BAD_SIGNATURE)], 0, "BAD_SIGNATURE is reserved");
        for (uint256 i = 0; i < hits.length; i++) {
            if (i == uint8(Reason.BAD_SIGNATURE)) continue;
            assertGe(hits[i], 1, _reasonName(i));
        }
    }

    function testFuzz_checkMatchesConsume(uint256 seed) public {
        _fixtures(false);
        for (uint256 i = 0; i < 16; i++) {
            this.runCase(uint256(keccak256(abi.encode(seed, i))));
        }
    }

    function testFuzz_checkIgnoresCaller(address caller, uint256 amount, uint8 assetPick) public {
        bytes32 id = _register(_base());
        _spend(id, address(tokenA), 60);
        address asset = assetPick % 3 == 0 ? address(tokenA) : assetPick % 3 == 1 ? address(tokenB) : noCode;
        (bool ok, Reason r) = registry.check(id, delegate, asset, amount, payee);
        vm.prank(caller);
        (bool ok2, Reason r2) = registry.check(id, delegate, asset, amount, payee);
        assertEq(ok, ok2);
        assertEq(uint8(r), uint8(r2));
    }

    /// One differential case: maybe change state, then compare `check` with `consume` on a drawn input.
    /// External so that each case runs in a fresh memory frame.
    function runCase(uint256 r) external {
        require(msg.sender == address(this), "self only");
        _mutateState(r);
        uint256 s = uint256(keccak256(abi.encode(r, "input")));
        bytes32 id = _pickId(s);
        (address p, address d) = registry.parties(id);
        SpendGrant memory t;
        if (p != address(0)) (t,,,,) = registry.getGrant(id);
        address asset = _pickAsset(s >> 8, t);
        address authorizer = _pickAuthorizer(s >> 24, p, d);
        address to = _pickRecipient(s >> 40, t, asset);
        uint256 amount = _pickAmount(s >> 56, id, t, asset);
        if ((s >> 248) % 6 == 0) _strangerConsume(s >> 120, id, authorizer, asset, amount, to);
        _compare(id, authorizer, asset, amount, to, s >> 136);
    }

    function _compare(bytes32 id, address authorizer, address asset, uint256 amount, address to, uint256 s) internal {
        address caller = _anyCaller(s);
        vm.prank(caller);
        (bool ok, Reason reason) = registry.check(id, authorizer, asset, amount, to);
        (bool ok2, Reason reason2) = registry.check(id, authorizer, asset, amount, to);
        assertEq(ok, ok2, "check depends on its caller");
        assertEq(uint8(reason), uint8(reason2), "check depends on its caller");
        assertEq(ok, reason == Reason.OK, "ok flag");
        assertTrue(reason != Reason.BAD_SIGNATURE && reason != Reason.UNAUTHORIZED_EXECUTOR, "check reason");

        (uint256 spentBefore, uint256 callsBefore) = registry.usage(id, asset);
        vm.prank(executor);
        (bool success, bytes memory ret) =
            address(registry).call(abi.encodeCall(ISpendGrantRegistry.consume, (id, authorizer, asset, amount, to)));
        if (ok) {
            assertTrue(success, "check OK but consume reverted");
            (uint256 spentAfter, uint256 callsAfter) = registry.usage(id, asset);
            assertEq(spentAfter, spentBefore + amount, "spent");
            assertEq(callsAfter, callsBefore + 1, "calls");
        } else {
            assertFalse(success, "check failed but consume succeeded");
            assertEq(ret, abi.encodeWithSelector(SPEND_GRANT_ERROR, uint8(reason)), "revert data");
        }
        hits[uint8(reason)]++;
    }

    function _strangerConsume(uint256 s, bytes32 id, address authorizer, address asset, uint256 amount, address to)
        internal
    {
        address[4] memory callers = [principal, delegate, stranger, payee];
        vm.prank(callers[s % 4]);
        (bool success, bytes memory ret) =
            address(registry).call(abi.encodeCall(ISpendGrantRegistry.consume, (id, authorizer, asset, amount, to)));
        assertFalse(success, "non-executor consume succeeded");
        assertEq(ret, abi.encodeWithSelector(SPEND_GRANT_ERROR, uint8(12)), "non-executor revert data");
        hits[uint8(Reason.UNAUTHORIZED_EXECUTOR)]++;
    }

    function _fixtures(bool full) internal {
        // INVALID_GRANT fixture: lists a no-code asset and an EIP-7702 designator; any recipient; never expires.
        SpendGrant memory inv = _base();
        inv.recipientMode = 1;
        inv.recipient = address(0);
        inv.validUntil = type(uint64).max;
        inv.salt = 0x1A;
        inv.assets = _sorted3(
            AssetLimit(address(tokenA), 100, 1000, 1e9),
            AssetLimit(noCode, 100, 1000, 1e9),
            AssetLimit(designator, 100, 1000, 1e9)
        );
        invalidId = _register(inv);
        ids.push(invalidId);
        for (uint256 i = 0; i < 3; i++) {
            ids.push(_registerRandom(uint256(keccak256(abi.encode("seed grant", i)))));
        }
        if (!full) return;
        // WINDOW_FULL fixture: 1024 live debits in a window longer than the whole run.
        SpendGrant memory f = _base();
        f.recipientMode = 1;
        f.recipient = address(0);
        f.windowSeconds = uint64(1) << 40;
        f.validUntil = type(uint64).max;
        f.salt = 0xF0;
        f.assets[0] = AssetLimit(address(tokenA), 10, 1e30, 1e30);
        fullId = _register(f);
        _fill(fullId, address(tokenA), MAX_LIVE_DEBITS, 1);
        ids.push(fullId);
    }

    function _mutateState(uint256 r) internal {
        uint256 op = r % 100;
        if (op < 6) {
            ids.push(_registerRandom(r >> 8));
        } else if (op < 13) {
            bytes32 id = ids[(r >> 8) % ids.length];
            (SpendGrant memory t, uint256 version,,, bool isRevoked) = registry.getGrant(id);
            if (id != fullId && id != invalidId && !isRevoked) {
                SpendGrant memory n = _randomTerms(r >> 24, t.principal, t.delegate, t.windowSeconds);
                vm.prank(t.principal);
                registry.update(id, version, n);
            }
        } else if (op < 15) {
            bytes32 id = ids[(r >> 8) % ids.length];
            if (id != fullId && id != invalidId) {
                (address p,) = registry.parties(id);
                vm.prank(p);
                registry.revoke(id);
            }
        } else if (op < 35) {
            // A well-formed spend of what remains on a recent grant, so that windows and totals fill up.
            bytes32 id = _pickId(r >> 8);
            (address p, address d) = registry.parties(id);
            if (p != address(0)) {
                (SpendGrant memory t,,,,) = registry.getGrant(id);
                address asset = t.assets[(r >> 24) % t.assets.length].asset;
                address to = t.recipientMode == 0 ? t.recipient : payees[(r >> 32) % 2];
                // Draw 7 is exactly what remains; draw 2 is a random amount up to it.
                uint256 draw = (((r >> 48) >> 4) << 4) | ((r >> 40) % 2 == 0 ? 7 : 2);
                _compare(id, d, asset, _pickAmount(draw, id, t, asset), to, r >> 56);
            }
        }
        uint256 w = (r >> 64) % 100;
        uint256 by = r >> 72;
        if (w < 50) return;
        if (w < 85) by %= 11;
        else if (w < 95) by %= 601;
        else if (w < 99) by %= 1 days;
        else by %= 400_000;
        vm.warp(vm.getBlockTimestamp() + by);
    }

    function _registerRandom(uint256 r) internal returns (bytes32) {
        address p = principals[r % 3];
        address d = delegates[(r >> 4) % 2];
        uint64[4] memory windows = [uint64(1), 60, 3600, 1 days];
        return _register(_randomTerms(r >> 8, p, d, windows[(r >> 6) % 4]));
    }

    /// Random terms within the structural and registration rules.
    function _randomTerms(uint256 r, address p, address d, uint64 window) internal view returns (SpendGrant memory g) {
        uint256 t = vm.getBlockTimestamp();
        g.principal = p;
        g.delegate = d;
        g.recipientMode = uint8(r % 2);
        g.recipient = g.recipientMode == 0 ? payees[(r >> 1) % 2] : address(0);
        g.windowSeconds = window;
        uint256 v = (r >> 2) % 8;
        uint256 start = v == 0 ? t + 1 + (r >> 8) % 3600 : t - (r >> 8) % 5000;
        uint256 length = v == 1 ? 1 + (r >> 24) % 100 : 1 + (r >> 24) % 2_000_000;
        g.validAfter = uint64(start);
        g.validUntil = uint64(start + length);
        g.salt = r;

        uint256 profile = (r >> 48) % 4;
        uint256 n;
        bool[] memory take = new bool[](pool.length);
        for (uint256 i = 0; i < pool.length; i++) {
            bool rare = pool[i] == noCode || pool[i] == designator;
            uint256 bit = (r >> (56 + 3 * i)) % 8;
            take[i] = rare ? bit == 0 : bit < 4;
            if (take[i]) n++;
        }
        if (n == 0) {
            for (uint256 i = 0; i < pool.length; i++) {
                if (pool[i] == address(tokenA)) take[i] = true;
            }
            n = 1;
        }
        g.assets = new AssetLimit[](n);
        uint256 k;
        for (uint256 i = 0; i < pool.length; i++) {
            if (!take[i]) continue;
            g.assets[k++] = _randomLimit(pool[i], profile, uint256(keccak256(abi.encode(r, i))));
        }
    }

    function _randomLimit(address asset, uint256 profile, uint256 r) internal pure returns (AssetLimit memory l) {
        l.asset = asset;
        if (profile == 0) {
            l.maxPerCall = 1 + r % 100;
            l.maxPerWindow = l.maxPerCall + (r >> 16) % 500;
            l.maxTotal = l.maxPerWindow + (r >> 32) % 2000;
        } else if (profile == 1) {
            l.maxPerCall = 1 + r % 50;
            l.maxPerWindow = l.maxPerCall;
            l.maxTotal = l.maxPerCall;
        } else if (profile == 2) {
            l.maxPerCall = 1 + r % 100;
            l.maxPerWindow = l.maxPerCall * 10;
            l.maxTotal = l.maxPerWindow + (r >> 16) % 10;
        } else {
            l.maxPerCall = type(uint256).max;
            l.maxPerWindow = type(uint256).max;
            l.maxTotal = type(uint256).max;
        }
    }

    function _pickId(uint256 s) internal view returns (bytes32) {
        uint256 c = s % 20;
        if (c == 0) return keccak256(abi.encode(s, "unregistered"));
        if (c == 1 && fullId != bytes32(0)) return fullId;
        if (c == 2) return invalidId;
        if (c < 12) return ids[ids.length - 1 - (s >> 8) % (ids.length < 4 ? ids.length : 4)];
        return ids[(s >> 8) % ids.length];
    }

    function _pickAsset(uint256 s, SpendGrant memory t) internal view returns (address) {
        uint256 c = s % 16;
        if (t.assets.length > 0 && c < 11) return t.assets[(s >> 8) % t.assets.length].asset;
        if (c == 11) return address(tokenC);
        if (c == 12) return NATIVE;
        if (c == 13) return noCode;
        if (c == 14) return designator;
        return address(uint160(uint256(keccak256(abi.encode(s, "asset")))));
    }

    function _pickAuthorizer(uint256 s, address p, address d) internal view returns (address) {
        uint256 c = s % 16;
        if (c < 12) return d;
        if (c == 12) return p;
        if (c == 13) return stranger;
        if (c == 14) return (s >> 8) % 2 == 0 ? address(0) : executor;
        return delegates[(s >> 8) % 2];
    }

    function _pickRecipient(uint256 s, SpendGrant memory t, address asset) internal view returns (address) {
        uint256 c = s % 14;
        address valid = t.recipientMode == 0 && t.principal != address(0) ? t.recipient : payees[(s >> 8) % 2];
        if (c < 9) return valid;
        if (c == 9) return address(0);
        if (c == 10) return t.principal == address(0) ? principal : t.principal;
        if (c == 11) return address(registry);
        if (c == 12) return (s >> 8) % 2 == 0 ? executor : asset;
        return (s >> 8) % 2 == 0 ? stranger : payees[(s >> 9) % 2];
    }

    /// Mostly at most what remains (so debits accumulate), plus each boundary just past a cap.
    function _pickAmount(uint256 s, bytes32 id, SpendGrant memory t, address asset) internal view returns (uint256) {
        uint256 c = s % 16;
        (bool listed, AssetLimit memory l) = _find(t, asset);
        if (!listed) return c < 2 ? 0 : 1 + (s >> 8) % 1000;
        (uint256 windowSpent,) = registry.rollingUsage(id, asset);
        (uint256 spent,) = registry.usage(id, asset);
        uint256 windowRoom = l.maxPerWindow > windowSpent ? l.maxPerWindow - windowSpent : 0;
        uint256 totalRoom = l.maxTotal > spent ? l.maxTotal - spent : 0;
        uint256 room = l.maxPerCall;
        if (windowRoom < room) room = windowRoom;
        if (totalRoom < room) room = totalRoom;
        if (room > type(uint192).max) room = type(uint192).max;
        if (c == 0) return 0;
        if (c == 1) return 1;
        if (c <= 6) return room == 0 ? 1 : 1 + (s >> 8) % room;
        if (c == 7) return room == 0 ? 1 : room;
        if (c == 8) return room + 1;
        if (c == 9) return l.maxPerCall == type(uint256).max ? l.maxPerCall : l.maxPerCall + 1;
        if (c == 10) return uint256(type(uint192).max) + 1;
        if (c == 11) return windowRoom == type(uint256).max ? windowRoom : windowRoom + 1;
        if (c == 12) return totalRoom == type(uint256).max ? totalRoom : totalRoom + 1;
        if (c == 13) return windowRoom;
        if (c == 14) return totalRoom;
        return s >> 8;
    }

    function _anyCaller(uint256 s) internal view returns (address) {
        address[6] memory callers = [executor, principal, delegate, stranger, address(0), address(registry)];
        return callers[s % 6];
    }

    function _find(SpendGrant memory t, address asset) internal pure returns (bool, AssetLimit memory) {
        for (uint256 i = 0; i < t.assets.length; i++) {
            if (t.assets[i].asset == asset) return (true, t.assets[i]);
        }
        AssetLimit memory none;
        return (false, none);
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

    /// Spent 1000 in an expired window, then 1024 live debits of 1: windowSpent 1024, spent 2024, ring full.
    function _fullRingFixture() internal returns (bytes32 id, SpendGrant memory g) {
        g = _base();
        g.assets[0] = AssetLimit(address(tokenA), 1000, 1_000_000, 1_000_000);
        id = _register(g);
        _spend(id, address(tokenA), 1000);
        vm.warp(vm.getBlockTimestamp() + WINDOW);
        _fill(id, address(tokenA), MAX_LIVE_DEBITS, 1);
        (uint256 windowSpent, uint256 live) = registry.rollingUsage(id, address(tokenA));
        (uint256 spent,) = registry.usage(id, address(tokenA));
        assertEq(windowSpent, 1024);
        assertEq(live, MAX_LIVE_DEBITS);
        assertEq(spent, 2024);
    }

    function _setCaps(
        bytes32 id,
        SpendGrant memory g,
        uint256 version,
        uint256 perCall,
        uint256 perWindow,
        uint256 total
    ) internal {
        g.assets[0] = AssetLimit(address(tokenA), perCall, perWindow, total);
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

    function _revoke(bytes32 id) internal {
        (address p,) = registry.parties(id);
        vm.prank(p);
        registry.revoke(id);
    }

    function _spend(bytes32 id, address asset, uint256 amount) internal {
        (, address d) = registry.parties(id);
        (SpendGrant memory t,,,,) = registry.getGrant(id);
        address to = t.recipientMode == 0 ? t.recipient : payee;
        vm.prank(executor);
        registry.consume(id, d, asset, amount, to);
    }

    function _fill(bytes32 id, address asset, uint256 n, uint256 amount) internal {
        (, address d) = registry.parties(id);
        (SpendGrant memory t,,,,) = registry.getGrant(id);
        address to = t.recipientMode == 0 ? t.recipient : payee;
        for (uint256 i = 0; i < n; i++) {
            vm.prank(executor);
            registry.consume(id, d, asset, amount, to);
        }
    }

    function _tryConsume(bytes32 id, address authorizer, address asset, uint256 amount, address to)
        internal
        returns (bool ok, bytes memory ret)
    {
        vm.prank(executor);
        (ok, ret) =
            address(registry).call(abi.encodeCall(ISpendGrantRegistry.consume, (id, authorizer, asset, amount, to)));
    }

    function _assertConsumeData(bytes32 id, address authorizer, address asset, uint256 amount, address to, uint8 n)
        internal
    {
        (bool ok, bytes memory ret) = _tryConsume(id, authorizer, asset, amount, to);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(bytes4(keccak256("SpendGrantError(uint8)")), n));
        (bool checkOk, Reason r) = registry.check(id, authorizer, asset, amount, to);
        assertFalse(checkOk);
        assertEq(uint8(r), n);
    }

    function _assertReason(bytes32 id, address authorizer, address asset, uint256 amount, address to, Reason expected)
        internal
        view
    {
        (bool ok, Reason r) = registry.check(id, authorizer, asset, amount, to);
        assertEq(uint8(r), uint8(expected), _reasonName(uint8(expected)));
        assertEq(ok, expected == Reason.OK);
    }

    function _err(Reason r) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SPEND_GRANT_ERROR, uint8(r));
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

    function _reasonName(uint256 r) internal pure returns (string memory) {
        string[15] memory names = [
            "OK",
            "INVALID_GRANT",
            "BAD_SIGNATURE",
            "NOT_YET_VALID",
            "EXPIRED",
            "REVOKED",
            "WRONG_ASSET",
            "WRONG_RECIPIENT",
            "OVER_TX_CAP",
            "OVER_WINDOW_CAP",
            "OVER_CUMULATIVE_CAP",
            "WINDOW_FULL",
            "UNAUTHORIZED_EXECUTOR",
            "UNAUTHORIZED_DELEGATE",
            "NONEXISTENT"
        ];
        return names[r];
    }
}
