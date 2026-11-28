// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {AssetLimit, MAX_LIVE_DEBITS, Reason, SpendGrantError} from "../src/SpendGrantTypes.sol";

/// @dev Test-only reference model: the ring of the previous registry (base 445bc54), copied verbatim
/// from `_debit`, `usage`, `rollingUsage`, `liveDebits`, `evict`, `_live`, `_pack`, `_unpack`, with the
/// window passed in as before. Used as an independent oracle for the new registry's ring.
contract OldRingOracle {
    uint256 internal constant AMOUNT_BITS = 192;

    struct AssetUsage {
        uint64 head;
        uint64 tail;
        uint64 calls;
        uint256 spent;
        uint256 windowSpent;
        uint256[MAX_LIVE_DEBITS] ring;
    }

    mapping(bytes32 => mapping(address => AssetUsage)) internal _usage;
    mapping(bytes32 => uint64) internal _windowSeconds;

    function debit(bytes32 grantHash, uint64 windowSeconds, AssetLimit memory limit, address asset, uint256 amount)
        external
    {
        _debit(grantHash, windowSeconds, limit, asset, amount);
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

    function liveDebits(bytes32 grantHash, address asset, uint256 maxCount)
        external
        view
        returns (uint256[] memory expiresAt, uint256[] memory amounts)
    {
        AssetUsage storage u = _usage[grantHash][asset];
        uint64 windowSeconds = _windowSeconds[grantHash];

        uint64 head = u.head;
        uint64 tail = u.tail;
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

    function _live(uint64 stamped, uint64 windowSeconds) internal view returns (bool) {
        uint256 ts = block.timestamp;
        uint256 s = uint256(stamped);
        if (ts < s) return true;
        return (ts - s) < uint256(windowSeconds);
    }

    function _pack(uint64 time, uint256 amount) internal pure returns (uint256) {
        return (uint256(time) << AMOUNT_BITS) | amount;
    }

    function _unpack(uint256 word) internal pure returns (uint64 time, uint256 amount) {
        time = uint64(word >> AMOUNT_BITS);
        amount = uint256(uint192(word));
    }
}
