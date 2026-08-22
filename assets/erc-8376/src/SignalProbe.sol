// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC20} from "./IERC20.sol";
import {Powers} from "./LaunchAbuseTypes.sol";

/// @title On-chain derivation of the signals that can be read from chain state.
/// @notice Reduces what an off-chain detector must be trusted for. Every value
///         produced here is independently recomputable by anyone, which is the
///         precondition for a detector bond to be enforceable.
/// @dev Not all ten signals are derivable on-chain. Funding-ancestry clustering
///      (`sniperConcentration`, `insiderAllocationShare`) requires historical
///      graph traversal and remains an off-chain responsibility.
library SignalProbe {
    uint256 internal constant BPS = 10_000;
    /// @dev SCSTG "Detecting Unbounded Loops": these iterate a caller-supplied
    ///      array. Capped so a probe called inside a transaction cannot be made
    ///      to exhaust gas by passing an arbitrarily long list.
    uint256 internal constant MAX_ADDRESSES = 32;

    /// @notice Resolve a proxy to the code that actually runs.
    /// @dev A contract cannot read another contract's storage, so the EIP-1967
    ///      slots are not readable from here: an off-chain detector reads them
    ///      with `eth_getStorageAt`. On-chain, resolution is limited to what the
    ///      bytecode or an exposed getter reveals.
    ///
    ///      `isProxy` is returned even when resolution fails, because failing to
    ///      resolve is itself the finding. Code that can be swapped is
    ///      upgradeable whether or not we can read today's implementation, and
    ///      reporting an unresolvable proxy as powerless is the one error that
    ///      must not happen: it would mark the most dangerous case clean.
    /// @dev The `staticcall` probing an optional `implementation()` getter cannot
    ///      modify state, and its failure is handled as "unresolved" rather than
    ///      propagated. A high-level call would revert on the common case being
    ///      detected: a contract that does not implement the function.
    // slither-disable-next-line low-level-calls
    function implementationOf(address target)
        internal
        view
        returns (address impl, bool isProxy, bool resolved)
    {
        bytes memory code = target.code;
        if (code.length == 0) return (target, false, true);

        // EIP-1167: 363d3d373d3d3d363d73 <20 bytes> 5af43d82803e903d91602b57fd5bf3
        if (code.length == 45 && code[0] == 0x36 && code[1] == 0x3d && code[9] == 0x73) {
            uint160 addr = 0;
            for (uint256 i = 0; i < 20; ++i) {
                addr = (addr << 8) | uint160(uint8(code[10 + i]));
            }
            return (address(addr), true, true);
        }

        // A conventionally exposed getter, as most upgradeable proxies provide.
        (bool ok, bytes memory ret) =
            target.staticcall(abi.encodeWithSignature("implementation()"));
        if (ok && ret.length >= 32) {
            address a = abi.decode(ret, (address));
            if (a != address(0) && a.code.length > 0) return (a, true, true);
        }

        // Otherwise: does it delegatecall at all? A contract that delegates is
        // a proxy whose target we cannot see from here, whatever its size. The
        // size test this replaces read every proxy above a kilobyte as an
        // ordinary contract and reported it as having no privileged powers,
        // which is the strongest possible statement about the code least
        // possible to examine.
        if (_hasDelegateCall(code)) {
            return (address(0), true, false);
        }

        return (target, false, true);
    }

    /// @dev Delegation anywhere in the runtime, walked as opcodes from the
    ///      start so PUSH immediates are not mistaken for instructions. A raw
    ///      byte scan reports any 0xf4 sitting inside PUSH data and marks
    ///      ordinary contracts as upgradeable proxies; skipping the immediates
    ///      is what makes the answer mean anything.
    ///
    ///      No region is skipped on the subject's say-so, and the several
    ///      attempts to skip one are why. The length, the header and every byte
    ///      that would justify skipping a trailing section are written by the
    ///      party under examination, so each test of whether a region "is
    ///      metadata" was a test the subject could pass by construction: name a
    ///      length, place a CBOR header, avoid whichever opcode the last
    ///      version looked for. Every such rule bought a smaller scan at the
    ///      price of letting the token choose what went unread, and an unread
    ///      region reported as clean is the one error this signal must not make.
    ///
    ///      `_unreachableRegion` skips a region on a different footing: not that it
    ///      is metadata, but that it cannot execute. That is a property of the
    ///      bytes rather than a claim about them, and a token that arranges for
    ///      the region to be reachable is a token whose region gets walked.
    function _hasDelegateCall(bytes memory code) private pure returns (bool) {
        uint256 region = _unreachableRegion(code);
        uint256 i = 0;
        bool ended = false; // did the instruction just decoded end execution
        while (i < code.length) {
            // The walk itself decides reachability. Arriving at the region on an
            // instruction boundary, with execution already ended, is the only
            // way to stop early: a body ending PUSH1 0x00 arrives here with
            // `ended` false, because the 0x00 was an immediate and never ran.
            if (i == region && ended) return false;

            uint8 op = uint8(code[i]);
            // CALLCODE runs foreign code against this contract's own storage.
            // For everything this signal is for, that is delegation.
            if (op == 0xf4 || op == 0xf2) return true; // DELEGATECALL, CALLCODE

            ended =
                op == 0x00 || // STOP
                op == 0x56 || // JUMP
                op == 0xf3 || // RETURN
                op == 0xfd || // REVERT
                op == 0xfe || // INVALID
                op == 0xff;   // SELFDESTRUCT

            if (op >= 0x60 && op <= 0x7f) i += uint256(op) - 0x5f; // skip PUSH data
            ++i;
        }
        return false;
    }

    /// @dev The start of a trailing region that cannot execute, or the length of
    ///      the code where there is none. Nothing here is taken on the subject's
    ///      word. Solidity announces its CBOR metadata with a two-byte length
    ///      the subject writes and could lie about, so the length locates a
    ///      candidate and settles nothing.
    ///
    ///      Two ways in have to be closed. A region holding no `JUMPDEST` cannot
    ///      be jumped into, which is decided here. Whether execution can fall
    ///      into it is decided by the caller's walk instead, because it is the
    ///      walk that knows whether the byte before the region was an
    ///      instruction or a PUSH immediate. Reading that byte directly is the
    ///      bypass this file has already been through: a body ending PUSH1 0x00
    ///      reads as ending in STOP, and everything after it goes unread.
    ///
    ///      This is narrower than the trims the whole-runtime scan was right to
    ///      refuse, and it is confined to delegation. A selector only needs to
    ///      sit in a region as data, four bytes at a time, so `_scan` still
    ///      reads every byte. An opcode has to run to matter, and unreachable
    ///      bytes never run. What the old behavior cost was not an over-reported
    ///      power, which a detector must corroborate anyway; it was reporting an
    ///      ordinary token as a proxy whose code could not be seen, which blanks
    ///      `privilegedPowers` outright. That fired on roughly one contract in
    ///      fourteen here, moved whenever an unrelated source file changed, and
    ///      fell on exactly the honest tokens the signal exists to clear.
    function _unreachableRegion(bytes memory code) private pure returns (uint256) {
        uint256 n = code.length;
        if (n < 4) return n;

        uint256 len = (uint256(uint8(code[n - 2])) << 8) | uint256(uint8(code[n - 1]));
        if (len == 0 || len + 3 > n) return n;
        uint256 start = n - 2 - len;

        // A CBOR map header, as every Solidity version writes. Anything else is
        // not the region this is about, and gets no benefit of the doubt.
        uint8 header = uint8(code[start]);
        if (header < 0xa1 || header > 0xbf) return n;

        // One valid destination anywhere in it is enough to make it reachable.
        for (uint256 i = start; i < n; ++i) {
            if (uint8(code[i]) == 0x5b) return n; // JUMPDEST
        }

        return start;
    }

    /// @notice Whether `selector` appears anywhere in the runtime bytecode.
    /// @dev A heuristic, and stated as one. It sees selectors a contract
    ///      dispatches on, so it can report a power that is present but
    ///      permanently disabled. Detectors MUST treat a positive as grounds to
    ///      look, not as proof.
    ///
    ///      The four bytes are matched wherever they sit, rather than only
    ///      behind a PUSH4. Keying on the instruction meant `PUSH5` with a
    ///      leading zero pushed the same value and read as absent, and a
    ///      dispatcher could keep its constants as data and `CODECOPY` them in.
    ///      A selector is recognisable as itself; how it reaches the stack is
    ///      the author's choice and not evidence of anything.
    function hasSelector(address target, bytes4 selector) internal view returns (bool) {
        bytes memory code = target.code;
        if (code.length < 4) return false;

        bytes1 b0 = selector[0];
        for (uint256 i = 0; i + 3 < code.length; ++i) {
            if (code[i] != b0) continue;
            if (
                code[i + 1] == selector[1] &&
                code[i + 2] == selector[2] &&
                code[i + 3] == selector[3]
            ) return true;
        }
        return false;
    }

    /// @notice Derive the `privilegedPowers` bitmask, following proxies.
    /// @return mask the powers found
    /// @return exact false when the scan could not see all the code that runs,
    ///         so a consumer knows the absence of a bit is not evidence of its
    ///         absence in fact
    function powersOf(address token) internal view returns (uint16 mask, bool exact) {
        (address impl, bool isProxy, bool resolved) = implementationOf(token);

        // Upgradeability is a power in its own right: whoever can swap the code
        // can grant themselves every other power later.
        if (isProxy) mask |= Powers.UPGRADE;

        mask |= _scan(token);
        if (isProxy && resolved && impl != token && impl != address(0)) {
            mask |= _scan(impl);
        }

        // Nothing is skipped, so the only thing that can hide code from this
        // scan is a proxy whose implementation could not be resolved.
        exact = !isProxy || resolved;
    }

    /// @notice Bitmask form for the signal vector.
    /// @dev Returns the unavailability sentinel when the scan was not exact, so
    ///      the evaluator excludes the signal instead of scoring an unreadable
    ///      contract as clean.
    function privilegedPowers(address token) internal view returns (uint16) {
        (uint16 mask, bool exact) = powersOf(token);
        return exact ? mask : type(uint16).max;
    }

    /// @dev Single pass over the bytecode. Scanning once per selector meant
    ///      eight traversals of up to 24KB per contract, and sixteen when a
    ///      proxy was followed, which is a gas-griefing surface for any caller
    ///      that invokes this in a transaction rather than a static call.
    function _scan(address target) private view returns (uint16 mask) {
        bytes memory code = target.code;
        if (code.length < 5) return 0;

        bytes4[8] memory sels = [
            bytes4(keccak256("mint(address,uint256)")),
            bytes4(keccak256("pause()")),
            bytes4(keccak256("blacklist(address)")),
            bytes4(keccak256("setFee(uint256)")),
            bytes4(keccak256("upgradeTo(address)")),
            bytes4(keccak256("seize(address,uint256)")),
            bytes4(keccak256("setMaxTx(uint256)")),
            bytes4(keccak256("setExempt(address,bool)"))
        ];
        uint16[8] memory bits = [
            Powers.MINT, Powers.PAUSE, Powers.BLACKLIST, Powers.FEE,
            Powers.UPGRADE, Powers.SEIZE, Powers.LIMITS, Powers.EXEMPT
        ];

        // Every byte, and the constant rather than the instruction carrying it.
        // A four-byte sequence occurring by chance in a few kilobytes is
        // vanishingly unlikely; a selector the scan declines to look at is a
        // power reported absent.
        for (uint256 i = 0; i + 3 < code.length; ++i) {
            bytes1 b = code[i];
            for (uint256 k = 0; k < 8; ++k) {
                if (mask & bits[k] != 0) continue;
                if (
                    b == sels[k][0] && code[i + 1] == sels[k][1] &&
                    code[i + 2] == sels[k][2] && code[i + 3] == sels[k][3]
                ) { mask |= bits[k]; break; }
            }
        }
    }

    /// @notice Share of LP supply held at lock or burn addresses, in bps.
    /// @dev Protective signal: a high value is good. Returns the unavailability
    ///      sentinel when supply is zero rather than implying full protection.
    function lockedShare(address lpToken, address[] memory sinks)
        internal
        view
        returns (uint16)
    {
        require(sinks.length <= MAX_ADDRESSES, "too many sinks");
        uint256 supply = IERC20(lpToken).totalSupply();
        if (supply == 0) return type(uint16).max;

        uint256 held = 0;
        for (uint256 i = 0; i < sinks.length; ++i) {
            held += IERC20(lpToken).balanceOf(sinks[i]);
        }
        return toBps(held, supply);
    }

    /// @notice Share of pool liquidity held at lock or burn addresses, in bps,
    ///         where positions are non-fungible and there is no supply to divide.
    /// @dev Same protective polarity as `lockedShare`, and the same sentinel on
    ///      an empty pool: zero would assert that liquidity was measured and
    ///      none of it was locked. More locked than total is incoherent input
    ///      rather than full protection, so it reads as unavailable too.
    function lockedLiquidityShare(uint256 lockedLiquidity, uint256 totalLiquidity)
        internal
        pure
        returns (uint16)
    {
        if (totalLiquidity == 0) return type(uint16).max;
        if (lockedLiquidity > totalLiquidity) return type(uint16).max;
        return toBps(lockedLiquidity, totalLiquidity);
    }

    /// @notice Share of a deployer's allocation that has left its wallets, in bps.
    function sellRatio(address token, address[] memory deployerWallets, uint256 allocated)
        internal
        view
        returns (uint16)
    {
        require(deployerWallets.length <= MAX_ADDRESSES, "too many wallets");
        if (allocated == 0) return type(uint16).max;

        uint256 remaining = 0;
        for (uint256 i = 0; i < deployerWallets.length; ++i) {
            remaining += IERC20(token).balanceOf(deployerWallets[i]);
        }
        if (remaining >= allocated) return 0;
        return toBps(allocated - remaining, allocated);
    }

    /// @notice Share of peak liquidity withdrawn, in bps.
    function liquidityRemoved(uint256 peak, uint256 current) internal pure returns (uint16) {
        if (peak == 0) return type(uint16).max;
        if (current >= peak) return 0;
        return toBps(peak - current, peak);
    }

    function toBps(uint256 part, uint256 whole) internal pure returns (uint16) {
        if (whole == 0) return type(uint16).max;
        uint256 v = (part * BPS) / whole;
        return uint16(v > BPS ? BPS : v);
    }
}
