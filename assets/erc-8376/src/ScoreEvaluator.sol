// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {
    SignalVector,
    ImpersonationSignals,
    Powers,
    Patterns,
    Schemas,
    InvalidSignalVector,
    InvalidPattern,
    UnknownExtensionSchema
} from "./LaunchAbuseTypes.sol";

/// @title Fixed-point evaluator for the launch abuse score.
/// @notice Implements `abuseScore = round(100 * sum(w[i] * s[i]) / sum(w[i]))`
///         with every `s[i]` normalized into [0, BPS] against a pattern
///         activation threshold.
/// @dev Every signal describes deployer conduct. There is deliberately no input
///      to this library carrying price, market capitalization or buyer loss:
///      scoring outcome would flag honest failure as fraud.
library ScoreEvaluator {
    /// @dev Base signals. The twelve of version 1, and only those.
    uint256 internal constant N   = 12;
    /// @dev Slots reserved for the fields an extension schema adds. A pattern
    ///      that can be named but not scored is an identifier rather than a
    ///      detection, so the vector has to extend where the taxonomy does.
    uint256 internal constant EXT = 3;
    /// @dev Total addressable signals: base, then extension.
    uint256 internal constant M   = N + EXT;
    uint256 internal constant BPS = 10_000;

    // Signal indices, matching the order of `SignalVector`.
    uint256 internal constant I_DEPLOYER_SUPPLY   = 0;
    uint256 internal constant I_INSIDER_ALLOC     = 1;
    uint256 internal constant I_SNIPER_CONC       = 2;
    uint256 internal constant I_LP_LOCKED         = 3;
    uint256 internal constant I_LP_LOCK_REMAINING = 4;
    uint256 internal constant I_LIQUIDITY_REMOVED = 5;
    uint256 internal constant I_DEPLOYER_SELL     = 6;
    uint256 internal constant I_PROCEEDS_WITHDRAWN= 7;
    uint256 internal constant I_PRIVILEGED_POWERS = 8;
    uint256 internal constant I_PRIOR_CLAIMS      = 9;
    uint256 internal constant I_SUPPLY_INFLATION  = 10;
    uint256 internal constant I_WASH_TRADE        = 11;

    // Extension indices, in the order a schema declares its fields.
    uint256 internal constant I_EXT_0 = 12;
    uint256 internal constant I_EXT_1 = 13;
    uint256 internal constant I_EXT_2 = 14;

    // Field positions of the reference impersonation schema.
    uint256 internal constant I_SYMBOL_COLLISION = I_EXT_0;
    uint256 internal constant I_NAME_SIMILARITY  = I_EXT_1;
    uint256 internal constant I_METADATA_REUSE   = I_EXT_2;

    struct Profile {
        uint16[M] weights;    // zero weight excludes the signal from the pattern
        uint32[M] thresholds; // activation value; full contribution at or beyond
        bool[M]   protective; // true: contribution falls as the value rises
    }

    /// @notice Reference weight profile for `Patterns.HARD_RUG`.
    /// @dev Weights sum to 100. Deployments MAY tune these but MUST publish them.
    function hardRugProfile() internal pure returns (Profile memory p) {
        p.weights[I_LIQUIDITY_REMOVED]  = 30;
        p.weights[I_LP_LOCKED]          = 20;
        p.weights[I_PROCEEDS_WITHDRAWN] = 15;
        p.weights[I_LP_LOCK_REMAINING]  = 10;
        p.weights[I_DEPLOYER_SELL]      = 10;
        p.weights[I_PRIVILEGED_POWERS]  = 10;
        p.weights[I_PRIOR_CLAIMS]       = 5;

        p.thresholds[I_LIQUIDITY_REMOVED]  = 2_000;             // >= 20% removed
        p.thresholds[I_LP_LOCKED]          = 8_000;             // < 80% locked
        p.thresholds[I_PROCEEDS_WITHDRAWN] = 5_000;             // >= 50% withdrawn
        p.thresholds[I_LP_LOCK_REMAINING]  = uint32(30 days);   // < 30 days left
        p.thresholds[I_DEPLOYER_SELL]      = 3_000;             // >= 30% sold
        p.thresholds[I_PRIVILEGED_POWERS]  = Powers.DANGEROUS;  // any dangerous bit
        p.thresholds[I_PRIOR_CLAIMS]       = 1;                 // >= 1 prior claim

        p.protective[I_LP_LOCKED]         = true;
        p.protective[I_LP_LOCK_REMAINING] = true;
    }


    /// @notice The reference profile for a pattern.
    /// @dev Every pattern in the taxonomy has one. A pattern that can be
    ///      reported but not scored is an identifier, not a detection.
    function profileFor(bytes32 patternId) internal pure returns (Profile memory) {
        if (patternId == Patterns.HARD_RUG)            return hardRugProfile();
        if (patternId == Patterns.SOFT_RUG)            return softRugProfile();
        if (patternId == Patterns.INSIDER_ALLOCATION)  return insiderProfile();
        if (patternId == Patterns.SNIPER_COORDINATION) return sniperProfile();
        if (patternId == Patterns.HONEYPOT)            return honeypotProfile();
        if (patternId == Patterns.MINT_DILUTION)       return mintDilutionProfile();
        if (patternId == Patterns.RETAINED_CONTROL)    return retainedControlProfile();
        if (patternId == Patterns.WASH_LAUNCH)         return washLaunchProfile();
        if (patternId == Patterns.UNLOCK_EXIT)         return unlockExitProfile();
        if (patternId == Patterns.SERIAL_DEPLOYER)     return serialDeployerProfile();
        if (patternId == Patterns.IMPERSONATION)       return impersonationProfile();
        revert InvalidPattern(patternId);
    }

    /// @notice Score a vector under the reference profile for its pattern.
    /// @dev Reverts for a pattern whose weight sits in an extension. Scoring it
    ///      on the base vector alone would drop every extension field from both
    ///      sums and decide the pattern on whatever base signal the profile
    ///      happens to share: for impersonation, a single prior upheld claim
    ///      would carry the whole score to 100 with no impersonation evidence
    ///      at all, and genuine impersonation with no prior claim would not
    ///      score at all.
    function scoreFor(bytes32 patternId, SignalVector memory v) internal pure returns (uint8) {
        Profile memory p = profileFor(patternId);
        if (weighsExtension(p)) revert UnknownExtensionSchema(bytes32(0));
        return score(v, p);
    }

    /// @notice Whether a profile places weight on any extension field.
    function weighsExtension(Profile memory p) internal pure returns (bool) {
        for (uint256 i = N; i < M; ++i) {
            if (p.weights[i] != 0) return true;
        }
        return false;
    }

    /// @notice Score a vector together with the fields an extension schema adds.
    /// @dev Extension signals participate on identical terms to base signals:
    ///      they carry weights, they normalize against published thresholds, and
    ///      they are excluded from both sums when reported as unavailable.
    function scoreFor(
        bytes32 patternId,
        SignalVector memory v,
        bytes32 extensionSchema,
        bytes memory extensionSignals
    ) internal pure returns (uint8) {
        Profile memory profile = profileFor(patternId);
        if (extensionSchema == bytes32(0) && weighsExtension(profile)) {
            revert UnknownExtensionSchema(bytes32(0));
        }

        (uint32[M] memory value, bool[M] memory available) = flatten(v);
        if (extensionSchema != bytes32(0)) {
            (uint32[EXT] memory ev, bool[EXT] memory ea) =
                flattenExtension(extensionSchema, extensionSignals);
            for (uint256 i = 0; i < EXT; ++i) {
                value[N + i] = ev[i];
                available[N + i] = ea[i];
            }
        }
        return _score(value, available, profile);
    }

    /// @notice Decode the fields of a known extension schema.
    /// @dev A schema nobody can decode is not a detection either, so an
    ///      unrecognized identifier reverts here rather than scoring as zero.
    ///      A consumer that merely stores or displays a report treats an
    ///      unrecognized schema as informational instead.
    function flattenExtension(bytes32 extensionSchema, bytes memory extensionSignals)
        internal
        pure
        returns (uint32[EXT] memory value, bool[EXT] memory available)
    {
        if (extensionSchema != Schemas.IMPERSONATION) {
            revert UnknownExtensionSchema(extensionSchema);
        }
        uint16 u16 = type(uint16).max;
        ImpersonationSignals memory i = abi.decode(extensionSignals, (ImpersonationSignals));

        value[0] = i.symbolCollision;
        value[1] = i.nameSimilarity;
        value[2] = i.metadataReuse;

        available[0] = i.symbolCollision != u16;
        available[1] = i.nameSimilarity  != u16;
        available[2] = i.metadataReuse   != u16;
    }

    /// @notice Reference profile for `Patterns.IMPERSONATION`.
    /// @dev Every base signal can read clean while the token is a copy of
    ///      someone else's, so the weight sits almost entirely in the extension.
    ///      `priorUpheldClaims` is the one base signal that still carries: a
    ///      deployer who has impersonated before is likely to again.
    function impersonationProfile() internal pure returns (Profile memory p) {
        p.weights[I_SYMBOL_COLLISION] = 40;
        // Categorical, like `privilegedPowers`: the threshold is the mask of
        // collision classes that count, not a proportion to divide by.
        p.thresholds[I_SYMBOL_COLLISION] = 0x0007;
        p.weights[I_NAME_SIMILARITY] = 30; p.thresholds[I_NAME_SIMILARITY] = 8_000;
        p.weights[I_METADATA_REUSE]  = 20; p.thresholds[I_METADATA_REUSE]  = 5_000;
        p.weights[I_PRIOR_CLAIMS]    = 10; p.thresholds[I_PRIOR_CLAIMS]    = 1;
    }

    function softRugProfile() internal pure returns (Profile memory p) {
        p.weights[I_DEPLOYER_SELL]      = 35; p.thresholds[I_DEPLOYER_SELL]      = 3_000;
        p.weights[I_DEPLOYER_SUPPLY]    = 20; p.thresholds[I_DEPLOYER_SUPPLY]    = 3_000;
        p.weights[I_PROCEEDS_WITHDRAWN] = 20; p.thresholds[I_PROCEEDS_WITHDRAWN] = 5_000;
        p.weights[I_LP_LOCKED]          = 10; p.thresholds[I_LP_LOCKED]          = 8_000;
        p.weights[I_PRIVILEGED_POWERS]  = 10; p.thresholds[I_PRIVILEGED_POWERS]  = Powers.DANGEROUS;
        p.weights[I_PRIOR_CLAIMS]       = 5;  p.thresholds[I_PRIOR_CLAIMS]       = 1;
        p.protective[I_LP_LOCKED] = true;
    }

    function insiderProfile() internal pure returns (Profile memory p) {
        p.weights[I_INSIDER_ALLOC]   = 45; p.thresholds[I_INSIDER_ALLOC]   = 1_000;
        p.weights[I_DEPLOYER_SUPPLY] = 20; p.thresholds[I_DEPLOYER_SUPPLY] = 3_000;
        p.weights[I_SNIPER_CONC]     = 20; p.thresholds[I_SNIPER_CONC]     = 2_000;
        p.weights[I_PRIOR_CLAIMS]    = 15; p.thresholds[I_PRIOR_CLAIMS]    = 1;
    }

    function sniperProfile() internal pure returns (Profile memory p) {
        p.weights[I_SNIPER_CONC]     = 50; p.thresholds[I_SNIPER_CONC]     = 2_000;
        p.weights[I_INSIDER_ALLOC]   = 25; p.thresholds[I_INSIDER_ALLOC]   = 1_000;
        p.weights[I_DEPLOYER_SUPPLY] = 15; p.thresholds[I_DEPLOYER_SUPPLY] = 3_000;
        p.weights[I_PRIOR_CLAIMS]    = 10; p.thresholds[I_PRIOR_CLAIMS]    = 1;
    }

    /// @dev A honeypot is built from the powers that block or tax selling, not
    ///      from the ones that expropriate.
    function honeypotProfile() internal pure returns (Profile memory p) {
        p.weights[I_PRIVILEGED_POWERS] = 70;
        p.thresholds[I_PRIVILEGED_POWERS] =
            Powers.PAUSE | Powers.BLACKLIST | Powers.FEE | Powers.LIMITS | Powers.EXEMPT;
        p.weights[I_DEPLOYER_SUPPLY] = 15; p.thresholds[I_DEPLOYER_SUPPLY] = 3_000;
        p.weights[I_PRIOR_CLAIMS]    = 15; p.thresholds[I_PRIOR_CLAIMS]    = 1;
    }

    function mintDilutionProfile() internal pure returns (Profile memory p) {
        p.weights[I_SUPPLY_INFLATION]  = 50; p.thresholds[I_SUPPLY_INFLATION]  = 1_000;
        p.weights[I_PRIVILEGED_POWERS] = 30; p.thresholds[I_PRIVILEGED_POWERS] = Powers.MINT;
        p.weights[I_DEPLOYER_SUPPLY]   = 10; p.thresholds[I_DEPLOYER_SUPPLY]   = 3_000;
        p.weights[I_PRIOR_CLAIMS]      = 10; p.thresholds[I_PRIOR_CLAIMS]      = 1;
    }

    function retainedControlProfile() internal pure returns (Profile memory p) {
        p.weights[I_PRIVILEGED_POWERS] = 70;
        p.thresholds[I_PRIVILEGED_POWERS] = Powers.MINT | Powers.PAUSE | Powers.BLACKLIST
            | Powers.FEE | Powers.UPGRADE | Powers.SEIZE | Powers.LIMITS | Powers.EXEMPT;
        p.weights[I_LP_LOCKED]    = 15; p.thresholds[I_LP_LOCKED]    = 8_000;
        p.weights[I_PRIOR_CLAIMS] = 15; p.thresholds[I_PRIOR_CLAIMS] = 1;
        p.protective[I_LP_LOCKED] = true;
    }

    function washLaunchProfile() internal pure returns (Profile memory p) {
        p.weights[I_WASH_TRADE]    = 50; p.thresholds[I_WASH_TRADE]    = 3_000;
        p.weights[I_SNIPER_CONC]   = 25; p.thresholds[I_SNIPER_CONC]   = 2_000;
        p.weights[I_INSIDER_ALLOC] = 15; p.thresholds[I_INSIDER_ALLOC] = 1_000;
        p.weights[I_PRIOR_CLAIMS]  = 10; p.thresholds[I_PRIOR_CLAIMS]  = 1;
    }

    /// @dev The exit is timed to the unlock, so a short remaining lock alongside
    ///      selling and withdrawal is the shape, not the lock alone.
    function unlockExitProfile() internal pure returns (Profile memory p) {
        p.weights[I_LP_LOCK_REMAINING] = 30; p.thresholds[I_LP_LOCK_REMAINING] = uint32(30 days);
        p.weights[I_DEPLOYER_SELL]     = 30; p.thresholds[I_DEPLOYER_SELL]     = 3_000;
        p.weights[I_LIQUIDITY_REMOVED] = 25; p.thresholds[I_LIQUIDITY_REMOVED] = 2_000;
        p.weights[I_PRIOR_CLAIMS]      = 15; p.thresholds[I_PRIOR_CLAIMS]      = 1;
        p.protective[I_LP_LOCK_REMAINING] = true;
    }

    /// @dev Scales to three prior claims so one upheld claim does not by itself
    ///      brand a deployer a repeat offender.
    function serialDeployerProfile() internal pure returns (Profile memory p) {
        p.weights[I_PRIOR_CLAIMS]      = 60; p.thresholds[I_PRIOR_CLAIMS]      = 3;
        p.weights[I_DEPLOYER_SUPPLY]   = 15; p.thresholds[I_DEPLOYER_SUPPLY]   = 3_000;
        p.weights[I_PRIVILEGED_POWERS] = 15; p.thresholds[I_PRIVILEGED_POWERS] = Powers.DANGEROUS;
        p.weights[I_INSIDER_ALLOC]     = 10; p.thresholds[I_INSIDER_ALLOC]     = 1_000;
    }

    /// @notice Flatten a `SignalVector` into values plus availability flags.
    /// @dev A signal reported at its type maximum is unavailable and MUST be
    ///      excluded from both the numerator and the denominator. Treating it as
    ///      zero would let a detector suppress exculpatory signals for free.
    function flatten(SignalVector memory v)
        internal
        pure
        returns (uint32[M] memory value, bool[M] memory available)
    {
        uint16 u16 = type(uint16).max;

        value[I_DEPLOYER_SUPPLY]    = v.deployerSupplyShare;
        value[I_INSIDER_ALLOC]      = v.insiderAllocationShare;
        value[I_SNIPER_CONC]        = v.sniperConcentration;
        value[I_LP_LOCKED]          = v.lpLockedShare;
        value[I_LP_LOCK_REMAINING]  = v.lpLockRemaining;
        value[I_LIQUIDITY_REMOVED]  = v.liquidityRemoved;
        value[I_DEPLOYER_SELL]      = v.deployerSellRatio;
        value[I_PROCEEDS_WITHDRAWN] = v.proceedsWithdrawnShare;
        value[I_PRIVILEGED_POWERS]  = v.privilegedPowers;
        value[I_PRIOR_CLAIMS]       = v.priorUpheldClaims;
        value[I_SUPPLY_INFLATION]   = v.supplyInflation;
        value[I_WASH_TRADE]         = v.washTradeRatio;

        available[I_DEPLOYER_SUPPLY]    = v.deployerSupplyShare    != u16;
        available[I_INSIDER_ALLOC]      = v.insiderAllocationShare != u16;
        available[I_SNIPER_CONC]        = v.sniperConcentration    != u16;
        available[I_LP_LOCKED]          = v.lpLockedShare          != u16;
        available[I_LP_LOCK_REMAINING]  = v.lpLockRemaining        != type(uint32).max;
        available[I_LIQUIDITY_REMOVED]  = v.liquidityRemoved       != u16;
        available[I_DEPLOYER_SELL]      = v.deployerSellRatio      != u16;
        available[I_PROCEEDS_WITHDRAWN] = v.proceedsWithdrawnShare != u16;
        available[I_PRIVILEGED_POWERS]  = v.privilegedPowers       != u16;
        available[I_PRIOR_CLAIMS]       = v.priorUpheldClaims      != u16;
        available[I_SUPPLY_INFLATION]  = v.supplyInflation        != u16;
        available[I_WASH_TRADE]        = v.washTradeRatio         != u16;
    }

    /// @notice Normalize one signal to [0, BPS].
    function normalize(uint256 index, uint32 value, Profile memory p)
        internal
        pure
        returns (uint256 s)
    {
        // The bitmask signals are categorical, not proportional: any dangerous
        // power contributes fully, and a merely inconvenient one not at all.
        // A symbol collision reads the same way, since sharing the ticker of an
        // older token is not twice as bad as sharing that of any token.
        if (index == I_PRIVILEGED_POWERS || index == I_SYMBOL_COLLISION) {
            // The threshold carries the mask, so each pattern scores the
            // powers that matter to it: a honeypot cares about pause and
            // blacklist, a rug about mint, upgrade and seize.
            uint16 mask = uint16(p.thresholds[index]);
            return (uint16(value) & mask) != 0 ? BPS : 0;
        }

        uint32 t = p.thresholds[index];
        if (t == 0) return 0;

        s = (uint256(value) * BPS) / uint256(t);
        if (s > BPS) s = BPS;

        // A protective signal at or beyond its threshold contributes nothing;
        // its absence is what is adverse.
        if (p.protective[index]) s = BPS - s;
    }

    /// @notice Compute the 0-100 abuse score for a vector under a profile.
    function score(SignalVector memory v, Profile memory p)
        internal
        pure
        returns (uint8)
    {
        (uint32[M] memory value, bool[M] memory available) = flatten(v);
        return _score(value, available, p);
    }

    function _score(uint32[M] memory value, bool[M] memory available, Profile memory p)
        internal
        pure
        returns (uint8)
    {
        uint256 num = 0;
        uint256 den = 0;
        for (uint256 i = 0; i < M; ++i) {
            uint256 w = p.weights[i];
            if (w == 0 || !available[i]) continue;
            num += w * normalize(i, value[i], p);
            den += w;
        }

        if (den == 0) revert InvalidSignalVector();

        uint256 scale = den * BPS;
        uint256 result = (num * 100 + scale / 2) / scale; // round half up
        return uint8(result > 100 ? 100 : result);
    }

    /// @notice Convenience wrapper using the reference hard-rug profile.
    function scoreHardRug(SignalVector memory v) internal pure returns (uint8) {
        return score(v, hardRugProfile());
    }
}
