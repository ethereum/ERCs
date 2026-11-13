// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {AssetLimit, MAX_LIVE_DEBITS, NATIVE, Reason, SpendGrant} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Drives one registry with consume, update and revoke, and predicts every consume from its own model: a copy
/// of each grant's current terms and revocation, and a timestamped debit log per grant and asset that it reads by a
/// full scan under the spec's liveness rule (`now < time + windowSeconds`). Every action ends in at least one
/// consume, called inside try/catch whatever the model expects and never chosen by reading the registry. The
/// registry's outcome is compared with the model's, `check` with both, and every disagreement is recorded for the
/// invariants to assert. Nothing here reverts, so `fail_on_revert` stays on.
contract SpendGrantHandler is Test {
    bytes4 internal constant SPEND_GRANT_ERROR = bytes4(keccak256("SpendGrantError(uint8)"));
    bytes4 internal constant GRANT_IS_REVOKED = bytes4(keccak256("GrantIsRevoked(bytes32)"));
    uint8 internal constant MALFORMED = 255;

    uint256 internal constant SLOTS = 3;
    /// The slot whose grant `burst` fills toward the live-debit bound.
    uint256 internal constant RING_SLOT = 2;
    /// The edge grant's slot. It is not in `slotId`, so only `consumeTargeted` spends it and nothing updates or
    /// revokes it.
    uint256 internal constant EDGE_SLOT = 3;
    uint64 internal constant FAR = 4_000_000_000;
    /// An id no one registers.
    bytes32 internal constant UNKNOWN = keccak256("unknown grant");
    /// A literal address without code: listed by slot 0, so spends of it fail the asset code check.
    address public constant NO_CODE = address(0xC0DE);

    struct Caps {
        bool listed;
        uint256 perCall;
        uint256 perWindow;
        uint256 total;
    }

    struct ModelGrant {
        bool registered;
        bool revoked;
        address delegate;
        uint8 mode;
        address recipient;
        uint64 window;
        uint64 validAfter;
        uint64 validUntil;
        uint256 version;
        uint256 slot;
    }

    /// Debits recorded at one timestamp, merged: liveness depends only on the time, so they expire together.
    struct Batch {
        uint64 time;
        uint256 amount;
        uint256 count;
    }

    struct Usage {
        Batch[] batches;
        uint256 spent;
        uint256 calls;
    }

    SpendGrantRegistry public registry;
    address public principal;
    address public delegate;
    address public delegate2;
    address public payee;
    address public payee2;
    address public stranger;
    address public token;
    address public unlisted;
    uint64 public start;

    /// Every asset a spend names, ascending (the order a grant lists them in).
    address[4] internal _universe;

    mapping(bytes32 => ModelGrant) internal _m;
    mapping(bytes32 => mapping(address => Caps)) internal _caps;
    mapping(bytes32 => mapping(address => Usage)) internal _use;
    mapping(bytes32 => mapping(address => uint256[2])) internal _usageAtRevoke;

    bytes32[SLOTS] public slotId;
    bytes32 public edgeId;
    bytes32[] internal _ids;
    bytes32[] internal _retired;
    uint256 internal _salt;
    uint256 internal _nonce;

    // Ghost state.
    uint256 public mismatches;
    string public firstMismatch;
    uint256 public acceptedAfterRevoke;
    uint256 public consumeCalls;
    uint256[15] public outcomes;
    /// The edge grant's outcomes, kept out of `outcomes` so that `outcomes` shows what every other probe reached.
    uint256[15] public edgeOutcomes;

    constructor() {
        vm.warp(1_700_000_000);
        start = uint64(vm.getBlockTimestamp() - 1 days);
        principal = makeAddr("principal");
        delegate = makeAddr("delegate");
        delegate2 = makeAddr("delegate2");
        payee = makeAddr("payee");
        payee2 = makeAddr("payee2");
        stranger = makeAddr("stranger");
        registry = new SpendGrantRegistry(address(this));
        token = address(new MockERC20());
        unlisted = address(new MockERC20());

        address[4] memory u = [token, NATIVE, NO_CODE, unlisted];
        for (uint256 i = 1; i < 4; i++) {
            for (uint256 j = i; j > 0 && uint160(u[j]) < uint160(u[j - 1]); j--) {
                (u[j], u[j - 1]) = (u[j - 1], u[j]);
            }
        }
        _universe = u;
        for (uint256 k = 0; k < SLOTS; k++) {
            slotId[k] = _registerSlot(k, delegate);
        }
        edgeId = _registerSlot(EDGE_SLOT, delegate);
    }

    // ---------------------------------------------------------------- actions

    /// Any id (a slot's, a revoked one, or an unknown one), any caller, authorizer, asset, recipient and amount.
    function consume(uint256 seed) external {
        bytes32 id = _anyId(seed);
        _warp(seed, _m[id].registered ? _m[id].window : 1 hours);
        uint256 probes = 1 + _pick(seed, 3);
        for (uint256 i = 0; i < probes; i++) {
            address asset = _pick(seed, 2) == 0 ? _universe[_pick(seed, 4)] : _listedAsset(seed, id, false);
            address caller = _pick(seed, 16) == 0 ? stranger : address(this);
            _probe(id, caller, _authorizer(seed, id), asset, _amount(seed, id, asset), _recipient(seed, id, asset));
        }
    }

    /// Slot 0's or slot 1's grant with the right authorizer and recipient and a listed asset, probed at its cap
    /// boundaries: above the per-call cap, just above the lifetime room, a spend into the room (all of it three
    /// times in four), just above the window room, and just above the lifetime room again. Then the edge grant.
    function consumeTargeted(uint256 seed) external {
        bytes32 id = slotId[_pick(seed, 2)];
        ModelGrant storage g = _m[id];
        _warp(seed, g.window);
        address asset = _listedAsset(seed, id, true);
        address to = _validRecipient(id);
        Caps storage c = _caps[id][asset];

        _probe(id, address(this), g.delegate, asset, _pick(seed, 2) == 0 ? 0 : c.perCall + 1, to);
        _probeLifetimeEdge(id, asset, to);
        (uint256 windowRoom, uint256 lifetimeRoom) = _rooms(id, asset);
        uint256 fill = _min(c.perCall, _min(windowRoom, lifetimeRoom));
        if (fill > 1 && _pick(seed, 4) == 0) fill = 1 + _pick(seed, fill);
        _probe(id, address(this), g.delegate, asset, fill == 0 ? 1 : fill, to);
        (windowRoom,) = _rooms(id, asset);
        if (windowRoom < c.perCall) _probe(id, address(this), g.delegate, asset, windowRoom + 1, to);
        _probeLifetimeEdge(id, asset, to);
        _probeEdges();
    }

    /// The ring slot's grant spends 1 per call at one timestamp: a short run, or (one time in eight) enough calls
    /// to pass the live-debit bound. Stops at the first refusal.
    function burst(uint256 seed) external {
        bytes32 id = slotId[RING_SLOT];
        vm.warp(vm.getBlockTimestamp() + _pick(seed, 3));
        address asset = _caps[id][NATIVE].listed ? NATIVE : _listedAsset(seed, id, true);
        (, uint256 live) = _window(id, asset);
        uint256 count = _pick(seed, 8) == 0 ? MAX_LIVE_DEBITS - _min(live, MAX_LIVE_DEBITS) + 2 : 1 + _pick(seed, 32);
        address to = _validRecipient(id);
        address d = _m[id].delegate;
        for (uint256 i = 0; i < count; i++) {
            if (_probe(id, address(this), d, asset, 1, to) != uint8(Reason.OK)) break;
        }
    }

    /// The principal updates a slot's grant (or, one time in eight, a revoked one, which must refuse) with the
    /// right expectedVersion: caps lowered to or below lifetime spend, a window cap lowered to or below the
    /// unexpired spend, an asset removed, an asset re-added, caps redrawn, validity paused, ended or restored, and
    /// the recipient changed. Then the grant is spent under its new terms.
    function update(uint256 seed) external {
        bool onRevoked = _retired.length > 0 && _pick(seed, 8) == 0;
        bytes32 id = onRevoked ? _retired[_pick(seed, _retired.length)] : slotId[_pick(seed, SLOTS)];
        vm.warp(vm.getBlockTimestamp() + _pick(seed, 4));
        ModelGrant storage g = _m[id];
        (SpendGrant memory terms, Caps[4] memory next) = _changedTerms(seed, id);

        vm.prank(principal);
        try registry.update(id, g.version, terms) {
            if (g.revoked) _fail("update accepted for a revoked grant", 0, 0);
            else _applyTerms(id, terms, next);
        } catch (bytes memory err) {
            if (!g.revoked || keccak256(err) != keccak256(abi.encodeWithSelector(GRANT_IS_REVOKED, id))) {
                _fail("update refused", g.revoked ? 1 : 0, err.length);
            }
        }
        _probeValid(seed, id);
    }

    /// One time in four, the principal revokes a slot's grant and registers a new one in its place (with the same
    /// or the other delegate); one time in eight, revokes an already revoked grant again, which changes nothing.
    /// The revoked grant and the slot's grant are then spent.
    function revoke(uint256 seed) external {
        uint256 k = _pick(seed, SLOTS);
        if (_retired.length > 0 && _pick(seed, 8) == 0) {
            bytes32 old = _retired[_pick(seed, _retired.length)];
            vm.prank(principal);
            try registry.revoke(old) {}
            catch {
                _fail("repeat revoke refused", 0, 0);
            }
        }
        if (_pick(seed, 4) == 0) {
            bytes32 id = slotId[k];
            vm.prank(principal);
            try registry.revoke(id) {
                _m[id].revoked = true;
                for (uint256 i = 0; i < 4; i++) {
                    (uint256 spent, uint256 calls) = registry.usage(id, _universe[i]);
                    _usageAtRevoke[id][_universe[i]] = [spent, calls];
                }
                _retired.push(id);
                slotId[k] = _registerSlot(k, _pick(seed, 2) == 0 ? delegate : delegate2);
            } catch {
                _fail("revoke refused", 0, 0);
            }
            _probeValid(seed, id);
        }
        _probeValid(seed, slotId[k]);
    }

    // ---------------------------------------------------------------- the comparison

    /// Calls `check` and `consume` for one spend and compares both with the model. Returns the registry's outcome.
    function _probe(bytes32 id, address caller, address authorizer, address asset, uint256 amount, address to)
        internal
        returns (uint8 actual)
    {
        Reason evaluated = _evaluate(id, authorizer, asset, amount, to);
        Reason expected = caller == address(this) ? evaluated : Reason.UNAUTHORIZED_EXECUTOR;

        try registry.check(id, authorizer, asset, amount, to) returns (bool ok, Reason r) {
            if (r != evaluated || ok != (r == Reason.OK)) _fail("check", uint8(evaluated), uint8(r));
        } catch {
            _fail("check reverted", uint8(evaluated), MALFORMED);
        }

        if (caller != address(this)) vm.prank(caller);
        try registry.consume(id, authorizer, asset, amount, to) {
            actual = uint8(Reason.OK);
        } catch (bytes memory err) {
            actual = _reasonOf(err);
        }
        consumeCalls++;
        if (actual < 15) {
            if (id == edgeId) edgeOutcomes[actual]++;
            else outcomes[actual]++;
        }
        if (actual != uint8(expected)) _fail("consume", uint8(expected), actual);
        if (actual == uint8(Reason.OK) && _m[id].revoked) acceptedAfterRevoke++;
        if (expected == Reason.OK) _record(id, asset, amount);
    }

    /// The model's verdict, in the registry's evaluation order (steps 1-12), from the model's own terms and log.
    function _evaluate(bytes32 id, address authorizer, address asset, uint256 amount, address to)
        internal
        view
        returns (Reason)
    {
        ModelGrant storage g = _m[id];
        if (!g.registered) return Reason.NONEXISTENT;
        if (authorizer != g.delegate) return Reason.UNAUTHORIZED_DELEGATE;
        uint256 nowTs = vm.getBlockTimestamp();
        if (nowTs < g.validAfter) return Reason.NOT_YET_VALID;
        if (nowTs >= g.validUntil) return Reason.EXPIRED;
        if (g.revoked) return Reason.REVOKED;
        if (to == address(0) || to == principal || to == address(registry) || to == address(this) || to == asset) {
            return Reason.WRONG_RECIPIENT;
        }
        if (g.mode == 0 && to != g.recipient) return Reason.WRONG_RECIPIENT;
        Caps storage c = _caps[id][asset];
        if (!c.listed) return Reason.WRONG_ASSET;
        if (asset == NO_CODE) return Reason.INVALID_GRANT;
        if (amount == 0 || amount > c.perCall || amount > type(uint192).max) return Reason.OVER_TX_CAP;
        (uint256 windowSpent, uint256 live) = _window(id, asset);
        if (windowSpent + amount > c.perWindow) return Reason.OVER_WINDOW_CAP;
        if (_use[id][asset].spent + amount > c.total) return Reason.OVER_CUMULATIVE_CAP;
        if (live >= MAX_LIVE_DEBITS) return Reason.WINDOW_FULL;
        return Reason.OK;
    }

    /// Unexpired spend and debit count by a full scan of the log.
    function _window(bytes32 id, address asset) internal view returns (uint256 sum, uint256 live) {
        Batch[] storage b = _use[id][asset].batches;
        uint256 nowTs = vm.getBlockTimestamp();
        uint256 w = _m[id].window;
        for (uint256 i = 0; i < b.length; i++) {
            if (nowTs < uint256(b[i].time) + w) {
                sum += b[i].amount;
                live += b[i].count;
            }
        }
    }

    function _record(bytes32 id, address asset, uint256 amount) internal {
        Usage storage u = _use[id][asset];
        uint64 t = uint64(vm.getBlockTimestamp());
        uint256 n = u.batches.length;
        if (n > 0 && u.batches[n - 1].time == t) {
            u.batches[n - 1].amount += amount;
            u.batches[n - 1].count += 1;
        } else {
            u.batches.push(Batch(t, amount, 1));
        }
        u.spent += amount;
        u.calls += 1;
    }

    /// The reason in exactly `SpendGrantError(uint8)` revert data; MALFORMED for anything else.
    function _reasonOf(bytes memory err) internal pure returns (uint8) {
        if (err.length != 36 || bytes4(err) != SPEND_GRANT_ERROR) return MALFORMED;
        uint256 word;
        assembly ("memory-safe") {
            word := mload(add(err, 36))
        }
        return word < 15 ? uint8(word) : MALFORMED;
    }

    function _fail(string memory what, uint256 expected, uint256 actual) internal {
        if (mismatches++ == 0) {
            firstMismatch = string.concat(
                what,
                ": expected ",
                vm.toString(expected),
                ", got ",
                vm.toString(actual),
                ", after ",
                vm.toString(consumeCalls),
                " consumes"
            );
        }
    }

    // ---------------------------------------------------------------- grants and terms

    /// Slot 0: a fixed payee, three assets (one without code). Slot 1: any payee, two assets. In both, the window
    /// cap equals the lifetime cap, so one expired spend is enough for the lifetime cap to bind before the window
    /// cap (with `maxPerWindow <= maxTotal`, nothing else lets it). Slot 2: any payee, a per-call cap of 1 or 2 and
    /// a window cap above the live-debit bound, for `burst`. The edge grant: any payee; for the token, a window cap
    /// under twice the per-call cap and a lifetime cap far above both; for the native asset, every cap at 1.
    function _base(uint256 k, address asset) internal view returns (bool allowed, Caps memory c) {
        if (k == 0) {
            if (asset == token) return (true, Caps(true, 100, 150, 150));
            if (asset == NATIVE) return (true, Caps(true, 60, 100, 100));
            if (asset == NO_CODE) return (true, Caps(true, 5, 5, 5));
        } else if (k == 1) {
            if (asset == token) return (true, Caps(true, 40, 60, 60));
            if (asset == NATIVE) return (true, Caps(true, 30, 50, 50));
        } else if (k == RING_SLOT) {
            if (asset == NATIVE) return (true, Caps(true, 1, 1100, 1e30));
            if (asset == token) return (true, Caps(true, 2, 2000, 1e30));
        } else {
            if (asset == token) return (true, Caps(true, 40, 60, 1e30));
            if (asset == NATIVE) return (true, Caps(true, 1, 1, 1));
        }
    }

    function _slotWindow(uint256 k) internal pure returns (uint64) {
        return k == 0 ? 10 minutes : k == 1 ? 15 minutes : 5 minutes;
    }

    function _registerSlot(uint256 k, address d) internal returns (bytes32 id) {
        Caps[4] memory next;
        for (uint256 i = 0; i < 4; i++) {
            (, next[i]) = _base(k, _universe[i]);
        }
        SpendGrant memory t;
        t.principal = principal;
        t.delegate = d;
        t.recipientMode = k == 0 ? 0 : 1;
        t.recipient = k == 0 ? payee : address(0);
        t.windowSeconds = _slotWindow(k);
        t.validAfter = start;
        t.validUntil = FAR;
        t.salt = ++_salt;
        t.assets = _limits(next);

        vm.prank(principal);
        try registry.register(t) returns (bytes32 got) {
            id = got;
        } catch {
            _fail("register refused", k, 0);
            return UNKNOWN;
        }
        if (_m[id].registered) _fail("register reused an id", k, 0);
        _m[id] = ModelGrant({
            registered: true,
            revoked: false,
            delegate: d,
            mode: t.recipientMode,
            recipient: t.recipient,
            window: t.windowSeconds,
            validAfter: t.validAfter,
            validUntil: t.validUntil,
            version: 1,
            slot: k
        });
        for (uint256 i = 0; i < 4; i++) {
            _caps[id][_universe[i]] = next[i];
        }
        _ids.push(id);
    }

    /// New terms from the model's current ones. Principal, delegate and window are kept (update refuses to
    /// change them); salt is arbitrary (update ignores it).
    function _changedTerms(uint256 seed, bytes32 id) internal returns (SpendGrant memory t, Caps[4] memory next) {
        ModelGrant storage g = _m[id];
        uint256 k = g.slot;
        for (uint256 i = 0; i < 4; i++) {
            next[i] = _caps[id][_universe[i]];
        }

        uint256 a = _allowedIndex(seed, k);
        (, Caps memory base) = _base(k, _universe[a]);
        Caps memory c = next[a];
        uint256 kind = _pick(seed, 6);
        if (kind == 0 && c.listed) {
            // Lifetime cap to at or below what has been spent.
            uint256 spent = _use[id][_universe[a]].spent;
            c.total = spent == 0 ? 1 : 1 + _pick(seed, spent);
            c.perWindow = _min(c.perWindow, c.total);
            c.perCall = _min(c.perCall, c.perWindow);
        } else if (kind == 1 && c.listed) {
            // Window cap to at or below the unexpired spend.
            (uint256 windowSpent,) = _window(id, _universe[a]);
            c.perWindow = _min(windowSpent == 0 ? 1 : 1 + _pick(seed, windowSpent), c.total);
            c.perCall = _min(c.perCall, c.perWindow);
        } else if (kind == 2 && c.listed && _listedCount(next) > 1) {
            // Remove the asset; its usage stays.
            c = Caps(false, 0, 0, 0);
        } else if (kind >= 3 || !c.listed) {
            // Redraw the caps within the slot's base (half the time with the lifetime cap equal to the window
            // cap), re-adding the asset if it was removed.
            c.listed = true;
            c.perCall = 1 + _pick(seed, base.perCall);
            c.perWindow = c.perCall + _pick(seed, base.perWindow - c.perCall + 1);
            c.total = _pick(seed, 2) == 0 ? c.perWindow : c.perWindow + _pick(seed, base.total - c.perWindow + 1);
        }
        next[a] = c;

        t.principal = principal;
        t.delegate = g.delegate;
        t.windowSeconds = g.window;
        t.salt = _pick(seed, 1000);
        t.recipientMode = g.mode;
        t.recipient = g.recipient;
        uint256 v = _pick(seed, 8);
        uint64 nowTs = uint64(vm.getBlockTimestamp());
        if (v == 0) {
            (t.validAfter, t.validUntil) = (nowTs + 1 + uint64(_pick(seed, g.window)), FAR);
        } else if (v == 1) {
            (t.validAfter, t.validUntil) = (start, nowTs);
        } else {
            (t.validAfter, t.validUntil) = (start, FAR);
        }
        uint256 r = _pick(seed, 8);
        if (r == 0) {
            (t.recipientMode, t.recipient) = g.mode == 0 ? (1, address(0)) : (0, _pick(seed, 2) == 0 ? payee : payee2);
        } else if (r == 1 && g.mode == 0) {
            t.recipient = g.recipient == payee ? payee2 : payee;
        }
        t.assets = _limits(next);
    }

    function _applyTerms(bytes32 id, SpendGrant memory t, Caps[4] memory next) internal {
        ModelGrant storage g = _m[id];
        g.mode = t.recipientMode;
        g.recipient = t.recipient;
        g.validAfter = t.validAfter;
        g.validUntil = t.validUntil;
        g.version += 1;
        for (uint256 i = 0; i < 4; i++) {
            _caps[id][_universe[i]] = next[i];
        }
    }

    function _limits(Caps[4] memory next) internal view returns (AssetLimit[] memory list) {
        list = new AssetLimit[](_listedCount(next));
        uint256 j;
        for (uint256 i = 0; i < 4; i++) {
            if (next[i].listed) {
                list[j++] = AssetLimit(_universe[i], next[i].perCall, next[i].perWindow, next[i].total);
            }
        }
    }

    function _listedCount(Caps[4] memory next) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < 4; i++) {
            if (next[i].listed) n++;
        }
    }

    // ---------------------------------------------------------------- picks

    function _pick(uint256 seed, uint256 n) internal returns (uint256) {
        return uint256(keccak256(abi.encode(seed, ++_nonce))) % n;
    }

    /// Steps from {0, 1, window - 1, window, window + 1} or anywhere in [0, 2 * window].
    function _warp(uint256 seed, uint64 window) internal {
        uint256 p = _pick(seed, 8);
        uint256 dt = p == 0
            ? 0
            : p == 1
                ? 1
                : p == 2 ? window - 1 : p == 3 ? window : p == 4 ? window + 1 : _pick(seed, 2 * uint256(window) + 1);
        vm.warp(vm.getBlockTimestamp() + dt);
    }

    function _anyId(uint256 seed) internal returns (bytes32) {
        uint256 p = _pick(seed, 16);
        if (p == 0) return UNKNOWN;
        if (p <= 2 && _retired.length > 0) return _retired[_pick(seed, _retired.length)];
        return slotId[_pick(seed, SLOTS)];
    }

    function _authorizer(uint256 seed, bytes32 id) internal returns (address) {
        address d = _m[id].registered ? _m[id].delegate : delegate;
        uint256 p = _pick(seed, 8);
        if (p == 0) return stranger;
        if (p == 1) return d == delegate ? delegate2 : delegate;
        return d;
    }

    function _validRecipient(bytes32 id) internal view returns (address) {
        return _m[id].registered && _m[id].mode == 0 ? _m[id].recipient : payee;
    }

    /// Mostly the right recipient; otherwise zero, the principal, the registry, the executor, the asset, or another
    /// payee (wrong only for a fixed-payee grant).
    function _recipient(uint256 seed, bytes32 id, address asset) internal returns (address) {
        if (_pick(seed, 8) != 0) return _validRecipient(id);
        uint256 p = _pick(seed, 6);
        if (p == 0) return address(0);
        if (p == 1) return principal;
        if (p == 2) return address(registry);
        if (p == 3) return address(this);
        if (p == 4) return asset;
        return _validRecipient(id) == payee ? payee2 : payee;
    }

    /// A listed asset of the grant (one with code when `withCode`), or any asset if none is listed.
    function _listedAsset(uint256 seed, bytes32 id, bool withCode) internal returns (address) {
        address[4] memory found;
        uint256 n;
        for (uint256 i = 0; i < 4; i++) {
            address a = _universe[i];
            if (_caps[id][a].listed && !(withCode && a == NO_CODE)) found[n++] = a;
        }
        if (n == 0) return _universe[_pick(seed, 4)];
        return found[_pick(seed, n)];
    }

    /// The index in `_universe` of an asset the slot may list.
    function _allowedIndex(uint256 seed, uint256 k) internal returns (uint256) {
        uint256[4] memory found;
        uint256 n;
        for (uint256 i = 0; i < 4; i++) {
            (bool allowed,) = _base(k, _universe[i]);
            if (allowed) found[n++] = i;
        }
        return found[_pick(seed, n)];
    }

    /// Amounts at the edges the model sees: zero, the per-call cap and one above it, the window and lifetime rooms
    /// and one above each, past uint192, the largest uint256, or anything up to the per-call cap.
    function _amount(uint256 seed, bytes32 id, address asset) internal returns (uint256) {
        Caps storage c = _caps[id][asset];
        (uint256 windowRoom, uint256 lifetimeRoom) = _rooms(id, asset);
        uint256 p = _pick(seed, 12);
        if (p == 0) return 0;
        if (p == 1) return c.perCall + 1;
        if (p == 2) return windowRoom;
        if (p == 3) return windowRoom + 1;
        if (p == 4) return lifetimeRoom;
        if (p == 5) return lifetimeRoom + 1;
        if (p == 6) return c.perCall;
        if (p == 7) return uint256(type(uint192).max) + 1;
        if (p == 8) return type(uint256).max;
        return 1 + _pick(seed, c.perCall == 0 ? 100 : c.perCall);
    }

    function _rooms(bytes32 id, address asset) internal view returns (uint256 windowRoom, uint256 lifetimeRoom) {
        Caps storage c = _caps[id][asset];
        (uint256 windowSpent,) = _window(id, asset);
        uint256 spent = _use[id][asset].spent;
        windowRoom = c.perWindow > windowSpent ? c.perWindow - windowSpent : 0;
        lifetimeRoom = c.total > spent ? c.total - spent : 0;
    }

    /// Just above the lifetime room, when that is within both the per-call cap and the window room.
    function _probeLifetimeEdge(bytes32 id, address asset, address to) internal {
        (uint256 windowRoom, uint256 lifetimeRoom) = _rooms(id, asset);
        if (lifetimeRoom < _min(_caps[id][asset].perCall, windowRoom)) {
            _probe(id, address(this), _m[id].delegate, asset, lifetimeRoom + 1, to);
        }
    }

    /// The edge grant's caps, whatever the slots' grants have been through. The token is spent by the lesser of its
    /// per-call cap and its window room, then probed just above the room left: with a window cap under twice the
    /// per-call cap, that room is under the per-call cap, so the probe is refused for the window cap, and the
    /// lifetime cap is never in reach. The native asset is probed for 1: accepted once, then refused for the window
    /// cap until that spend has left the window, and for the lifetime cap after.
    function _probeEdges() internal {
        (uint256 windowRoom,) = _rooms(edgeId, token);
        uint256 fill = _min(_caps[edgeId][token].perCall, windowRoom);
        if (fill > 0) _probe(edgeId, address(this), delegate, token, fill, payee);
        (windowRoom,) = _rooms(edgeId, token);
        _probe(edgeId, address(this), delegate, token, windowRoom + 1, payee);
        _probe(edgeId, address(this), delegate, NATIVE, 1, payee);
    }

    /// The right authorizer and recipient, a listed asset, an edge amount.
    function _probeValid(uint256 seed, bytes32 id) internal {
        address asset = _listedAsset(seed, id, false);
        _probe(id, address(this), _m[id].delegate, asset, _amount(seed, id, asset), _validRecipient(id));
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // ---------------------------------------------------------------- views for the invariants

    function idCount() external view returns (uint256) {
        return _ids.length;
    }

    function idAt(uint256 i) external view returns (bytes32) {
        return _ids[i];
    }

    function retiredCount() external view returns (uint256) {
        return _retired.length;
    }

    function retiredAt(uint256 i) external view returns (bytes32) {
        return _retired[i];
    }

    function universe(uint256 i) external view returns (address) {
        return _universe[i];
    }

    function modelUsage(bytes32 id, address asset) external view returns (uint256 spent, uint256 calls) {
        return (_use[id][asset].spent, _use[id][asset].calls);
    }

    function modelWindow(bytes32 id, address asset) external view returns (uint256 spent, uint256 calls) {
        return _window(id, asset);
    }

    function modelGrant(bytes32 id) external view returns (bool revoked, uint256 version, AssetLimit[] memory assets) {
        Caps[4] memory listed;
        for (uint256 i = 0; i < 4; i++) {
            listed[i] = _caps[id][_universe[i]];
        }
        return (_m[id].revoked, _m[id].version, _limits(listed));
    }

    function usageAtRevoke(bytes32 id, address asset) external view returns (uint256 spent, uint256 calls) {
        return (_usageAtRevoke[id][asset][0], _usageAtRevoke[id][asset][1]);
    }
}

/// @notice Model-differential invariants over consume, update and revoke (see SpendGrantHandler).
contract SpendGrantInvariantTest is Test {
    SpendGrantHandler internal handler;
    SpendGrantRegistry internal registry;

    function setUp() public {
        handler = new SpendGrantHandler();
        registry = handler.registry();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = SpendGrantHandler.consume.selector;
        selectors[1] = SpendGrantHandler.consumeTargeted.selector;
        selectors[2] = SpendGrantHandler.burst.selector;
        selectors[3] = SpendGrantHandler.update.selector;
        selectors[4] = SpendGrantHandler.revoke.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// The registry accepted exactly the spends the model accepted, refused the rest with the model's reason,
    /// `check` agreed with both, and every update and revoke had the expected outcome.
    /// forge-config: default.invariant.runs = 16
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_registryAgreesWithModel() public view {
        assertEq(handler.mismatches(), 0, handler.firstMismatch());
    }

    /// Lifetime and unexpired usage, the version, the revocation, and the stored asset list equal the model's for
    /// every grant ever registered and every asset.
    /// forge-config: default.invariant.runs = 16
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_usageAndTermsMatchModel() public view {
        uint256 n = handler.idCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 id = handler.idAt(i);
            for (uint256 j = 0; j < 4; j++) {
                address asset = handler.universe(j);
                (uint256 spent, uint256 calls) = registry.usage(id, asset);
                (uint256 modelSpent, uint256 modelCalls) = handler.modelUsage(id, asset);
                assertEq(spent, modelSpent, "spent");
                assertEq(calls, modelCalls, "calls");
                (uint256 windowSpent, uint256 live) = registry.rollingUsage(id, asset);
                (uint256 modelWindowSpent, uint256 modelLive) = handler.modelWindow(id, asset);
                assertEq(windowSpent, modelWindowSpent, "window spent");
                assertEq(live, modelLive, "live debits");
            }
            (SpendGrant memory terms, uint256 version,,, bool isRevoked) = registry.getGrant(id);
            (bool modelRevoked, uint256 modelVersion, AssetLimit[] memory modelAssets) = handler.modelGrant(id);
            assertEq(isRevoked, modelRevoked, "revoked");
            assertEq(version, modelVersion, "version");
            assertEq(abi.encode(terms.assets), abi.encode(modelAssets), "assets");
        }
    }

    /// No grant ever holds more than MAX_LIVE_DEBITS unexpired debits for an asset (`burst` reaches the bound),
    /// and unexpired spend never exceeds lifetime spend.
    /// forge-config: default.invariant.runs = 16
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_liveDebitsBounded() public view {
        uint256 n = handler.idCount();
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j < 4; j++) {
                bytes32 id = handler.idAt(i);
                address asset = handler.universe(j);
                (uint256 windowSpent, uint256 live) = registry.rollingUsage(id, asset);
                assertLe(live, MAX_LIVE_DEBITS);
                (uint256 spent,) = registry.usage(id, asset);
                assertLe(windowSpent, spent);
            }
        }
    }

    /// A revoked grant's usage never moves after the revocation, and no consume on a revoked grant succeeded.
    /// forge-config: default.invariant.runs = 16
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_nothingConsumedAfterRevoke() public view {
        assertEq(handler.acceptedAfterRevoke(), 0);
        uint256 n = handler.retiredCount();
        for (uint256 i = 0; i < n; i++) {
            bytes32 id = handler.retiredAt(i);
            assertTrue(registry.revoked(id));
            for (uint256 j = 0; j < 4; j++) {
                address asset = handler.universe(j);
                (uint256 spent, uint256 calls) = registry.usage(id, asset);
                (uint256 spentThen, uint256 callsThen) = handler.usageAtRevoke(id, asset);
                assertEq(spent, spentThen);
                assertEq(calls, callsThen);
            }
        }
    }

    /// Foundry calls this after every run, so no run's comparisons were vacuous. The slots' grants must reach OK and
    /// the per-call cap in every run. Whether they reach the window and lifetime caps depends on the run (the window
    /// cap only until the lifetime room is spent and that spend has left the window), so those two also count the
    /// edge grant's outcomes: every `consumeTargeted` reaches its window cap, and each one after its native spend
    /// has left the window reaches its lifetime cap. Runs are 128 calls long so that each run makes many such calls.
    /// `test_handler_reachesEveryReason` checks on a fixed sequence that every reason is reached without the edge
    /// grant.
    function afterInvariant() public view {
        assertGt(handler.outcomes(uint8(Reason.OK)), 0, "no OK");
        assertGt(handler.outcomes(uint8(Reason.OVER_TX_CAP)), 0, "no OVER_TX_CAP");
        uint8 w = uint8(Reason.OVER_WINDOW_CAP);
        uint8 l = uint8(Reason.OVER_CUMULATIVE_CAP);
        assertGt(handler.outcomes(w) + handler.edgeOutcomes(w), 0, "no OVER_WINDOW_CAP");
        assertGt(handler.outcomes(l) + handler.edgeOutcomes(l), 0, "no OVER_CUMULATIVE_CAP");
    }

    /// The handler's reach, on a fixed sequence of 600 actions: every reason the registry can return to a spend (all
    /// but the reserved BAD_SIGNATURE) is reached without the edge grant, the registry agrees with the model
    /// throughout, and the invariants hold at the end.
    function test_handler_reachesEveryReason() public {
        for (uint256 i = 0; i < 600; i++) {
            uint256 seed = uint256(keccak256(abi.encode("step", i)));
            uint256 action = seed % 5;
            if (action == 0) handler.consume(seed);
            else if (action == 1) handler.consumeTargeted(seed);
            else if (action == 2) handler.burst(seed);
            else if (action == 3) handler.update(seed);
            else handler.revoke(seed);
        }
        assertEq(handler.mismatches(), 0, handler.firstMismatch());
        uint256 reached;
        for (uint256 r = 0; r < 15; r++) {
            uint256 hits = handler.outcomes(r);
            console.log("reason", r, hits);
            if (r == uint8(Reason.BAD_SIGNATURE)) {
                assertEq(hits, 0);
            } else {
                assertGt(hits, 0, vm.toString(r));
                reached++;
            }
        }
        assertEq(reached, 14);
        assertGt(handler.retiredCount(), 0);
        console.log("consumes", handler.consumeCalls());
        invariant_usageAndTermsMatchModel();
        invariant_liveDebitsBounded();
        invariant_nothingConsumedAfterRevoke();
    }
}
