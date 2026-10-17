// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  CAAP M1 shared type domain
/// @notice Single source of truth for the claim taxonomy, resolution codes,
///         and payout tranches shared by LeaseBond and IResolutionModule.
///         Enum ordinals are ABI-load-bearing across contracts: append only,
///         never reorder, never remove. Semantics are normative in
///         m1-failure-state-spec-v0.1.md and i-resolution-module-v0.1.md.

enum ClaimKind {
    PhysicalDamage,       // body damaged property or hardware
    WipeNonproduction,    // wipe evidence not produced after cure
    CredentialRetention,  // broker-rule violation past lease end
    TelemetryWithheld,    // no valid disclosure for the claim window
    Equivocation,         // forked heads / conflicting tickets, same actor
    Casualty,             // total physical loss of the body
    EvidenceFraud,        // fabricated or anchored-root-contradicting evidence
    Contradiction         // post-loss key use, counter rollback
}

enum ResolutionCode {
    None,
    TimelyWipe,
    LateWipeNoFault,
    LateWipeOperatorFault,
    QualifiedCasualty,
    UnprovenLoss,
    MountInvariantBreach,
    DeliberateRetention,
    AttestationEquivocation,
    OperatorNonCooperation,
    VendorOrVerifierFailure,
    ChallengerAbuse,
    ProtocolFailure
}

enum Tranche { Performance, Evidence, Casualty, Challenge, ContradictionHoldback }
