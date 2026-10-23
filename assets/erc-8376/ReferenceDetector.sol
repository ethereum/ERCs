// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IERC20Minimal {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/// @dev The twelve base signals, version 1. Basis points unless stated.
struct SignalVector {
    uint16 deployerSupplyShare;
    uint16 insiderAllocationShare;
    uint16 sniperConcentration;
    uint16 lpLockedShare;
    uint32 lpLockRemaining;
    uint16 liquidityRemoved;
    uint16 deployerSellRatio;
    uint16 proceedsWithdrawnShare;
    uint16 privilegedPowers;
    uint16 priorUpheldClaims;
    uint16 supplyInflation;
    uint16 washTradeRatio;
}

/// @title Reference detector, evaluator and guard for ERC-8376.
/// @notice Derives the chain-readable signals, scores a vector under a pattern
///         profile, and returns the containment action a venue acts on.
contract ReferenceDetector {
    uint16 internal constant NA16 = type(uint16).max;
    uint32 internal constant NA32 = type(uint32).max;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant N = 12;

    enum ContainmentAction { None, Flag, ExtendSchedule, SuspendRelease, Freeze, Refund }

    uint256 internal constant I_LP_LOCK_REMAINING = 4;
    uint256 internal constant I_PRIVILEGED_POWERS = 8;
    uint8 internal constant ELEVATED_MAX = 60; // the top of the Elevated band

    // Activation thresholds, in SignalVector order. The privilegedPowers slot
    // carries this profile's mask rather than a magnitude, since the signal is
    // categorical: PATTERN_HARD_RUG masks mint, upgrade and seize.
    uint256[N] internal THRESHOLD = [
        uint256(3000), 1000, 2000, 8000, 30 days, 2000, 3000, 5000,
        MINT | UPGRADE | SEIZE, 1, 1000, 3000
    ];
    // Signals describing an action the deployer took, as distinct from a
    // capability its code retains or a protection nobody arranged.
    bool[N] internal CONDUCT = [
        false, true, true, false, false, true, true, true, false, true, true, true
    ];
    // True where a high value is protective rather than adverse.
    bool[N] internal PROTECTIVE = [
        false, false, false, true, true, false, false, false, false, false, false, false
    ];
    // PATTERN_HARD_RUG: weights sum to 100. Zero excludes the signal.
    uint256 internal constant PROFILE_WEIGHT = 100;
    uint256[N] internal HARD_RUG = [uint256(0), 0, 0, 20, 10, 30, 10, 15, 10, 5, 0, 0];

    /// @notice Privileged powers, by effect rather than by function name.
    ///         The eight the bit table assigns, in its order.
    uint16 internal constant MINT = 0x0001;
    uint16 internal constant PAUSE = 0x0002;
    uint16 internal constant BLACKLIST = 0x0004;
    uint16 internal constant FEE = 0x0008;
    uint16 internal constant UPGRADE = 0x0010;
    uint16 internal constant SEIZE = 0x0020;
    uint16 internal constant LIMITS = 0x0040;
    uint16 internal constant EXEMPT = 0x0080;

    // --- Signal derivation ---------------------------------------------------

    /// @notice Share of a token's supply held by the deployer's wallets, in bps.
    function supplyShare(address token, address[] calldata wallets)
        public
        view
        returns (uint16)
    {
        uint256 supply = IERC20Minimal(token).totalSupply();
        if (supply == 0) return NA16;
        uint256 held;
        for (uint256 i = 0; i < wallets.length; ++i) {
            held += IERC20Minimal(token).balanceOf(wallets[i]);
        }
        return toBps(held, supply);
    }

    /// @notice Share of pool liquidity locked or burned, in bps.
    /// @dev A fungible liquidity token decides the value where one exists.
    ///      Otherwise the amounts are supplied, as a non-fungible position has
    ///      no supply to divide. An empty pool is unavailable, never zero.
    function lockedShare(
        address lpToken,
        address[] calldata sinks,
        uint256 lockedLiquidity,
        uint256 totalLiquidity
    ) public view returns (uint16) {
        if (lpToken != address(0)) {
            uint256 supply = IERC20Minimal(lpToken).totalSupply();
            if (supply == 0) return NA16;
            uint256 held;
            for (uint256 i = 0; i < sinks.length; ++i) {
                held += IERC20Minimal(lpToken).balanceOf(sinks[i]);
            }
            return toBps(held, supply);
        }
        if (totalLiquidity == 0 || lockedLiquidity > totalLiquidity) return NA16;
        return toBps(lockedLiquidity, totalLiquidity);
    }

    /// @notice Share of peak pool liquidity withdrawn during the window, in bps.
    function liquidityRemoved(uint256 peak, uint256 current) public pure returns (uint16) {
        if (peak == 0) return NA16;
        if (current >= peak) return 0;
        return toBps(peak - current, peak);
    }

    /// @notice Privileged functions callable by the deployer at window end.
    /// @dev Every bit the table assigns is scanned for, in the token's code and
    ///      in its implementation where it proxies, and upgradeability is itself
    ///      a power. Where a proxy cannot be followed the signal is unavailable:
    ///      an absent bit would read as an assurance, which is the one answer
    ///      this signal must not give. A positive is grounds to look rather than
    ///      proof, and the caller MUST corroborate before acting on it.
    /// @dev Selector names are conventional. A token exposing the same power
    ///      under another name is not reported, so this identifies a power it
    ///      recognises and never the absence of one.
    function privilegedPowers(address token) public view returns (uint16) {
        (address impl, bool isProxy, bool resolved) = implementationOf(token);

        uint16 mask = scanCode(token);
        if (isProxy) {
            // Delegation is upgradeability: whoever chooses the code that runs
            // can grant themselves every other power later. That holds whether
            // or not the implementation could be resolved, so the bit is set
            // either way and only the implementation's own selectors are lost.
            mask |= UPGRADE;
            if (resolved && impl != token && impl != address(0)) mask |= scanCode(impl);
        }
        return mask;
    }

    /// @dev EIP-1167 by its exact runtime shape, then the conventional getter.
    ///      Neither is exhaustive, so delegation decides the rest.
    function implementationOf(address target)
        public
        view
        returns (address impl, bool isProxy, bool resolved)
    {
        bytes memory code = target.code;
        if (code.length == 0) return (target, false, true);

        // 363d3d373d3d3d363d73 <20 bytes> 5af43d82803e903d91602b57fd5bf3
        if (code.length == 45 && code[0] == 0x36 && code[1] == 0x3d && code[9] == 0x73) {
            uint160 addr = 0;
            for (uint256 i = 0; i < 20; ++i) {
                addr = (addr << 8) | uint160(uint8(code[10 + i]));
            }
            return (address(addr), true, true);
        }

        (bool ok, bytes memory ret) =
            target.staticcall(abi.encodeWithSignature("implementation()"));
        if (ok && ret.length == 32) {
            address a = abi.decode(ret, (address));
            if (a != address(0)) return (a, true, true);
        }

        // Neither shape matched. Code that delegates is still a proxy, and
        // reporting it as a plain token would report its implementation's
        // powers as absent, which is the one answer this signal must not give.
        if (delegates(code)) return (address(0), true, false);

        return (target, false, true);
    }

    /// @dev Delegation anywhere in the runtime, walked as opcodes so that PUSH
    ///      immediates are not mistaken for instructions.
    function delegates(bytes memory code) public pure returns (bool) {
        uint256 region = unreachableRegion(code);
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
    ///      the code where there is none. The declared length locates a
    ///      candidate and settles nothing, since the subject writes it. A region
    ///      holding no `JUMPDEST` cannot be jumped into, which is decided here;
    ///      whether execution falls into it is decided by the walk above, which
    ///      knows whether the preceding byte was an instruction or an immediate.
    ///      Only delegation skips the region, because an opcode has to run to
    ///      matter; `scanCode` still reads every byte, since a selector only has
    ///      to sit there as data.
    function unreachableRegion(bytes memory code) public pure returns (uint256) {
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

    /// @dev Every byte, and the constant rather than the instruction carrying
    ///      it. A four-byte sequence occurring by chance in a few kilobytes is
    ///      vanishingly unlikely; a selector the scan declines to look at is a
    ///      power reported absent.
    function scanCode(address target) internal view returns (uint16 mask) {
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
        uint16[8] memory bits =
            [MINT, PAUSE, BLACKLIST, FEE, UPGRADE, SEIZE, LIMITS, EXEMPT];

        for (uint256 i = 0; i + 3 < code.length; ++i) {
            for (uint256 k = 0; k < 8; ++k) {
                if (mask & bits[k] != 0) continue;
                if (
                    code[i] == sels[k][0] && code[i + 1] == sels[k][1] &&
                    code[i + 2] == sels[k][2] && code[i + 3] == sels[k][3]
                ) { mask |= bits[k]; break; }
            }
        }
    }

    // --- Scoring -------------------------------------------------------------

    /// @notice Weighted mean of normalized contributions, renormalized over the
    ///         signals that were available. An unavailable signal is excluded,
    ///         never scored as zero.
    /// @return available false where the pattern MUST NOT be scored at all, in
    ///         which case a detector reports it as unavailable rather than as a
    ///         low score, which would read as a finding of nothing wrong.
    function score(SignalVector memory v)
        public
        view
        returns (bool available, uint8 abuseScore)
    {
        uint256[N] memory raw = flatten(v);
        uint256 weighted;
        uint256 established;
        bool anyConduct;
        bool anyProportional;

        for (uint256 i = 0; i < N; ++i) {
            uint256 w = HARD_RUG[i];
            if (w == 0) continue;
            uint256 value = raw[i];
            // lpLockRemaining is uint32 seconds, so 65535 is a lock of 18 hours
            // rather than a sentinel. Each signal is tested against its own.
            uint256 sentinel = i == I_LP_LOCK_REMAINING ? NA32 : NA16;
            if (value == sentinel) continue; // unavailable

            uint256 s;
            if (i == I_PRIVILEGED_POWERS) {
                // Categorical: the profile's mask decides, and a power outside
                // it contributes nothing however many bits are set.
                s = (value & THRESHOLD[i]) != 0 ? BPS : 0;
            } else {
                s = normalize(value, THRESHOLD[i]);
                anyProportional = true;
            }
            if (CONDUCT[i]) anyConduct = true;
            if (PROTECTIVE[i]) s = BPS - s;
            weighted += w * s;
            established += w;
        }

        // Nothing established, or nothing but categorical signals: one retained
        // power would otherwise carry the pattern and report 100.
        if (established == 0 || !anyProportional) return (false, 0);

        // One division, rounded half up, as the specification states it.
        abuseScore = uint8((weighted * 100 + (established * BPS) / 2) / (established * BPS));

        // A fragment of the profile, or nothing describing conduct, is reported
        // but never above Elevated: it may not instruct a venue to freeze.
        if ((established * 2 < PROFILE_WEIGHT || !anyConduct) && abuseScore > ELEVATED_MAX) {
            abuseScore = ELEVATED_MAX;
        }
        return (true, abuseScore);
    }

    /// @dev Rises linearly to full strength at the activation threshold.
    function normalize(uint256 value, uint256 threshold) internal pure returns (uint256) {
        if (threshold == 0) return value > 0 ? BPS : 0;
        uint256 s = (value * BPS) / threshold;
        return s > BPS ? BPS : s;
    }

    function flatten(SignalVector memory v) internal pure returns (uint256[N] memory f) {
        f[0] = v.deployerSupplyShare;
        f[1] = v.insiderAllocationShare;
        f[2] = v.sniperConcentration;
        f[3] = v.lpLockedShare;
        f[4] = v.lpLockRemaining;
        f[5] = v.liquidityRemoved;
        f[6] = v.deployerSellRatio;
        f[7] = v.proceedsWithdrawnShare;
        f[8] = v.privilegedPowers;
        f[9] = v.priorUpheldClaims;
        f[10] = v.supplyInflation;
        f[11] = v.washTradeRatio;
    }

    // --- Containment ---------------------------------------------------------

    /// @notice The action a venue takes, from score and confidence jointly.
    /// @dev The ladder above, read as code. Refund is unreachable here: it MUST
    ///      require an upheld claim, so detection alone never reaches it.
    function containment(uint8 abuseScore, uint8 confidence)
        public
        pure
        returns (ContainmentAction)
    {
        if (abuseScore >= 81) {
            if (confidence >= 80) return ContainmentAction.Freeze;
            if (confidence >= 50) return ContainmentAction.SuspendRelease;
            return ContainmentAction.Flag;
        }
        if (abuseScore >= 61) {
            if (confidence >= 80) return ContainmentAction.SuspendRelease;
            if (confidence >= 50) return ContainmentAction.ExtendSchedule;
            return ContainmentAction.Flag;
        }
        if (abuseScore >= 41) {
            if (confidence >= 80) return ContainmentAction.ExtendSchedule;
            if (confidence >= 50) return ContainmentAction.Flag;
            return ContainmentAction.None;
        }
        if (confidence >= 80) return ContainmentAction.Flag;
        return ContainmentAction.None;
    }

    function toBps(uint256 part, uint256 whole) internal pure returns (uint16) {
        if (whole == 0) return NA16;
        uint256 v = (part * BPS) / whole;
        return uint16(v > BPS ? BPS : v);
    }
}
