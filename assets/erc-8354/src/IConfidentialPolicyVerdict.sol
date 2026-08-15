// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice The verdict envelope. EVERY field is a public input of the proving program.
struct Verdict {
    uint256 agentId;          // ERC-8004 Identity Registry token id
    bytes32 domainId;         // policy domain
    bytes32 policyRoot;       // ERC-7812 EvidenceDB root the decision was made against
    bytes32 actionCommitment; // commitment to the action being authorized (see PolicyAction)
    address executor;         // the address permitted to consume this verdict (directly or via signed relay)
    uint64  expiry;           // unix seconds, exclusive
    bytes32 nullifier;        // single-use, domain-scoped
    uint8   decision;         // 0 = DENY, 1 = ALLOW
    uint8   policyKind;       // which of the four states this verdict carries (see PolicyKind)
}

/// @notice The four states a verdict can carry. `decision` alone collapses the three refusal
/// kinds into one bit; `policyKind` is what keeps them distinguishable at the surface a relying
/// party actually reads. Every kind is a committed public input of its proving program, so a
/// verdict cannot claim a kind its proof did not establish.
library PolicyKind {
    /// @dev decision == 1. The policy authorized the action.
    uint8 internal constant ALLOWED = 0;
    /// @dev decision == 0. A rule fired against the action (denylist membership).
    uint8 internal constant DENIED = 1;
    /// @dev decision == 0. Nothing authorized the action (allowlist non-membership).
    uint8 internal constant NOT_PERMITTED = 2;
    /// @dev decision == 0. The policy could not be evaluated at all.
    uint8 internal constant COULD_NOT_EVALUATE = 3;

    /// @dev A verdict is well-formed only when its decision and kind agree.
    function agreesWithDecision(uint8 kind, uint8 decision) internal pure returns (bool) {
        return decision == 1 ? kind == ALLOWED : (kind == DENIED || kind == NOT_PERMITTED || kind == COULD_NOT_EVALUATE);
    }
}

/// @notice Consume a confidential policy verdict: a ZK proof that an action was
/// evaluated against a committed (secret) policy and permitted.
/// @dev ERC-165 interfaceId = XOR of this interface's own 5 function selectors (inherited
/// IERC165.supportsInterface is excluded per the language rule). Value: 0xd6da8150.
interface IConfidentialPolicyVerdict is IERC165 {
    event VerdictConsumed(
        bytes32 indexed nullifier,
        uint256 indexed agentId,
        bytes32 indexed domainId,
        bytes32 policyRoot,
        bytes32 actionCommitment
    );

    error VerdictExpired(uint64 expiry);
    error VerdictReplayed(bytes32 nullifier);
    error ExecutorMismatch(address expected, address actual);
    error ExecutorAuthInvalid();
    error PolicyRootRejected(bytes32 root);
    error DomainInactive(bytes32 domainId);
    error VerdictDenied();
    /// @dev `decision` and `policyKind` disagree, so the verdict is not well-formed.
    error VerdictKindMismatch(uint8 decision, uint8 policyKind);
    error InvalidProof();

    /// @notice Verify without state change. MUST NOT revert on a well-formed-but-invalid
    /// verdict, and MUST return false (not revert) on a malformed proof.
    function verify(Verdict calldata v, bytes calldata proof) external view returns (bool);

    /// @notice EIP-712 digest an executor signs to authorize RELAYED submission of this exact
    /// verdict. The verdict's single-use nullifier gives the signature replay protection for free.
    function verdictDigest(Verdict calldata v) external view returns (bytes32);

    /// @notice Direct consume. MUST require v.executor == msg.sender, v.decision == 1, and burn
    /// the nullifier. Reverts with the specific error on the first failing check, in spec order.
    function consume(Verdict calldata v, bytes calldata proof) external;

    /// @notice Relayed consume. `msg.sender` MAY be any address if `executorAuth` is a valid
    /// EIP-712 signature (ECDSA or ERC-1271) by v.executor over verdictDigest(v). Because the
    /// action is committed and the executor is bound cryptographically, front-running the
    /// submission is neutral: any submitter causes the identical committed execution.
    function consume(Verdict calldata v, bytes calldata proof, bytes calldata executorAuth) external;

    function isConsumed(bytes32 domainId, bytes32 nullifier) external view returns (bool);
}

/// @notice A contract gated by a policy verdict.
interface IPolicyGuarded {
    function policyDomain() external view returns (bytes32);
}
