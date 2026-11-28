// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {
    AssetLimit,
    FixedField,
    GrantExists,
    GrantIsRevoked,
    GrantState,
    ISpendGrantRegistry,
    InsufficientGas,
    MAX_ASSETS,
    MAX_LIVE_DEBITS,
    NATIVE,
    NotPrincipal,
    Reason,
    SpendGrant,
    SpendGrantError,
    StaleVersion,
    UnknownGrant
} from "./SpendGrantTypes.sol";
import {SpendGrantHash} from "./SpendGrantHash.sol";
import {SpendGrantSignature} from "./SpendGrantSignature.sol";

/// @dev The two reads `grantState` makes of an ERC-20 asset.
interface IERC20Reads {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract SpendGrantRegistry is ISpendGrantRegistry {
    /// @dev Low bits of a ring slot hold the amount; the high 64 bits hold the timestamp.
    uint256 internal constant AMOUNT_BITS = 192;

    /// @dev Gas each balance or allowance read in `grantState` may use.
    uint256 internal constant READ_GAS = 100_000;

    /// @dev `gasleft()` a read needs before the call so that the token receives all of READ_GAS under the
    /// 63/64 rule, with a margin for the call itself (account access and setup).
    uint256 internal constant READ_GAS_REQUIRED = READ_GAS + READ_GAS / 63 + 5000;

    /// @dev The stored terms of a registered grant and its lifecycle. `assetCombine` is always 0 and is not
    /// stored. An id is registered iff `principal != 0`.
    struct Grant {
        address principal;
        uint64 validAfter;
        uint8 recipientMode;
        bool revoked;
        address delegate;
        uint64 validUntil;
        address recipient;
        uint64 windowSeconds;
        uint64 version;
        uint64 createdAt;
        uint64 updatedAt;
        uint256 salt;
        AssetLimit[] assets;
    }

    /// @dev Each ring slot packs `time (uint64) << 192 | amount (uint192)` into one storage word.
    struct AssetUsage {
        uint64 head;
        uint64 tail;
        uint64 calls;
        uint256 spent;
        uint256 windowSpent;
        uint256[MAX_LIVE_DEBITS] ring;
    }

    /// @dev What `_previewDebit` found for a debit that passes steps 9-12: the ring head after dropping
    /// expired debits, the tail, the unexpired spend, and the lifetime spend, all before the debit.
    struct DebitPlan {
        uint64 head;
        uint64 tail;
        uint256 windowSpent;
        uint256 spent;
    }

    address internal immutable EXECUTOR;

    mapping(bytes32 => Grant) internal _grants;
    mapping(bytes32 => mapping(address => AssetUsage)) internal _usage;
    mapping(address => bytes32[]) internal _grantsOf;
    mapping(address => bytes32[]) internal _grantsTo;

    error ZeroExecutor();

    constructor(address executor_) {
        if (executor_ == address(0)) revert ZeroExecutor();
        EXECUTOR = executor_;
    }

    function executor() external view returns (address) {
        return EXECUTOR;
    }

    /// @notice The id `register(terms)` would assign at this registry on this chain. Validates nothing.
    /// After an `update` the id can differ from the hash of the grant's current terms.
    function hashGrant(SpendGrant calldata terms) external view returns (bytes32) {
        return SpendGrantHash.digest(block.chainid, address(this), terms);
    }

    function register(SpendGrant calldata terms) external returns (bytes32 grantId) {
        if (msg.sender != terms.principal) revert NotPrincipal();
        _assertStructure(terms);
        _assertRegistrable(terms);
        grantId = SpendGrantHash.digest(block.chainid, address(this), terms);
        Grant storage g = _grants[grantId];
        if (g.principal != address(0)) revert GrantExists(grantId);

        g.principal = terms.principal;
        g.delegate = terms.delegate;
        g.windowSeconds = terms.windowSeconds;
        g.salt = terms.salt;
        g.version = 1;
        g.createdAt = uint64(block.timestamp);
        _setTerms(g, terms);
        _grantsOf[terms.principal].push(grantId);
        _grantsTo[terms.delegate].push(grantId);
        emit GrantRegistered(grantId, terms.principal, terms.delegate, terms);
    }

    /// @dev `terms.salt` is ignored: the grant keeps its registration salt and its id.
    function update(bytes32 grantId, uint256 expectedVersion, SpendGrant calldata terms) external {
        Grant storage g = _grants[grantId];
        address principal = g.principal;
        if (principal == address(0)) revert UnknownGrant(grantId);
        if (msg.sender != principal) revert NotPrincipal();
        if (g.revoked) revert GrantIsRevoked(grantId);
        uint64 current = g.version;
        if (expectedVersion != current) revert StaleVersion(current);
        if (terms.principal != principal || terms.delegate != g.delegate || terms.windowSeconds != g.windowSeconds) {
            revert FixedField();
        }
        _assertStructure(terms);
        _assertRegistrable(terms);

        _setTerms(g, terms);
        uint64 version = current + 1;
        g.version = version;
        emit GrantUpdated(grantId, principal, g.delegate, version, _terms(g));
    }

    function revoke(bytes32 grantId) external {
        Grant storage g = _grants[grantId];
        address principal = g.principal;
        if (principal == address(0)) revert UnknownGrant(grantId);
        if (msg.sender != principal) revert NotPrincipal();
        if (g.revoked) return;
        g.revoked = true;
        emit GrantRevoked(grantId, principal, g.delegate);
    }

    function revoked(bytes32 grantId) external view returns (bool) {
        return _grants[grantId].revoked;
    }

    function getGrant(bytes32 grantId)
        external
        view
        returns (SpendGrant memory terms, uint256 version, uint256 createdAt, uint256 updatedAt, bool isRevoked)
    {
        Grant storage g = _grants[grantId];
        return (_terms(g), g.version, g.createdAt, g.updatedAt, g.revoked);
    }

    function parties(bytes32 grantId) external view returns (address principal, address delegate) {
        Grant storage g = _grants[grantId];
        return (g.principal, g.delegate);
    }

    function grantsOf(address principal, uint256 offset, uint256 limit)
        external
        view
        returns (bytes32[] memory grantIds, uint256 total)
    {
        return _page(_grantsOf[principal], offset, limit);
    }

    function grantsTo(address delegate, uint256 offset, uint256 limit)
        external
        view
        returns (bytes32[] memory grantIds, uint256 total)
    {
        return _page(_grantsTo[delegate], offset, limit);
    }

    function usage(bytes32 grantId, address asset) external view returns (uint256 spent, uint256 calls) {
        AssetUsage storage u = _usage[grantId][asset];
        return (u.spent, u.calls);
    }

    function rollingUsage(bytes32 grantId, address asset) external view returns (uint256 spent, uint256 calls) {
        AssetUsage storage u = _usage[grantId][asset];
        (uint64 head, uint256 expiredAmount) = _expiredPrefix(u, _grants[grantId].windowSeconds);
        spent = u.windowSpent - expiredAmount;
        calls = uint256(u.tail - head);
    }

    /// @notice Drops up to `maxCount` expired debits from the front of the ring for `(grantId, asset)`.
    /// Anyone may call it. It changes nothing any check or view returns; it moves the cost of dropping
    /// expired debits, which would otherwise fall on the next `consume` all at once, into calls of a
    /// size the caller chooses.
    function evict(bytes32 grantId, address asset, uint256 maxCount) external {
        AssetUsage storage u = _usage[grantId][asset];
        uint64 windowSeconds = _grants[grantId].windowSeconds;

        uint64 head = u.head;
        uint64 tail = u.tail;
        uint256 evicted;
        uint256 dropped;
        while (head < tail && dropped < maxCount) {
            (uint64 time, uint256 amount) = _unpack(u.ring[head % MAX_LIVE_DEBITS]);
            if (_live(time, windowSeconds)) break;
            evicted += amount;
            unchecked {
                ++head;
                ++dropped;
            }
        }
        if (dropped == 0) return;
        u.head = head;
        u.windowSpent -= evicted;
    }

    /// @notice The oldest `min(maxCount, n)` of the `n` unexpired debits for `asset` under `grantId`
    /// at this block, in recording order. `amounts[i]` counts against the window while
    /// `block.timestamp < expiresAt[i]`.
    function liveDebits(bytes32 grantId, address asset, uint256 maxCount)
        external
        view
        returns (uint256[] memory expiresAt, uint256[] memory amounts)
    {
        AssetUsage storage u = _usage[grantId][asset];
        uint64 windowSeconds = _grants[grantId].windowSeconds;
        (uint64 head,) = _expiredPrefix(u, windowSeconds);

        uint256 n = u.tail - head;
        if (n > maxCount) n = maxCount;
        expiresAt = new uint256[](n);
        amounts = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            (uint64 time, uint256 amount) = _unpack(u.ring[(uint256(head) + i) % MAX_LIVE_DEBITS]);
            expiresAt[i] = uint256(time) + uint256(windowSeconds);
            amounts[i] = amount;
        }
    }

    /// @notice What a reader needs to know about `asset` under `grantId` at this block. Never reverts
    /// because of the asset; reverts with `InsufficientGas` when called with too little gas to read it.
    function grantState(bytes32 grantId, address asset) external view returns (GrantState memory s) {
        Grant storage g = _grants[grantId];
        AssetUsage storage u = _usage[grantId][asset];
        uint64 windowSeconds = g.windowSeconds;
        (uint64 head, uint256 expiredAmount) = _expiredPrefix(u, windowSeconds);
        uint64 tail = u.tail;
        s.spent = u.spent;
        s.windowSpent = u.windowSpent - expiredAmount;
        s.liveDebits = tail - head;
        if (head < tail) {
            (uint64 time,) = _unpack(u.ring[head % MAX_LIVE_DEBITS]);
            s.nextExpiry = uint256(time) + uint256(windowSeconds);
        }

        address principal = g.principal;
        if (principal == address(0)) {
            s.status = Reason.NONEXISTENT;
            return s;
        }
        (Reason assetStatus, AssetLimit memory limit) = _assetStatus(g, asset);
        if (assetStatus != Reason.WRONG_ASSET) {
            s.maxPerCall = limit.maxPerCall;
            s.maxPerWindow = limit.maxPerWindow;
            s.maxTotal = limit.maxTotal;
        }
        // Read only an asset that passes step 8, so empty accounts and precompiles are never called.
        if (assetStatus == Reason.OK) {
            if (asset == NATIVE) {
                (s.balance, s.balanceKnown) = (principal.balance, true);
                (s.allowance, s.allowanceKnown) = (type(uint256).max, true);
            } else {
                (s.balance, s.balanceKnown) = _read(asset, abi.encodeCall(IERC20Reads.balanceOf, (principal)));
                (s.allowance, s.allowanceKnown) =
                    _read(asset, abi.encodeCall(IERC20Reads.allowance, (principal, EXECUTOR)));
            }
        }
        s.status = _grantStatus(g);
        if (s.status == Reason.OK) s.status = assetStatus;
        if (s.status == Reason.OK) s.spendableNow = _spendable(s);
    }

    /// @notice The reason `consume(grantId, authorizer, asset, amount, recipient)` would fail with if the
    /// executor called it now, or OK if it would succeed. The same evaluation as `consume`, for any caller.
    function check(bytes32 grantId, address authorizer, address asset, uint256 amount, address recipient)
        external
        view
        returns (bool ok, Reason reason)
    {
        (reason,) = _evaluate(grantId, authorizer, asset, amount, recipient);
        ok = reason == Reason.OK;
    }

    /// @dev `authorizer` is the address the executor authenticated as authorizing this spend. Knowing a
    /// grant's id is not authority: ids are public.
    function consume(bytes32 grantId, address authorizer, address asset, uint256 amount, address recipient) external {
        if (msg.sender != EXECUTOR) revert SpendGrantError(Reason.UNAUTHORIZED_EXECUTOR);
        (Reason reason, DebitPlan memory plan) = _evaluate(grantId, authorizer, asset, amount, recipient);
        if (reason != Reason.OK) revert SpendGrantError(reason);
        _applyDebit(grantId, asset, amount, plan);
        emit GrantConsumed(grantId, _grants[grantId].principal, asset, amount, recipient);
    }

    /// @dev Evaluation steps 1-12 in order; the first failing step's reason, else OK and the debit to record.
    function _evaluate(bytes32 grantId, address authorizer, address asset, uint256 amount, address recipient)
        internal
        view
        returns (Reason reason, DebitPlan memory plan)
    {
        Grant storage g = _grants[grantId];
        address principal = g.principal;
        if (principal == address(0)) return (Reason.NONEXISTENT, plan);
        if (authorizer != g.delegate) return (Reason.UNAUTHORIZED_DELEGATE, plan);
        reason = _grantStatus(g);
        if (reason != Reason.OK) return (reason, plan);

        // The payee is never nothing, the principal, this registry, the executor, or the asset itself: the
        // first burns or misattributes, the second spends cap on a no-op, the rest strand the funds.
        if (
            recipient == address(0) || recipient == principal || recipient == address(this) || recipient == EXECUTOR
                || recipient == asset
        ) {
            return (Reason.WRONG_RECIPIENT, plan);
        }
        if (g.recipientMode == 0 && recipient != g.recipient) return (Reason.WRONG_RECIPIENT, plan);

        AssetLimit memory limit;
        (reason, limit) = _assetStatus(g, asset);
        if (reason != Reason.OK) return (reason, plan);
        return _previewDebit(grantId, limit, asset, amount);
    }

    /// @dev Steps 3-5 for a registered grant: validity at this block, then revocation.
    function _grantStatus(Grant storage g) internal view returns (Reason) {
        if (block.timestamp < g.validAfter) return Reason.NOT_YET_VALID;
        if (block.timestamp >= g.validUntil) return Reason.EXPIRED;
        if (g.revoked) return Reason.REVOKED;
        return Reason.OK;
    }

    /// @dev Steps 7-8: `asset` is listed in the current terms (its limit is returned), and it is NATIVE or
    /// has code that is not an EIP-7702 designator. Only the asset being spent needs code; an unrelated
    /// listing without code does not block the grant.
    function _assetStatus(Grant storage g, address asset) internal view returns (Reason, AssetLimit memory limit) {
        AssetLimit[] storage assets = g.assets;
        uint256 n = assets.length;
        uint256 i;
        while (i < n && assets[i].asset != asset) {
            unchecked {
                ++i;
            }
        }
        if (i == n) return (Reason.WRONG_ASSET, limit);
        limit = assets[i];
        if (asset != NATIVE) {
            uint256 codeLen = asset.code.length;
            if (codeLen == 0 || (codeLen == 23 && SpendGrantSignature.isDelegationDesignator(asset))) {
                return (Reason.INVALID_GRANT, limit);
            }
        }
        return (Reason.OK, limit);
    }

    /// @dev Steps 9-12 against the grant's stored window, without writing: the debit's reason and, when it
    /// is OK, what `_applyDebit` records.
    function _previewDebit(bytes32 grantId, AssetLimit memory limit, address asset, uint256 amount)
        internal
        view
        returns (Reason, DebitPlan memory plan)
    {
        if (amount == 0 || amount > limit.maxPerCall || amount > type(uint192).max) {
            return (Reason.OVER_TX_CAP, plan);
        }

        AssetUsage storage u = _usage[grantId][asset];
        (uint64 head, uint256 evicted) = _expiredPrefix(u, _grants[grantId].windowSeconds);
        uint64 tail = u.tail;
        uint256 windowSpent = u.windowSpent - evicted;

        if (windowSpent >= limit.maxPerWindow || amount > limit.maxPerWindow - windowSpent) {
            return (Reason.OVER_WINDOW_CAP, plan);
        }
        uint256 spent = u.spent;
        if (spent >= limit.maxTotal || amount > limit.maxTotal - spent) {
            return (Reason.OVER_CUMULATIVE_CAP, plan);
        }
        if (tail - head == MAX_LIVE_DEBITS) return (Reason.WINDOW_FULL, plan);

        plan = DebitPlan({head: head, tail: tail, windowSpent: windowSpent, spent: spent});
        return (Reason.OK, plan);
    }

    /// @dev Records a debit `_previewDebit` passed, dropping the expired debits it found.
    function _applyDebit(bytes32 grantId, address asset, uint256 amount, DebitPlan memory plan) internal {
        AssetUsage storage u = _usage[grantId][asset];
        u.ring[plan.tail % MAX_LIVE_DEBITS] = _pack(uint64(block.timestamp), amount);
        u.head = plan.head;
        u.tail = plan.tail + 1;
        u.windowSpent = plan.windowSpent + amount;
        u.spent = plan.spent + amount;
        u.calls += 1;
    }

    /// @dev Steps 9-12 and the write, for a derived contract that has settled steps 1-8 itself: reverts with
    /// the failing reason, else records the debit. The window is always the grant's stored window.
    function _debit(bytes32 grantId, AssetLimit memory limit, address asset, uint256 amount) internal {
        (Reason reason, DebitPlan memory plan) = _previewDebit(grantId, limit, asset, amount);
        if (reason != Reason.OK) revert SpendGrantError(reason);
        _applyDebit(grantId, asset, amount, plan);
    }

    /// @dev The first unexpired ring position and the sum of the expired debits before it. Timestamps are
    /// appended in order, so expired debits not yet evicted are a prefix.
    function _expiredPrefix(AssetUsage storage u, uint64 windowSeconds)
        internal
        view
        returns (uint64 head, uint256 expiredAmount)
    {
        head = u.head;
        uint64 tail = u.tail;
        while (head < tail) {
            (uint64 time, uint256 amount) = _unpack(u.ring[head % MAX_LIVE_DEBITS]);
            if (_live(time, windowSeconds)) break;
            expiredAmount += amount;
            unchecked {
                ++head;
            }
        }
    }

    /// @dev The least of the window room, the lifetime room, the room left in the live-debit bound (each
    /// debit at most `min(maxPerCall, type(uint192).max)`), the balance and the allowance (0 when unknown).
    function _spendable(GrantState memory s) internal pure returns (uint256 v) {
        v = s.maxPerWindow > s.windowSpent ? s.maxPerWindow - s.windowSpent : 0;
        uint256 lifetime = s.maxTotal > s.spent ? s.maxTotal - s.spent : 0;
        if (lifetime < v) v = lifetime;
        uint256 perDebit = s.maxPerCall < type(uint192).max ? s.maxPerCall : type(uint192).max;
        // At most 1024 * (2^192 - 1): no overflow.
        uint256 slots = (MAX_LIVE_DEBITS - s.liveDebits) * perDebit;
        if (slots < v) v = slots;
        if (s.balance < v) v = s.balance;
        if (s.allowance < v) v = s.allowance;
    }

    /// @dev A STATICCALL with a fixed stipend that copies at most one word back; known iff it succeeds and
    /// returns exactly 32 bytes. Reverts when the caller left too little gas for the stipend, so that
    /// "unknown" always means the asset misbehaved.
    function _read(address token, bytes memory data) internal view returns (uint256 value, bool known) {
        if (gasleft() < READ_GAS_REQUIRED) revert InsufficientGas();
        bool ok;
        uint256 size;
        assembly ("memory-safe") {
            ok := staticcall(READ_GAS, token, add(data, 32), mload(data), 0, 32)
            size := returndatasize()
            value := mload(0)
        }
        if (!ok || size != 32) return (0, false);
        return (value, true);
    }

    /// @dev Writes the terms `update` may change, replacing the whole asset list.
    function _setTerms(Grant storage g, SpendGrant calldata terms) internal {
        g.recipientMode = terms.recipientMode;
        g.recipient = terms.recipient;
        g.validAfter = terms.validAfter;
        g.validUntil = terms.validUntil;
        g.updatedAt = uint64(block.timestamp);
        delete g.assets;
        uint256 n = terms.assets.length;
        for (uint256 i = 0; i < n; i++) {
            AssetLimit calldata a = terms.assets[i];
            g.assets.push(AssetLimit(a.asset, a.maxPerCall, a.maxPerWindow, a.maxTotal));
        }
    }

    /// @dev The stored terms as a `SpendGrant`: registration salt, `assetCombine` 0. All zero for an unknown id.
    function _terms(Grant storage g) internal view returns (SpendGrant memory t) {
        t.principal = g.principal;
        t.delegate = g.delegate;
        t.recipientMode = g.recipientMode;
        t.recipient = g.recipient;
        t.windowSeconds = g.windowSeconds;
        t.assets = g.assets;
        t.validAfter = g.validAfter;
        t.validUntil = g.validUntil;
        t.salt = g.salt;
    }

    /// @dev Entries `[offset, min(offset + limit, total))` of `list`, computed without overflow for any limit.
    function _page(bytes32[] storage list, uint256 offset, uint256 limit)
        internal
        view
        returns (bytes32[] memory page, uint256 total)
    {
        total = list.length;
        if (offset >= total || limit == 0) return (new bytes32[](0), total);
        uint256 end = limit > total - offset ? total : offset + limit;
        page = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = list[i];
        }
    }

    function _assertStructure(SpendGrant calldata m) internal pure {
        if (m.principal == address(0) || m.delegate == address(0) || m.delegate == m.principal) {
            revert SpendGrantError(Reason.INVALID_GRANT);
        }
        if (m.recipientMode > 1 || m.assetCombine != 0) revert SpendGrantError(Reason.INVALID_GRANT);
        if (m.recipientMode == 0) {
            if (m.recipient == address(0) || m.recipient == m.principal) revert SpendGrantError(Reason.INVALID_GRANT);
        } else if (m.recipient != address(0)) {
            revert SpendGrantError(Reason.INVALID_GRANT);
        }
        if (m.windowSeconds == 0 || m.validAfter >= m.validUntil) revert SpendGrantError(Reason.INVALID_GRANT);

        uint256 n = m.assets.length;
        if (n == 0 || n > MAX_ASSETS) revert SpendGrantError(Reason.INVALID_GRANT);

        uint160 prev;
        for (uint256 i = 0; i < n; i++) {
            AssetLimit calldata a = m.assets[i];
            uint160 key = uint160(a.asset);
            if (i > 0 && key <= prev) revert SpendGrantError(Reason.INVALID_GRANT);
            prev = key;
            if (a.maxPerCall == 0 || a.maxPerWindow == 0 || a.maxTotal == 0) {
                revert SpendGrantError(Reason.INVALID_GRANT);
            }
            if (a.maxPerCall > a.maxPerWindow || a.maxPerWindow > a.maxTotal) {
                revert SpendGrantError(Reason.INVALID_GRANT);
            }
            if (a.asset == address(0)) revert SpendGrantError(Reason.INVALID_GRANT);
        }
    }

    /// @dev The registration rule: every spend rejects a payee that is this registry, the executor, or the
    /// asset spent, so a fixed recipient equal to the registry or the executor can never be paid, and one equal
    /// to a listed asset can never be paid in that asset, which `grantState` would still show as spendable.
    function _assertRegistrable(SpendGrant calldata m) internal view {
        if (m.recipientMode != 0) return;
        address r = m.recipient;
        if (r == address(this) || r == EXECUTOR) revert SpendGrantError(Reason.INVALID_GRANT);
        uint256 n = m.assets.length;
        for (uint256 i = 0; i < n; i++) {
            if (m.assets[i].asset == r) revert SpendGrantError(Reason.INVALID_GRANT);
        }
    }

    function _live(uint64 stamped, uint64 windowSeconds) internal view returns (bool) {
        uint256 ts = block.timestamp;
        uint256 s = uint256(stamped);
        if (ts < s) return true;
        return (ts - s) < uint256(windowSeconds);
    }

    /// @dev Packs a ring slot: time in the high 64 bits, amount (fits uint192) in the low 192 bits.
    function _pack(uint64 time, uint256 amount) internal pure returns (uint256) {
        return (uint256(time) << AMOUNT_BITS) | amount;
    }

    function _unpack(uint256 word) internal pure returns (uint64 time, uint256 amount) {
        time = uint64(word >> AMOUNT_BITS);
        amount = uint256(uint192(word));
    }
}
