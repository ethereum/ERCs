// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {AssetLimit, GrantState, MAX_LIVE_DEBITS, NATIVE, Reason, SpendGrant} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Every read reverts.
contract RevertingToken {
    fallback() external {
        revert("hostile");
    }
}

/// @dev Every read returns 31 bytes.
contract ShortReturnToken {
    fallback() external {
        assembly {
            mstore(0, 0x40)
            return(0, 31)
        }
    }
}

/// @dev Every read returns 64 bytes.
contract LongReturnToken {
    fallback() external {
        assembly {
            mstore(0, 0x40)
            mstore(0x20, 0x40)
            return(0, 64)
        }
    }
}

/// @dev Every read reverts with exactly one word of revert data.
contract Revert32Token {
    fallback() external {
        assembly {
            mstore(0, 777)
            revert(0, 32)
        }
    }
}

/// @dev Every read returns 100,000 bytes.
contract ReturnBombToken {
    fallback() external {
        assembly {
            return(0, 100000)
        }
    }
}

/// @dev Every read loops until it runs out of gas.
contract GasBombToken {
    fallback() external {
        assembly {
            for {} 1 {} { mstore(0, keccak256(0, 0x20)) }
        }
    }
}

/// @dev `balanceOf` answers; `allowance` reverts.
contract HalfToken {
    function balanceOf(address) external pure returns (uint256) {
        return 777;
    }

    function allowance(address, address) external pure returns (uint256) {
        revert("no");
    }
}

/// @notice `grantState`: status, caps, usage, the fail-soft balance and allowance reads, `spendableNow`,
/// and agreement with `check`.
contract SpendGrantStateTest is Test {
    uint64 internal constant WINDOW = 1 days;
    bytes4 internal constant INSUFFICIENT_GAS = bytes4(keccak256("InsufficientGas()"));
    address internal constant SHA256_PRECOMPILE = address(2);

    SpendGrantRegistry internal registry;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;
    RevertingToken internal reverting;

    address internal executor;
    address internal principal;
    address internal delegate;
    address internal payee;
    address internal stranger;
    address internal noCode;
    address internal designator;

    address[] internal pool;
    uint256[15] internal statusHits;
    uint256[15] internal okReasonHits;
    uint256 internal spendableProbes; // probes whose formula value was nonzero

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
        reverting = new RevertingToken();
        tokenA.mint(principal, 1e24);
        tokenB.mint(principal, 1e24);
        vm.startPrank(principal);
        tokenA.approve(executor, type(uint256).max);
        tokenB.approve(executor, type(uint256).max);
        vm.stopPrank();
        vm.deal(principal, 50 ether);
    }

    // ---------------------------------------------------------------- status

    function test_state_nonexistent() public view {
        GrantState memory s = registry.grantState(keccak256("unknown"), address(tokenA));
        assertEq(uint8(s.status), uint8(Reason.NONEXISTENT));
        _assertCaps(s, 0, 0, 0);
        _assertUsage(s, 0, 0, 0, 0);
        _assertNotRead(s);
        assertEq(s.spendableNow, 0);
    }

    function test_state_ok() public {
        bytes32 id = _register(_base());
        GrantState memory s = registry.grantState(id, address(tokenA));
        assertEq(uint8(s.status), uint8(Reason.OK));
        _assertCaps(s, 100, 1000, 5000);
        _assertUsage(s, 0, 0, 0, 0);
        assertTrue(s.balanceKnown);
        assertTrue(s.allowanceKnown);
        assertEq(s.balance, 1e24);
        assertEq(s.allowance, type(uint256).max);
        assertEq(s.spendableNow, 1000);
    }

    function test_state_notYetValid() public {
        SpendGrant memory g = _base();
        g.validAfter = uint64(vm.getBlockTimestamp() + 10);
        bytes32 id = _register(g);
        GrantState memory s = registry.grantState(id, address(tokenA));
        assertEq(uint8(s.status), uint8(Reason.NOT_YET_VALID));
        _assertCaps(s, 100, 1000, 5000);
        assertTrue(s.balanceKnown && s.allowanceKnown);
        assertEq(s.balance, 1e24);
        assertEq(s.spendableNow, 0);
    }

    function test_state_expired() public {
        SpendGrant memory g = _base();
        bytes32 id = _register(g);
        vm.warp(g.validUntil);
        GrantState memory s = registry.grantState(id, address(tokenA));
        assertEq(uint8(s.status), uint8(Reason.EXPIRED));
        _assertCaps(s, 100, 1000, 5000);
        assertEq(s.spendableNow, 0);
    }

    function test_state_revoked() public {
        bytes32 id = _register(_base());
        _spend(id, address(tokenA), 10);
        vm.prank(principal);
        registry.revoke(id);
        GrantState memory s = registry.grantState(id, address(tokenA));
        assertEq(uint8(s.status), uint8(Reason.REVOKED));
        _assertCaps(s, 100, 1000, 5000);
        _assertUsage(s, 10, 10, 1, vm.getBlockTimestamp() + WINDOW);
        assertEq(s.spendableNow, 0);
    }

    function test_state_wrongAssetIsNotRead() public {
        bytes32 id = _register(_base());
        GrantState memory s = registry.grantState(id, address(tokenB));
        assertEq(uint8(s.status), uint8(Reason.WRONG_ASSET));
        _assertCaps(s, 0, 0, 0);
        _assertNotRead(s);
        assertEq(s.spendableNow, 0);
    }

    function test_state_invalidGrantNoCode() public {
        bytes32 id = _register(_grantFor(noCode, 100, 1000, 5000));
        GrantState memory s = registry.grantState(id, noCode);
        assertEq(uint8(s.status), uint8(Reason.INVALID_GRANT));
        _assertCaps(s, 100, 1000, 5000);
        _assertNotRead(s);
        assertEq(s.spendableNow, 0);
    }

    function test_state_invalidGrantDesignator() public {
        bytes32 id = _register(_grantFor(designator, 100, 1000, 5000));
        GrantState memory s = registry.grantState(id, designator);
        assertEq(uint8(s.status), uint8(Reason.INVALID_GRANT));
        _assertCaps(s, 100, 1000, 5000);
        _assertNotRead(s);
        assertEq(s.spendableNow, 0);
    }

    /// SHA-256 answers any call with 32 bytes; a read would report a "known" garbage balance.
    function test_state_precompileNeverRead() public {
        bytes32 id = _register(_grantFor(SHA256_PRECOMPILE, 100, 1000, 5000));
        vm.expectCall(SHA256_PRECOMPILE, "", 0);
        GrantState memory s = registry.grantState(id, SHA256_PRECOMPILE);
        assertEq(uint8(s.status), uint8(Reason.INVALID_GRANT));
        _assertNotRead(s);
    }

    /// Positive control for the `expectCall` matcher above: a listed token is read once each way.
    function test_state_readsAListedTokenOnceEach() public {
        bytes32 id = _register(_base());
        vm.expectCall(address(tokenA), abi.encodeWithSignature("balanceOf(address)", principal), 1);
        vm.expectCall(address(tokenA), abi.encodeWithSignature("allowance(address,address)", principal, executor), 1);
        GrantState memory s = registry.grantState(id, address(tokenA));
        assertTrue(s.balanceKnown && s.allowanceKnown);
    }

    function test_state_statusOrder() public {
        uint64 t = uint64(vm.getBlockTimestamp());
        SpendGrant memory later = _base();
        later.validAfter = t + 10;
        later.validUntil = t + 20;
        bytes32 laterId = _register(later);
        _revoke(laterId);
        SpendGrant memory brief = _base();
        brief.validUntil = t + 5;
        bytes32 briefId = _register(brief);
        _revoke(briefId);
        SpendGrant memory gone = _base();
        gone.salt = 3;
        bytes32 goneId = _register(gone);
        _revoke(goneId);
        bytes32 liveId = _register(_grantFor(address(tokenA), 1, 1, 1));
        vm.warp(t + 5);

        assertEq(uint8(registry.grantState(laterId, noCode).status), uint8(Reason.NOT_YET_VALID));
        assertEq(uint8(registry.grantState(briefId, noCode).status), uint8(Reason.EXPIRED));
        assertEq(uint8(registry.grantState(goneId, noCode).status), uint8(Reason.REVOKED));
        assertEq(uint8(registry.grantState(liveId, noCode).status), uint8(Reason.WRONG_ASSET));
        GrantState memory s = registry.grantState(briefId, noCode);
        _assertCaps(s, 0, 0, 0);
        _assertNotRead(s);
    }

    // ---------------------------------------------------------------- spendableNow: each binding term

    function test_spendable_windowBinds() public {
        bytes32 id = _register(_grantFor(address(tokenA), 100, 500, 10_000));
        _spend(id, address(tokenA), 100);
        _spend(id, address(tokenA), 100);
        GrantState memory s = registry.grantState(id, address(tokenA));
        assertEq(s.windowSpent, 200);
        assertEq(s.spendableNow, 300);
    }

    function test_spendable_totalBinds() public {
        uint256 t0 = vm.getBlockTimestamp();
        bytes32 id = _register(_grantFor(address(tokenA), 1000, 1000, 1000));
        _spend(id, address(tokenA), 700);
        vm.warp(t0 + WINDOW);
        GrantState memory s = registry.grantState(id, address(tokenA));
        assertEq(s.windowSpent, 0);
        assertEq(s.spent, 700);
        assertEq(s.spendableNow, 300);
    }

    function test_spendable_liveDebitSlotsBind() public {
        bytes32 id = _register(_grantFor(address(tokenA), 1, 5000, 1_000_000));
        for (uint256 i = 0; i < 10; i++) {
            _spend(id, address(tokenA), 1);
        }
        GrantState memory s = registry.grantState(id, address(tokenA));
        assertEq(s.liveDebits, 10);
        assertEq(s.spendableNow, MAX_LIVE_DEBITS - 10);
    }

    function test_spendable_balanceBinds() public {
        address poor = makeAddr("poor");
        tokenA.mint(poor, 50);
        vm.prank(poor);
        tokenA.approve(executor, type(uint256).max);
        SpendGrant memory g = _base();
        g.principal = poor;
        bytes32 id = _register(g);
        GrantState memory s = registry.grantState(id, address(tokenA));
        assertEq(s.balance, 50);
        assertEq(s.spendableNow, 50);
    }

    function test_spendable_allowanceBinds() public {
        address careful = makeAddr("careful");
        tokenA.mint(careful, 1e24);
        vm.prank(careful);
        tokenA.approve(executor, 40);
        SpendGrant memory g = _base();
        g.principal = careful;
        bytes32 id = _register(g);
        GrantState memory s = registry.grantState(id, address(tokenA));
        assertEq(s.allowance, 40);
        assertEq(s.spendableNow, 40);
    }

    /// With every cap at the maximum, the per-debit amount bound (uint192) and the 1024 slots bind.
    function test_spendable_amountBoundBinds() public {
        uint256 max = type(uint256).max;
        bytes32 id = _register(_grantFor(NATIVE, max, max, max));
        vm.deal(principal, max);
        GrantState memory s = registry.grantState(id, NATIVE);
        assertEq(s.spendableNow, MAX_LIVE_DEBITS * uint256(type(uint192).max));
        assertEq(s.maxPerCall, max);
    }

    /// spendableNow counts each free slot at the lesser of maxPerCall and the amount bound (2^192 - 1): for maxPerCall
    /// one below the bound, at it and one above it, with the window, lifetime, balance and allowance at the maximum.
    function test_spendable_slotSizeAtTheAmountBound() public {
        uint256 max = type(uint256).max;
        uint256 bound = type(uint192).max;
        uint256[3] memory perCall = [bound - 1, bound, bound + 1];
        uint256[3] memory perDebit = [bound - 1, bound, bound];
        vm.deal(principal, max);
        for (uint256 i = 0; i < perCall.length; i++) {
            bytes32 id = _register(_grantFor(NATIVE, perCall[i], max, max));
            GrantState memory s = registry.grantState(id, NATIVE);
            assertEq(uint8(s.status), uint8(Reason.OK));
            assertEq(s.maxPerCall, perCall[i]);
            assertEq(s.spendableNow, MAX_LIVE_DEBITS * perDebit[i]);
        }
    }

    function test_spendable_allowanceIsTheExecutors() public {
        vm.startPrank(principal);
        tokenA.approve(stranger, 1e30);
        tokenA.approve(executor, 40);
        vm.stopPrank();
        bytes32 id = _register(_base());
        GrantState memory s = registry.grantState(id, address(tokenA));
        assertEq(s.allowance, 40);
        assertEq(s.spendableNow, 40);
    }

    // ---------------------------------------------------------------- usage fields

    function test_state_nextExpiry() public {
        uint256 t0 = vm.getBlockTimestamp();
        bytes32 id = _register(_base());
        _spend(id, address(tokenA), 10);
        vm.warp(t0 + 100);
        _spend(id, address(tokenA), 20);
        _assertUsage(registry.grantState(id, address(tokenA)), 30, 30, 2, t0 + WINDOW);
        vm.warp(t0 + WINDOW);
        _assertUsage(registry.grantState(id, address(tokenA)), 30, 20, 1, t0 + 100 + WINDOW);
        vm.warp(t0 + 100 + WINDOW);
        _assertUsage(registry.grantState(id, address(tokenA)), 30, 0, 0, 0);
    }

    function test_state_removedAssetKeepsItsHistory() public {
        uint256 t0 = vm.getBlockTimestamp();
        SpendGrant memory g = _base();
        g.assets = _two(AssetLimit(address(tokenA), 100, 1000, 5000), AssetLimit(address(tokenB), 100, 1000, 5000));
        bytes32 id = _register(g);
        _spend(id, address(tokenB), 30);
        vm.prank(principal);
        registry.update(id, 1, _base());
        GrantState memory s = registry.grantState(id, address(tokenB));
        assertEq(uint8(s.status), uint8(Reason.WRONG_ASSET));
        _assertCaps(s, 0, 0, 0);
        _assertUsage(s, 30, 30, 1, t0 + WINDOW);
        _assertNotRead(s);
        assertEq(s.spendableNow, 0);
    }

    // ---------------------------------------------------------------- hostile assets: unknown, never a revert

    function test_hostile_revertingReads() public {
        _assertHostile(address(reverting));
    }

    function test_hostile_shortReturn() public {
        _assertHostile(address(new ShortReturnToken()));
    }

    function test_hostile_longReturn() public {
        _assertHostile(address(new LongReturnToken()));
    }

    /// A read is known only if the call succeeds and returns exactly 32 bytes: one that reverts with exactly one word
    /// of revert data is unknown, its value 0.
    function test_hostile_revertWithOneWord() public {
        _assertHostile(address(new Revert32Token()));
    }

    function test_hostile_returnBomb() public {
        _assertHostile(address(new ReturnBombToken()));
    }

    /// Each read burns its whole stipend and no more.
    function test_hostile_gasBomb() public {
        address bomb = address(new GasBombToken());
        bytes32 id = _register(_grantFor(bomb, 100, 1000, 5000));
        uint256 before = gasleft();
        GrantState memory s = registry.grantState(id, bomb);
        uint256 used = before - gasleft();
        assertEq(uint8(s.status), uint8(Reason.OK));
        assertFalse(s.balanceKnown);
        assertFalse(s.allowanceKnown);
        assertGe(used, 200_000);
        assertLt(used, 300_000);
    }

    function test_hostile_flagsAreIndependent() public {
        address half = address(new HalfToken());
        bytes32 id = _register(_grantFor(half, 100, 1000, 5000));
        GrantState memory s = registry.grantState(id, half);
        assertEq(uint8(s.status), uint8(Reason.OK));
        assertTrue(s.balanceKnown);
        assertEq(s.balance, 777);
        assertFalse(s.allowanceKnown);
        assertEq(s.allowance, 0);
        assertEq(s.spendableNow, 0);
    }

    // ---------------------------------------------------------------- native currency

    function test_state_native() public {
        SpendGrant memory g = _base();
        g.assets = _two(AssetLimit(address(tokenA), 100, 1000, 5000), AssetLimit(NATIVE, 1 ether, 10 ether, 100 ether));
        bytes32 id = _register(g);
        GrantState memory s = registry.grantState(id, NATIVE);
        assertEq(uint8(s.status), uint8(Reason.OK));
        assertTrue(s.balanceKnown && s.allowanceKnown);
        assertEq(s.balance, 50 ether);
        assertEq(s.allowance, type(uint256).max);
        assertEq(s.spendableNow, 10 ether);
        vm.deal(principal, 3 ether);
        s = registry.grantState(id, NATIVE);
        assertEq(s.balance, 3 ether);
        assertEq(s.spendableNow, 3 ether);
    }

    // ---------------------------------------------------------------- gas guard (the sweeps: SpendGrantStateGas.t.sol)

    function test_state_starvedGasReverts() public {
        bytes32 id = _register(_base());
        vm.expectRevert(abi.encodeWithSelector(INSUFFICIENT_GAS));
        registry.grantState{gas: 60_000}(id, address(tokenA));
    }

    // ---------------------------------------------------------------- agreement with check

    /// status != OK => check(id, delegate, asset, 1, r) returns status for a valid recipient r;
    /// status == OK => it returns OK or a cap reason (OVER_WINDOW_CAP, OVER_CUMULATIVE_CAP, WINDOW_FULL).
    function test_state_matchesCheck_enumerated() public {
        uint64 t = uint64(vm.getBlockTimestamp());
        _probe(keccak256("unknown"), address(tokenA));

        bytes32 fresh = _register(_base());
        _probe(fresh, address(tokenA));
        _probe(fresh, address(tokenB));

        SpendGrant memory later = _base();
        later.validAfter = t + 10;
        _probe(_register(later), address(tokenA));

        SpendGrant memory brief = _base();
        brief.validUntil = t + 5;
        bytes32 briefId = _register(brief);

        SpendGrant memory gone = _base();
        gone.salt = 2;
        bytes32 goneId = _register(gone);
        _revoke(goneId);
        _probe(goneId, address(tokenA));

        SpendGrant memory odd = _base();
        odd.recipientMode = 1;
        odd.recipient = address(0);
        AssetLimit memory l = AssetLimit(address(0), 100, 1000, 5000);
        odd.assets = new AssetLimit[](6);
        address[6] memory listed = [address(tokenA), NATIVE, noCode, designator, SHA256_PRECOMPILE, address(reverting)];
        for (uint256 i = 0; i < listed.length; i++) {
            odd.assets[i] = AssetLimit(listed[i], l.maxPerCall, l.maxPerWindow, l.maxTotal);
        }
        _sortAssets(odd.assets);
        bytes32 oddId = _register(odd);
        for (uint256 i = 0; i < listed.length; i++) {
            _probe(oddId, listed[i]);
        }

        // OK status with each cap reason.
        bytes32 windowFull = _register(_grantFor(address(tokenB), 100, 100, 1000));
        _spend(windowFull, address(tokenB), 100);
        _probe(windowFull, address(tokenB));
        SpendGrant memory spentOut = _grantFor(address(tokenB), 100, 100, 100);
        spentOut.salt = 7;
        bytes32 spentOutId = _register(spentOut);
        _spend(spentOutId, address(tokenB), 100);

        bytes32 full = _register(_grantFor(address(tokenC), 1, 10_000, 10_000));
        for (uint256 i = 0; i < MAX_LIVE_DEBITS; i++) {
            _spend(full, address(tokenC), 1);
        }
        _probe(full, address(tokenC));

        // A removed asset.
        SpendGrant memory two = _base();
        two.salt = 8;
        two.assets = _two(AssetLimit(address(tokenA), 100, 1000, 5000), AssetLimit(address(tokenB), 100, 1000, 5000));
        bytes32 twoId = _register(two);
        _spend(twoId, address(tokenB), 5);
        SpendGrant memory one = _base();
        one.salt = 8;
        vm.prank(principal);
        registry.update(twoId, 1, one);
        _probe(twoId, address(tokenB));

        vm.warp(t + WINDOW);
        _probe(briefId, address(tokenA));
        _probe(spentOutId, address(tokenB));
        _probe(windowFull, address(tokenB));

        _assertStatusCoverage(true);
    }

    function test_state_matchesCheck_random() public {
        address[7] memory p =
            [address(tokenA), address(tokenB), NATIVE, noCode, designator, SHA256_PRECOMPILE, address(reverting)];
        for (uint256 i = 0; i < p.length; i++) {
            pool.push(p[i]);
        }
        for (uint256 i = 1; i < pool.length; i++) {
            for (uint256 j = i; j > 0 && pool[j - 1] > pool[j]; j--) {
                (pool[j - 1], pool[j]) = (pool[j], pool[j - 1]);
            }
        }
        bytes32 seed = keccak256("ERC-8427 v3 grantState/check");
        for (uint256 i = 0; i < 160; i++) {
            seed = keccak256(abi.encode(seed, i));
            this.stateCase(uint256(seed));
        }
        _assertStatusCoverage(false);
    }

    /// One random state, probed for every pool asset, an unlisted token, and an unknown id.
    function stateCase(uint256 r) external {
        require(msg.sender == address(this), "self only");
        SpendGrant memory g = _randomTerms(r, WINDOW);
        bytes32 id = _register(g);
        uint256 debits = (r >> 128) % 5;
        for (uint256 i = 0; i < debits; i++) {
            uint256 s = uint256(keccak256(abi.encode(r, "debit", i)));
            AssetLimit memory l = g.assets[s % g.assets.length];
            uint256 room = _room(id, l);
            uint256 amount = (s >> 8) % 3 == 0 ? room : 1 + (s >> 16) % (room == 0 ? 1 : room);
            address to = g.recipientMode == 0 ? g.recipient : payee;
            (bool ok,) = registry.check(id, g.delegate, l.asset, amount, to);
            if (ok) _spend(id, l.asset, amount);
            if ((s >> 200) % 3 == 0) vm.warp(vm.getBlockTimestamp() + (s >> 208) % (2 * uint256(WINDOW)));
        }
        if ((r >> 136) % 4 == 0) {
            SpendGrant memory n = _randomTerms(r >> 140, WINDOW);
            vm.prank(principal);
            registry.update(id, 1, n);
        }
        if ((r >> 160) % 6 == 0) _revoke(id);
        if ((r >> 164) % 3 == 0) vm.warp(vm.getBlockTimestamp() + (r >> 168) % 3 days);
        for (uint256 i = 0; i < pool.length; i++) {
            _probe(id, pool[i]);
        }
        _probe(id, address(tokenC));
        _probe(keccak256(abi.encode(r, "unknown")), address(tokenA));
    }

    function _probe(bytes32 id, address asset) internal {
        GrantState memory s = registry.grantState(id, asset);
        (address p, address d) = registry.parties(id);
        address to = payee;
        AssetLimit memory l; // the asset's caps in the stored terms; zero if unknown id or not listed
        if (p != address(0)) {
            (SpendGrant memory t,,,,) = registry.getGrant(id);
            if (t.recipientMode == 0) to = t.recipient;
            l = _limitOf(t, asset);
        }
        _assertCaps(s, l.maxPerCall, l.maxPerWindow, l.maxTotal);
        (bool ok, Reason reason) = registry.check(id, d, asset, 1, to);
        assertEq(ok, reason == Reason.OK);
        bool capReason =
            reason == Reason.OVER_WINDOW_CAP || reason == Reason.OVER_CUMULATIVE_CAP || reason == Reason.WINDOW_FULL;
        if (s.status != Reason.OK || capReason) assertEq(s.spendableNow, 0, "spendableNow while check fails");
        if (s.status != Reason.OK) {
            assertEq(uint8(reason), uint8(s.status), "status differs from check");
        } else {
            assertTrue(reason == Reason.OK || capReason, "OK status but check fails a non-cap step");
            okReasonHits[uint8(reason)]++;
            if (s.spendableNow > 0) {
                uint256 amount = s.spendableNow < s.maxPerCall ? s.spendableNow : s.maxPerCall;
                if (amount > type(uint192).max) amount = type(uint192).max;
                (bool payable_,) = registry.check(id, d, asset, amount, to);
                assertTrue(payable_, "spendableNow overstates");
            }
        }
        statusHits[uint8(s.status)]++;

        (uint256 spent,) = registry.usage(id, asset);
        (uint256 windowSpent, uint256 live) = registry.rollingUsage(id, asset);
        (uint256[] memory expiresAt,) = registry.liveDebits(id, asset, 1);
        assertEq(s.spent, spent);
        assertEq(s.windowSpent, windowSpent);
        assertEq(s.liveDebits, live);
        assertEq(s.nextExpiry, expiresAt.length == 0 ? 0 : expiresAt[0]);

        // §3.6 from the stored caps, the usage views and the asset itself, never from grantState's fields.
        uint256 expected;
        if (s.status == Reason.OK) {
            (uint256 balance, uint256 allowance) = _readsOf(p, asset);
            expected = l.maxPerWindow > windowSpent ? l.maxPerWindow - windowSpent : 0;
            uint256 lifetime = l.maxTotal > spent ? l.maxTotal - spent : 0;
            if (lifetime < expected) expected = lifetime;
            uint256 perDebit = l.maxPerCall < type(uint192).max ? l.maxPerCall : type(uint192).max;
            uint256 slots = (MAX_LIVE_DEBITS - live) * perDebit;
            if (slots < expected) expected = slots;
            if (balance < expected) expected = balance;
            if (allowance < expected) expected = allowance;
        }
        assertEq(s.spendableNow, expected, "spendableNow differs from the plan formula");
        if (expected > 0) spendableProbes++;
    }

    function _limitOf(SpendGrant memory t, address asset) internal pure returns (AssetLimit memory l) {
        for (uint256 i = 0; i < t.assets.length; i++) {
            if (t.assets[i].asset == asset) return t.assets[i];
        }
    }

    /// The principal's balance and allowance to the executor as the asset itself reports them: the mocks are
    /// read directly, NATIVE is the account balance with no allowance limit, and the only other asset that can
    /// reach status OK here, the reverting token, cannot be read (0, unknown).
    function _readsOf(address p, address asset) internal view returns (uint256 balance, uint256 allowance) {
        if (asset == NATIVE) return (p.balance, type(uint256).max);
        if (asset == address(tokenA) || asset == address(tokenB) || asset == address(tokenC)) {
            return (MockERC20(asset).balanceOf(p), MockERC20(asset).allowance(p, executor));
        }
        assertEq(asset, address(reverting), "an unreadable asset other than the reverting token reached OK");
    }

    function _assertStatusCoverage(bool withWindowFull) internal view {
        Reason[7] memory statuses = [
            Reason.OK,
            Reason.NONEXISTENT,
            Reason.NOT_YET_VALID,
            Reason.EXPIRED,
            Reason.REVOKED,
            Reason.WRONG_ASSET,
            Reason.INVALID_GRANT
        ];
        for (uint256 i = 0; i < statuses.length; i++) {
            console2.log("status", uint8(statuses[i]), statusHits[uint8(statuses[i])]);
            assertGe(statusHits[uint8(statuses[i])], 1, "status not observed");
        }
        console2.log("OK status, check OK", okReasonHits[uint8(Reason.OK)]);
        console2.log("OK status, OVER_WINDOW_CAP", okReasonHits[uint8(Reason.OVER_WINDOW_CAP)]);
        console2.log("OK status, OVER_CUMULATIVE_CAP", okReasonHits[uint8(Reason.OVER_CUMULATIVE_CAP)]);
        console2.log("OK status, WINDOW_FULL", okReasonHits[uint8(Reason.WINDOW_FULL)]);
        assertGe(okReasonHits[uint8(Reason.OK)], 1);
        console2.log("probes with nonzero spendableNow", spendableProbes);
        assertGe(spendableProbes, 1, "formula only ever compared zero");
        assertGe(okReasonHits[uint8(Reason.OVER_WINDOW_CAP)], 1);
        assertGe(okReasonHits[uint8(Reason.OVER_CUMULATIVE_CAP)], 1);
        if (withWindowFull) assertGe(okReasonHits[uint8(Reason.WINDOW_FULL)], 1);
    }

    function _randomTerms(uint256 r, uint64 window) internal view returns (SpendGrant memory g) {
        uint256 t = vm.getBlockTimestamp();
        g.principal = principal;
        g.delegate = delegate;
        g.recipientMode = uint8(r % 2);
        g.recipient = g.recipientMode == 0 ? payee : address(0);
        g.windowSeconds = window;
        uint256 v = (r >> 2) % 6;
        uint256 start = v == 0 ? t + 1 + (r >> 8) % 3600 : t - (r >> 8) % 5000;
        uint256 length = v == 1 ? 1 + (r >> 24) % 100 : 1 + (r >> 24) % 2_000_000;
        g.validAfter = uint64(start);
        g.validUntil = uint64(start + length);
        g.salt = r;
        uint256 n;
        bool[] memory take = new bool[](pool.length);
        for (uint256 i = 0; i < pool.length; i++) {
            take[i] = (r >> (48 + 2 * i)) % 3 == 0;
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
        uint256 profile = (r >> 80) % 3;
        for (uint256 i = 0; i < pool.length; i++) {
            if (!take[i]) continue;
            uint256 x = uint256(keccak256(abi.encode(r, i)));
            uint256 perCall = 1 + x % 100;
            if (profile == 0) {
                g.assets[k++] = AssetLimit(pool[i], perCall, perCall * 3, perCall * 6);
            } else if (profile == 1) {
                g.assets[k++] = AssetLimit(pool[i], perCall, perCall, perCall);
            } else {
                g.assets[k++] = AssetLimit(pool[i], perCall, perCall * 10, perCall * 10 + (x >> 8) % 50);
            }
        }
    }

    function _room(bytes32 id, AssetLimit memory l) internal view returns (uint256 room) {
        (uint256 windowSpent,) = registry.rollingUsage(id, l.asset);
        (uint256 spent,) = registry.usage(id, l.asset);
        room = l.maxPerCall;
        uint256 w = l.maxPerWindow > windowSpent ? l.maxPerWindow - windowSpent : 0;
        uint256 tot = l.maxTotal > spent ? l.maxTotal - spent : 0;
        if (w < room) room = w;
        if (tot < room) room = tot;
    }

    // ---------------------------------------------------------------- helpers

    function _assertHostile(address token) internal {
        bytes32 id = _register(_grantFor(token, 100, 1000, 5000));
        GrantState memory s = registry.grantState(id, token);
        assertEq(uint8(s.status), uint8(Reason.OK));
        _assertCaps(s, 100, 1000, 5000);
        _assertNotRead(s);
        assertEq(s.spendableNow, 0);
        (bool ok,) = registry.check(id, delegate, token, 1, payee);
        assertTrue(ok);
    }

    function _assertCaps(GrantState memory s, uint256 perCall, uint256 perWindow, uint256 total) internal pure {
        assertEq(s.maxPerCall, perCall, "maxPerCall");
        assertEq(s.maxPerWindow, perWindow, "maxPerWindow");
        assertEq(s.maxTotal, total, "maxTotal");
    }

    function _assertUsage(GrantState memory s, uint256 spent, uint256 windowSpent, uint256 live, uint256 nextExpiry)
        internal
        pure
    {
        assertEq(s.spent, spent, "spent");
        assertEq(s.windowSpent, windowSpent, "windowSpent");
        assertEq(s.liveDebits, live, "liveDebits");
        assertEq(s.nextExpiry, nextExpiry, "nextExpiry");
    }

    function _assertNotRead(GrantState memory s) internal pure {
        assertFalse(s.balanceKnown, "balanceKnown");
        assertFalse(s.allowanceKnown, "allowanceKnown");
        assertEq(s.balance, 0, "balance");
        assertEq(s.allowance, 0, "allowance");
    }

    function _base() internal view returns (SpendGrant memory g) {
        g = _grantFor(address(tokenA), 100, 1000, 5000);
    }

    function _grantFor(address asset, uint256 perCall, uint256 perWindow, uint256 total)
        internal
        view
        returns (SpendGrant memory g)
    {
        uint64 t = uint64(vm.getBlockTimestamp());
        g.principal = principal;
        g.delegate = delegate;
        g.recipientMode = 0;
        g.recipient = payee;
        g.windowSeconds = WINDOW;
        g.assets = new AssetLimit[](1);
        g.assets[0] = AssetLimit(asset, perCall, perWindow, total);
        g.validAfter = t;
        g.validUntil = t + 30 days;
        g.salt = 1;
    }

    function _register(SpendGrant memory g) internal returns (bytes32 id) {
        vm.prank(g.principal);
        id = registry.register(g);
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

    function _two(AssetLimit memory a, AssetLimit memory b) internal pure returns (AssetLimit[] memory list) {
        list = new AssetLimit[](2);
        (list[0], list[1]) = a.asset < b.asset ? (a, b) : (b, a);
    }

    function _sortAssets(AssetLimit[] memory list) internal pure {
        for (uint256 i = 1; i < list.length; i++) {
            for (uint256 j = i; j > 0 && list[j - 1].asset > list[j].asset; j--) {
                (list[j - 1], list[j]) = (list[j], list[j - 1]);
            }
        }
    }
}
