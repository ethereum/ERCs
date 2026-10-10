// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {
    AssetLimit,
    ISpendGrantRegistry,
    SpendGrant,
    SpendGrantError,
    MAX_ASSETS,
    MAX_LIVE_DEBITS,
    NATIVE,
    Reason
} from "./SpendGrantTypes.sol";
import {SpendGrantHash} from "./SpendGrantHash.sol";
import {SpendGrantSignature} from "./SpendGrantSignature.sol";

contract SpendGrantRegistry is ISpendGrantRegistry {
    /// @dev Low bits of a ring slot hold the amount; the high 64 bits hold the timestamp.
    uint256 internal constant AMOUNT_BITS = 192;

    /// @dev Each ring slot packs `time (uint64) << 192 | amount (uint192)` into one storage word.
    struct AssetUsage {
        uint64 head;
        uint64 tail;
        uint64 calls;
        uint256 spent;
        uint256 windowSpent;
        uint256[MAX_LIVE_DEBITS] ring;
    }

    address internal immutable EXECUTOR;

    mapping(address => mapping(bytes32 => bool)) public revoked;
    mapping(bytes32 => mapping(address => AssetUsage)) internal _usage;
    mapping(bytes32 => uint64) internal _windowSeconds;

    error ZeroExecutor();

    constructor(address executor_) {
        if (executor_ == address(0)) revert ZeroExecutor();
        EXECUTOR = executor_;
    }

    function executor() external view returns (address) {
        return EXECUTOR;
    }

    /// @notice The `grantHash` this registry computes for `grant` on this chain: the value `consume`
    /// validates the signature over, keys usage on, and looks up in `revoked`. A wallet revokes this value
    /// rather than one it computed itself, because `revoke` cannot tell a wrong hash from a right one.
    function hashGrant(SpendGrant calldata grant) external view returns (bytes32) {
        return SpendGrantHash.digest(block.chainid, address(this), grant);
    }

    function revoke(bytes32 grantHash) external {
        if (revoked[msg.sender][grantHash]) return;
        revoked[msg.sender][grantHash] = true;
        emit GrantRevoked(msg.sender, grantHash);
    }

    function usage(bytes32 grantHash, address asset) external view returns (uint256 spent, uint256 calls) {
        AssetUsage storage u = _usage[grantHash][asset];
        return (u.spent, u.calls);
    }

    function rollingUsage(bytes32 grantHash, address asset) external view returns (uint256 spent, uint256 calls) {
        AssetUsage storage u = _usage[grantHash][asset];
        uint64 windowSeconds = _windowSeconds[grantHash];

        uint64 head = u.head;
        uint64 tail = u.tail;
        uint256 expiredAmount;
        uint256 expiredCount;
        while (head < tail) {
            (uint64 time, uint256 amount) = _unpack(u.ring[head % MAX_LIVE_DEBITS]);
            if (_live(time, windowSeconds)) break;
            expiredAmount += amount;
            unchecked {
                ++expiredCount;
                ++head;
            }
        }

        spent = u.windowSpent - expiredAmount;
        calls = uint256(tail - u.head) - expiredCount;
    }

    /// @notice Drops up to `maxCount` expired debits from the front of the ring for `(grantHash, asset)`.
    /// Anyone may call it. It changes nothing any check or view returns; it moves the cost of dropping
    /// expired debits, which would otherwise fall on the next `consume` all at once, into calls of a
    /// size the caller chooses.
    function evict(bytes32 grantHash, address asset, uint256 maxCount) external {
        AssetUsage storage u = _usage[grantHash][asset];
        uint64 windowSeconds = _windowSeconds[grantHash];

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

    /// @notice The oldest `min(maxCount, n)` of the `n` unexpired debits for `asset` under `grantHash`
    /// at this block, in recording order. `amounts[i]` counts against the window while
    /// `block.timestamp < expiresAt[i]`.
    function liveDebits(bytes32 grantHash, address asset, uint256 maxCount)
        external
        view
        returns (uint256[] memory expiresAt, uint256[] memory amounts)
    {
        AssetUsage storage u = _usage[grantHash][asset];
        uint64 windowSeconds = _windowSeconds[grantHash];

        uint64 head = u.head;
        uint64 tail = u.tail;
        // Timestamps are appended in order, so expired debits not yet evicted are a prefix.
        while (head < tail) {
            (uint64 time,) = _unpack(u.ring[head % MAX_LIVE_DEBITS]);
            if (_live(time, windowSeconds)) break;
            unchecked {
                ++head;
            }
        }

        uint256 n = tail - head;
        if (n > maxCount) n = maxCount;
        expiresAt = new uint256[](n);
        amounts = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            (uint64 time, uint256 amount) = _unpack(u.ring[(uint256(head) + i) % MAX_LIVE_DEBITS]);
            expiresAt[i] = uint256(time) + uint256(windowSeconds);
            amounts[i] = amount;
        }
    }

    /// @dev `authorizer` is the address the executor authenticated as authorizing this spend.
    /// Holding the grant and its signature is not authority: both are public after first use.
    function consume(
        SpendGrant calldata grant,
        bytes calldata grantSignature,
        address authorizer,
        address asset,
        uint256 amount,
        address recipient
    ) external {
        if (msg.sender != EXECUTOR) revert SpendGrantError(Reason.UNAUTHORIZED_EXECUTOR);
        if (authorizer != grant.delegate) revert SpendGrantError(Reason.UNAUTHORIZED_DELEGATE);

        _assertStructure(grant);

        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(this), grant);
        if (!_validSignature(grant.principal, grantHash, grantSignature)) {
            revert SpendGrantError(Reason.BAD_SIGNATURE);
        }

        if (block.timestamp < grant.validAfter) revert SpendGrantError(Reason.NOT_YET_VALID);
        if (block.timestamp >= grant.validUntil) revert SpendGrantError(Reason.EXPIRED);
        if (revoked[grant.principal][grantHash]) revert SpendGrantError(Reason.REVOKED);

        // The payee is never nothing, the principal, this registry, the executor, or the asset itself: the
        // first burns or misattributes, the second spends cap on a no-op, the rest strand the funds. This
        // applies to the argument even when a mode 0 grant signed one of them, so such a grant fails closed.
        if (
            recipient == address(0) || recipient == grant.principal || recipient == address(this)
                || recipient == EXECUTOR || recipient == asset
        ) {
            revert SpendGrantError(Reason.WRONG_RECIPIENT);
        }
        if (grant.recipientMode == 0 && recipient != grant.recipient) revert SpendGrantError(Reason.WRONG_RECIPIENT);

        AssetLimit calldata limit = _asset(grant, asset);
        // Only the asset being spent needs code, and code that is an EIP-7702 designator is an account, not
        // a token; an unrelated listing without code does not block the grant.
        if (asset != NATIVE) {
            uint256 codeLen = asset.code.length;
            if (codeLen == 0 || (codeLen == 23 && SpendGrantSignature.isDelegationDesignator(asset))) {
                revert SpendGrantError(Reason.INVALID_GRANT);
            }
        }

        _debit(grantHash, grant.windowSeconds, limit, asset, amount);
        emit GrantConsumed(grantHash, grant.principal, asset, amount, recipient);
    }

    /// @dev `windowSeconds` must equal the value already signed into this grant (what `consume`
    /// passes through from `grant.windowSeconds`). It is only written to `_windowSeconds` on the
    /// first debit for `grantHash`; `rollingUsage` and `liveDebits` always read that stored value, so a caller
    /// (e.g. a derived contract calling `_debit` directly) that passes a different value here
    /// makes those views and eviction disagree with what `consume` would have done.
    function _debit(bytes32 grantHash, uint64 windowSeconds, AssetLimit memory limit, address asset, uint256 amount)
        internal
    {
        if (amount == 0 || amount > limit.maxPerCall || amount > type(uint192).max) {
            revert SpendGrantError(Reason.OVER_TX_CAP);
        }

        if (_windowSeconds[grantHash] == 0) _windowSeconds[grantHash] = windowSeconds;

        AssetUsage storage u = _usage[grantHash][asset];

        uint64 head = u.head;
        uint64 tail = u.tail;
        uint256 windowSpent = u.windowSpent;
        uint256 evicted;
        while (head < tail) {
            (uint64 time, uint256 evictedAmount) = _unpack(u.ring[head % MAX_LIVE_DEBITS]);
            if (_live(time, windowSeconds)) break;
            evicted += evictedAmount;
            unchecked {
                ++head;
            }
        }
        windowSpent -= evicted;
        u.head = head;

        if (windowSpent >= limit.maxPerWindow || amount > limit.maxPerWindow - windowSpent) {
            revert SpendGrantError(Reason.OVER_WINDOW_CAP);
        }
        uint256 spent = u.spent;
        if (spent >= limit.maxTotal || amount > limit.maxTotal - spent) {
            revert SpendGrantError(Reason.OVER_CUMULATIVE_CAP);
        }
        if (tail - head == MAX_LIVE_DEBITS) revert SpendGrantError(Reason.WINDOW_FULL);

        u.ring[tail % MAX_LIVE_DEBITS] = _pack(uint64(block.timestamp), amount);
        u.tail = tail + 1;
        u.windowSpent = windowSpent + amount;
        u.spent = spent + amount;
        u.calls += 1;
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

    function _asset(SpendGrant calldata m, address asset) internal pure returns (AssetLimit calldata limit) {
        uint256 n = m.assets.length;
        for (uint256 i = 0; i < n; i++) {
            if (m.assets[i].asset == asset) return m.assets[i];
        }
        revert SpendGrantError(Reason.WRONG_ASSET);
    }

    /// @dev The Signatures rules, shared with executors through SpendGrantSignature: no code is strict
    /// ECDSA; an EIP-7702 designator tries the account's own key first, then ERC-1271; any other code
    /// is ERC-1271 only; the ERC-1271 call is a STATICCALL.
    function _validSignature(address principal, bytes32 digest, bytes calldata sig) internal view returns (bool) {
        return SpendGrantSignature.isValid(principal, digest, sig);
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
