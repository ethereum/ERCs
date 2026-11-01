// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Verdict} from "./IConfidentialPolicyVerdict.sol";

/// @notice The attestation a consumed verdict hands off to ERC-8004's Validation Registry, so a
/// local pre-execution permission (the Verdict) becomes part of the agent's public compliance record.
/// @dev Two fields make this composable and non-ambiguous downstream:
///  - `artifactHash` is a content-addressed reference to the SPECIFIC action judged (not a class of
///    actions). It is exactly `Verdict.actionCommitment` (the canonical `PolicyAction` hash), so a
///    consumer can confirm the attestation is about one concrete action.
///  - `mechanism` is a source-class tag describing HOW the verdict was reached. Writing verdicts of
///    structurally different guarantees (self-attested / independent-mediator / ZK-against-secret-
///    policy / public-recomputable) into one shared registry without this tag lets them get silently
///    conflated into a single green checkmark. This standard is `MECHANISM_ZK_SECRET_POLICY`.
struct VerdictAttestation {
    uint256 agentId;      // ERC-8004 Identity Registry token id
    bytes32 artifactHash; // == Verdict.actionCommitment — content-addressed ref to the action judged
    bytes32 policyRoot;   // ERC-7812 root of the committed (undisclosed) policy the decision used
    bytes32 domainId;     // policy domain
    bytes32 nullifier;    // single-use verdict id
    uint8   decision;     // 1 = ALLOW
    bytes32 mechanism;    // source-class: how the verdict was reached (see PolicyAttestation)
    uint64  expiry;       // verdict expiry (unix seconds)
}

library PolicyAttestation {
    /// @dev The source-class for this standard: a ZK proof that a committed, undisclosed policy
    /// evaluated the action and permitted it. Distinguishes CAPV verdicts from every other kind.
    bytes32 internal constant MECHANISM_ZK_SECRET_POLICY = keccak256("zk-secret-policy");

    /// @notice Canonical attestation for a consumed verdict — the payload written to ERC-8004.
    function attestationFor(Verdict memory v) internal pure returns (VerdictAttestation memory) {
        return VerdictAttestation({
            agentId: v.agentId,
            artifactHash: v.actionCommitment,
            policyRoot: v.policyRoot,
            domainId: v.domainId,
            nullifier: v.nullifier,
            decision: v.decision,
            mechanism: MECHANISM_ZK_SECRET_POLICY,
            expiry: v.expiry
        });
    }
}

/// @notice Minimal view of the ERC-8004 Validation Registry write target used by a guarded contract
/// after it consumes a verdict. RECOMMENDED, not required — the Guard stays a minimal verdict primitive.
interface IValidationRegistry {
    event VerdictRecorded(uint256 indexed agentId, bytes32 indexed nullifier, bytes32 mechanism);

    function recordVerdict(VerdictAttestation calldata attestation) external;
}
