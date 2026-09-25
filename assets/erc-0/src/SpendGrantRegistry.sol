// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {
    AssetLimit,
    IERC1271,
    ISpendGrantRegistry,
    SpendGrant,
    SpendGrantError,
    MAX_ASSETS,
    MAX_LIVE_DEBITS,
    NATIVE,
    Reason
} from "./SpendGrantTypes.sol";
import {SpendGrantHash} from "./SpendGrantHash.sol";

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

    constructor(address executor_) {
        EXECUTOR = executor_;
    }

    function executor() external view returns (address) {
        return EXECUTOR;
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

    function consume(
        SpendGrant calldata grant,
        bytes calldata grantSignature,
        address asset,
        uint256 amount,
        address recipient
    ) external {
        if (msg.sender != EXECUTOR) revert SpendGrantError(Reason.UNAUTHORIZED_EXECUTOR);

        _assertStructure(grant);

        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(this), grant);
        if (!_validSignature(grant.principal, grantHash, grantSignature)) {
            revert SpendGrantError(Reason.BAD_SIGNATURE);
        }

        if (block.timestamp < grant.validAfter) revert SpendGrantError(Reason.NOT_YET_VALID);
        if (block.timestamp >= grant.validUntil) revert SpendGrantError(Reason.EXPIRED);
        if (revoked[grant.principal][grantHash]) revert SpendGrantError(Reason.REVOKED);

        if (grant.recipientMode == 0) {
            if (recipient != grant.recipient) revert SpendGrantError(Reason.WRONG_RECIPIENT);
        }

        _debit(grantHash, grant.windowSeconds, _asset(grant, asset), asset, amount, recipient);
    }

    /// @dev `windowSeconds` must equal the value already signed into this grant (what `consume`
    /// passes through from `grant.windowSeconds`). It is only written to `_windowSeconds` on the
    /// first debit for `grantHash`; `rollingUsage` always reads that stored value, so a caller
    /// (e.g. a derived contract calling `_debit` directly) that passes a different value here
    /// makes `rollingUsage`/eviction disagree with what `consume` would have done.
    function _debit(
        bytes32 grantHash,
        uint64 windowSeconds,
        AssetLimit memory limit,
        address asset,
        uint256 amount,
        address recipient
    ) internal {
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

        emit GrantConsumed(grantHash, asset, amount, recipient);
    }

    function _assertStructure(SpendGrant calldata m) internal view {
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
            if (a.asset != NATIVE && a.asset.code.length == 0) revert SpendGrantError(Reason.INVALID_GRANT);
        }
    }

    function _asset(SpendGrant calldata m, address asset) internal pure returns (AssetLimit calldata limit) {
        uint256 n = m.assets.length;
        for (uint256 i = 0; i < n; i++) {
            if (m.assets[i].asset == asset) return m.assets[i];
        }
        revert SpendGrantError(Reason.WRONG_ASSET);
    }

    /// @dev A principal with a 23-byte EIP-7702 delegation designator (0xef0100 || implementation)
    /// tries strict ECDSA first (the designator authorizes the EOA's own key), then falls back to
    /// ERC-1271 against the delegate implementation. Any other code-bearing principal is ERC-1271
    /// only; a principal with no code is ECDSA only.
    function _validSignature(address principal, bytes32 digest, bytes calldata sig) internal view returns (bool) {
        uint256 codeLen = principal.code.length;
        if (codeLen == 0) {
            return _validEcdsaSignature(principal, digest, sig);
        }
        if (codeLen == 23 && _isDelegationDesignator(principal.code)) {
            if (_validEcdsaSignature(principal, digest, sig)) return true;
        }
        (bool ok, bytes memory ret) = principal.staticcall(abi.encodeCall(IERC1271.isValidSignature, (digest, sig)));
        if (!ok || ret.length != 32) return false;
        return abi.decode(ret, (bytes32)) == bytes32(IERC1271.isValidSignature.selector);
    }

    /// @dev EIP-7702 delegation designator: exactly 23 bytes, 0xef0100 prefix. Caller must have
    /// already checked code.length == 23 via EXTCODESIZE before paying for this EXTCODECOPY.
    function _isDelegationDesignator(bytes memory code) internal pure returns (bool) {
        return code[0] == 0xef && code[1] == 0x01 && code[2] == 0x00;
    }

    function _validEcdsaSignature(address principal, bytes32 digest, bytes calldata sig) internal pure returns (bool) {
        if (sig.length != 65) return false;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v != 27 && v != 28) return false;
        if (uint256(s) == 0 || uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return false;
        }
        address recovered = ecrecover(digest, v, r, s);
        return recovered != address(0) && recovered == principal;
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
