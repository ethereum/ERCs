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
    Reason,
    WAD
} from "./SpendGrantTypes.sol";
import {SpendGrantHash} from "./SpendGrantHash.sol";

contract SpendGrantRegistry is ISpendGrantRegistry {
    struct Debit {
        uint64 time;
        uint256 amount;
        uint256 windowPieWad;
    }

    struct AssetUsage {
        uint256 spent;
        uint256 calls;
        Debit[] window;
    }

    address public immutable executor;

    mapping(address => mapping(bytes32 => bool)) public revoked;
    mapping(bytes32 => mapping(address => AssetUsage)) internal _usage;
    mapping(bytes32 => uint256) internal _lifetimePie;
    mapping(bytes32 => uint64) internal _windowSeconds;
    mapping(bytes32 => address[]) internal _touchedAssets;
    mapping(bytes32 => mapping(address => bool)) internal _touched;

    constructor(address executor_) {
        executor = executor_;
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
        return _rolling(_usage[grantHash][asset], _windowSeconds[grantHash]);
    }

    function pieUsed(bytes32 grantHash) external view returns (uint256 lifetimeWad, uint256 windowWad) {
        lifetimeWad = _lifetimePie[grantHash];
        windowWad = _windowPie(grantHash, _windowSeconds[grantHash]);
    }

    function consume(
        SpendGrant calldata grant,
        bytes calldata grantSignature,
        address asset,
        uint256 amount,
        address recipient
    ) external {
        if (msg.sender != executor) revert SpendGrantError(Reason.UNAUTHORIZED_EXECUTOR);

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

        AssetLimit calldata limit = _asset(grant, asset);

        if (amount == 0 || amount > limit.maxPerCall) revert SpendGrantError(Reason.OVER_TX_CAP);

        uint64 windowSeconds = grant.windowSeconds;
        if (_windowSeconds[grantHash] == 0) _windowSeconds[grantHash] = windowSeconds;

        AssetUsage storage u = _usage[grantHash][asset];
        _compact(u, windowSeconds);
        if (u.window.length >= MAX_LIVE_DEBITS) revert SpendGrantError(Reason.WINDOW_FULL);

        uint256 windowPieWad;
        if (grant.assetCombine == 0) {
            (uint256 rollingSpent,) = _rolling(u, windowSeconds);
            if (rollingSpent >= limit.maxPerWindow || amount > limit.maxPerWindow - rollingSpent) {
                revert SpendGrantError(Reason.OVER_WINDOW_CAP);
            }
            if (u.spent >= limit.maxTotal || amount > limit.maxTotal - u.spent) {
                revert SpendGrantError(Reason.OVER_CUMULATIVE_CAP);
            }
        } else {
            windowPieWad = _ceilWad(amount, limit.maxPerWindow);
            uint256 lifetimePieWad = _ceilWad(amount, limit.maxTotal);
            uint256 usedWindow = _windowPie(grantHash, windowSeconds);
            uint256 usedLifetime = _lifetimePie[grantHash];
            if (usedWindow >= WAD || windowPieWad > WAD - usedWindow) revert SpendGrantError(Reason.OVER_WINDOW_CAP);
            if (usedLifetime >= WAD || lifetimePieWad > WAD - usedLifetime) {
                revert SpendGrantError(Reason.OVER_CUMULATIVE_CAP);
            }
            _lifetimePie[grantHash] = usedLifetime + lifetimePieWad;
            _touch(grantHash, asset);
        }

        u.window.push(Debit({time: uint64(block.timestamp), amount: amount, windowPieWad: windowPieWad}));
        u.spent += amount;
        u.calls += 1;

        emit GrantConsumed(grantHash, asset, amount, recipient);
    }

    function _assertStructure(SpendGrant calldata m) internal view {
        if (m.principal == address(0) || m.delegate == address(0) || m.delegate == m.principal) {
            revert SpendGrantError(Reason.INVALID_GRANT);
        }
        if (m.recipientMode > 1 || m.assetCombine > 1) revert SpendGrantError(Reason.INVALID_GRANT);
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
            if (a.maxPerCall == 0 || a.maxPerWindow == 0 || a.maxTotal == 0) revert SpendGrantError(Reason.INVALID_GRANT);
            if (a.maxPerCall > a.maxPerWindow || a.maxPerWindow > a.maxTotal) {
                revert SpendGrantError(Reason.INVALID_GRANT);
            }
            if (a.asset != address(0) && a.asset.code.length == 0) revert SpendGrantError(Reason.INVALID_GRANT);
        }
    }

    function _asset(SpendGrant calldata m, address asset) internal pure returns (AssetLimit calldata limit) {
        uint256 n = m.assets.length;
        for (uint256 i = 0; i < n; i++) {
            if (m.assets[i].asset == asset) return m.assets[i];
        }
        revert SpendGrantError(Reason.WRONG_ASSET);
    }

    function _validSignature(address principal, bytes32 digest, bytes calldata sig) internal view returns (bool) {
        if (principal.code.length > 0) {
            (bool ok, bytes memory ret) =
                principal.staticcall(abi.encodeCall(IERC1271.isValidSignature, (digest, sig)));
            if (!ok || ret.length != 32) return false;
            return abi.decode(ret, (bytes32)) == bytes32(IERC1271.isValidSignature.selector);
        }
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

    function _compact(AssetUsage storage u, uint64 windowSeconds) internal {
        Debit[] storage window = u.window;
        uint256 n = window.length;
        uint256 w;
        for (uint256 i = 0; i < n; i++) {
            if (_live(window[i].time, windowSeconds)) {
                if (w != i) window[w] = window[i];
                unchecked {
                    ++w;
                }
            }
        }
        while (window.length > w) {
            window.pop();
        }
    }

    function _rolling(AssetUsage storage u, uint64 windowSeconds) internal view returns (uint256 spent, uint256 calls) {
        Debit[] storage window = u.window;
        uint256 n = window.length;
        for (uint256 i = 0; i < n; i++) {
            if (_live(window[i].time, windowSeconds)) {
                spent += window[i].amount;
                unchecked {
                    ++calls;
                }
            }
        }
    }

    function _windowPie(bytes32 grantHash, uint64 windowSeconds) internal view returns (uint256 windowWad) {
        address[] storage assets = _touchedAssets[grantHash];
        uint256 n = assets.length;
        for (uint256 i = 0; i < n; i++) {
            Debit[] storage window = _usage[grantHash][assets[i]].window;
            uint256 m = window.length;
            for (uint256 j = 0; j < m; j++) {
                if (_live(window[j].time, windowSeconds)) windowWad += window[j].windowPieWad;
            }
        }
    }

    function _touch(bytes32 grantHash, address asset) internal {
        if (_touched[grantHash][asset]) return;
        _touched[grantHash][asset] = true;
        _touchedAssets[grantHash].push(asset);
    }

    /// @dev ceil(amount * WAD / denom).
    function _ceilWad(uint256 amount, uint256 denom) internal pure returns (uint256) {
        if (amount == 0) return 0;
        if (denom == 0) revert SpendGrantError(Reason.INVALID_GRANT);
        return _mulDivUp(amount, WAD, denom);
    }

    function _mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        uint256 rem = mulmod(x, y, d);
        uint256 lo;
        uint256 hi;
        assembly {
            lo := mul(x, y)
            let mm := mulmod(x, y, not(0))
            hi := sub(sub(mm, lo), lt(mm, lo))
            let borrow := lt(lo, rem)
            lo := sub(lo, rem)
            hi := sub(hi, borrow)
        }
        uint256 q = hi == 0 ? lo / d : _div512(lo, hi, d);
        if (rem == 0) return q;
        if (q == type(uint256).max) revert SpendGrantError(Reason.INVALID_GRANT);
        unchecked {
            return q + 1;
        }
    }

    /// @dev floor((hi * 2^256 + lo) / d) with hi < d so the quotient fits in uint256.
    function _div512(uint256 lo, uint256 hi, uint256 d) internal pure returns (uint256 z) {
        if (d == 0 || hi >= d) revert SpendGrantError(Reason.INVALID_GRANT);
        uint256 r = hi;
        for (uint256 i = 0; i < 256;) {
            uint256 bit = lo >> 255;
            lo <<= 1;
            z <<= 1;
            bool overflow = r > (type(uint256).max >> 1);
            unchecked {
                r = (r << 1) | bit;
            }
            if (overflow || r >= d) {
                unchecked {
                    r -= d;
                }
                z |= 1;
            }
            unchecked {
                ++i;
            }
        }
    }
}
