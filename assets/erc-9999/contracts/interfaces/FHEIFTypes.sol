// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @notice Status of an activity scope.
enum ScopeStatus {
    NONE,
    ACTIVE,
    PAUSED,
    CLOSED
}

/// @notice Status of one key epoch of a key context.
/// ACTIVE accepts inputs, operation outputs and disclosures. RETIRED accepts no new objects;
/// objects already accepted under it may still be disclosed or converted. REVOKED accepts nothing.
enum EpochStatus {
    NONE,
    ACTIVE,
    RETIRED,
    REVOKED
}

/// @notice What a new key epoch declares about objects of the epoch before it.
/// RETAIN keeps them under the earlier epoch. CONVERT permits operations that take inputs of the
/// earlier epoch and produce outputs of the new one. RESET revokes the earlier epoch.
enum CarryOver {
    NONE,
    RETAIN,
    CONVERT,
    RESET
}

/// @notice What a policy version lets later versions do with objects accepted under it.
/// NARROW_ONLY: a later version can only take authority away. GOVERN: a later version decides alone.
enum SuccessorRight {
    NARROW_ONLY,
    GOVERN
}

enum ObjectOrigin {
    NONE,
    INPUT,
    OUTPUT
}

enum ObjectStatus {
    NONE,
    PROPOSED,
    ACCEPTED,
    REJECTED
}

enum OperationStatus {
    NONE,
    ADMITTED,
    RESULT_SUBMITTED,
    ACCEPTED,
    REJECTED,
    FAILED,
    CANCELLED,
    EXPIRED
}

enum DisclosureStatus {
    NONE,
    REQUESTED,
    AUTHORIZED,
    RELEASED,
    REFUSED,
    EXPIRED
}

/// @notice A crypto profile: the semantic contract of one way of computing on protected objects.
struct Profile {
    bytes32 descriptorHash;
    bytes32 evaluationClass;
    address registrant;
    uint64 registeredAt;
}

/// @notice A key context. Its key material, access structure and holders are those of its epochs.
struct KeyContext {
    bytes32 profileId;
    address controller;
    bytes32 descriptorHash;
    uint32 currentEpoch;
}

/// @notice What is declared when a key epoch is opened.
struct EpochInit {
    bytes32 materialHash;
    bytes32 accessHash;
    uint16 releaseQuorum;
    address[] holders;
}

struct KeyEpoch {
    bytes32 materialHash;
    bytes32 accessHash;
    uint16 releaseQuorum;
    uint16 holderCount;
    EpochStatus status;
    CarryOver carryOver;
    uint64 openedAt;
}

struct PolicyInit {
    bytes32 policyHash;
    address authorizer;
    SuccessorRight successorRight;
}

struct Policy {
    bytes32 policyHash;
    address authorizer;
    SuccessorRight successorRight;
    uint64 activatedAt;
}

struct Scope {
    address controller;
    bytes32 descriptorHash;
    bytes32 recordMode;
    uint64 policyVersion;
    ScopeStatus status;
}

/// @notice A disclosure view: what a release under it contains, and from what it is computed.
struct ViewDefinition {
    bytes32 scopeId;
    bytes32 programHash;
    bytes32 outputHash;
    bytes32 keyContextId;
    uint64 policyVersion;
    bool retired;
    bytes32[] inputClasses;
}

struct InputSubmission {
    bytes32 scopeId;
    bytes32 keyContextId;
    uint32 keyEpoch;
    bytes32 classId;
    bytes32 commitment;
    string locator;
}

struct OutputSubmission {
    bytes32 commitment;
    string locator;
}

struct ProtectedObject {
    bytes32 scopeId;
    bytes32 keyContextId;
    uint32 keyEpoch;
    bytes32 classId;
    bytes32 viewId;
    bytes32 commitment;
    bytes32 originId;
    address submitter;
    uint64 policyVersion;
    ObjectOrigin origin;
    ObjectStatus status;
}

/// @notice An operation request. Its EIP-712 digest is the operation identifier.
struct OperationRequest {
    bytes32 scopeId;
    uint64 policyVersion;
    bytes32 keyContextId;
    uint32 inputEpoch;
    uint32 outputEpoch;
    bytes32 programHash;
    bytes32 viewId;
    bytes32 outputClass;
    bytes32[] inputs;
    address requester;
    address executor;
    uint256 nonce;
    uint64 validUntil;
}

struct Operation {
    OperationRequest request;
    OperationStatus status;
    address submittedBy;
    bytes32[] outputs;
}

/// @notice A disclosure request. Its EIP-712 digest is the disclosure identifier.
struct DisclosureRequest {
    bytes32 scopeId;
    bytes32 objectId;
    bytes32 viewId;
    bytes32 keyContextId;
    uint32 keyEpoch;
    uint64 policyVersion;
    address audience;
    bytes32 deliveryKeyHash;
    address requester;
    uint256 nonce;
    uint64 validAfter;
    uint64 validUntil;
}

struct Disclosure {
    DisclosureRequest request;
    DisclosureStatus status;
    uint16 approvalsRequired;
    uint16 approvals;
    uint16 attestations;
}

/// @notice One piece of evidence: who supports which proposition about which subject, and how.
struct Evidence {
    bytes32 proposition;
    bytes32 mechanism;
    address attester;
    bytes32 payloadHash;
    uint64 recordedAt;
}

struct Anchor {
    bytes32 scopeId;
    bytes32 recordKind;
    address anchoredBy;
    uint64 anchoredAt;
}

/// @notice Well-known identifiers. Each is the keccak256 hash of the string shown.
library FHEIF {
    // Evaluation classes of a profile.
    bytes32 internal constant EVAL_HOMOMORPHIC = keccak256("fheif.evaluation.homomorphic");
    bytes32 internal constant EVAL_MIXED = keccak256("fheif.evaluation.mixed");
    bytes32 internal constant EVAL_TEST_ONLY = keccak256("fheif.evaluation.test-only");

    // Record modes of a scope.
    bytes32 internal constant RECORD_OPEN = keccak256("fheif.record.open");
    bytes32 internal constant RECORD_COMMITTED = keccak256("fheif.record.committed");

    // Capabilities resolved by the authorizer of a policy version.
    bytes32 internal constant CAP_SUBMIT_INPUT = keccak256("fheif.capability.submit-input");
    bytes32 internal constant CAP_REQUEST_OPERATION = keccak256("fheif.capability.request-operation");
    bytes32 internal constant CAP_EXECUTE_OPERATION = keccak256("fheif.capability.execute-operation");
    bytes32 internal constant CAP_ACCEPT_RESULT = keccak256("fheif.capability.accept-result");
    bytes32 internal constant CAP_REQUEST_DISCLOSURE = keccak256("fheif.capability.request-disclosure");
    bytes32 internal constant CAP_RECEIVE_VIEW = keccak256("fheif.capability.receive-view");
    bytes32 internal constant CAP_APPROVE_DISCLOSURE = keccak256("fheif.capability.approve-disclosure");
    bytes32 internal constant CAP_ANCHOR_RECORD = keccak256("fheif.capability.anchor-record");

    // The program of a view that releases an object as it is.
    bytes32 internal constant PROGRAM_IDENTITY = keccak256("fheif.program.identity");

    // The audience of a release that is open to everybody.
    address internal constant AUDIENCE_PUBLIC = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

    // Propositions an item of evidence can support.
    bytes32 internal constant PROP_INPUT_WELL_FORMED = keccak256("fheif.proposition.input-well-formed");
    bytes32 internal constant PROP_INPUT_CONSTRAINT = keccak256("fheif.proposition.input-constraint");
    bytes32 internal constant PROP_OPERATION_CORRECT = keccak256("fheif.proposition.operation-correct");
    bytes32 internal constant PROP_DECRYPTION_CORRECT = keccak256("fheif.proposition.decryption-correct");
    bytes32 internal constant PROP_DISCLOSURE_AUTHORIZED = keccak256("fheif.proposition.disclosure-authorized");
    bytes32 internal constant PROP_BUSINESS_ACCEPTED = keccak256("fheif.proposition.business-accepted");

    // Mechanisms by which a proposition is supported.
    bytes32 internal constant MECH_NONE = keccak256("fheif.mechanism.none");
    bytes32 internal constant MECH_SELF_DECLARED = keccak256("fheif.mechanism.self-declared");
    bytes32 internal constant MECH_REEXECUTION = keccak256("fheif.mechanism.re-execution");
    bytes32 internal constant MECH_COMMITTEE = keccak256("fheif.mechanism.committee");
    bytes32 internal constant MECH_ZK_PROOF = keccak256("fheif.mechanism.zk-proof");
    bytes32 internal constant MECH_TEE_ATTESTATION = keccak256("fheif.mechanism.tee-attestation");
    bytes32 internal constant MECH_OPTIMISTIC_CHALLENGE = keccak256("fheif.mechanism.optimistic-challenge");
    bytes32 internal constant MECH_DESIGNATED_VERIFIER = keccak256("fheif.mechanism.designated-verifier");
    bytes32 internal constant MECH_LEDGER_STATE = keccak256("fheif.mechanism.ledger-state");

    // Reasons given when an operation fails or a request can no longer proceed.
    bytes32 internal constant REASON_UNSUPPORTED = keccak256("fheif.reason.unsupported");
    bytes32 internal constant REASON_INCOMPATIBLE = keccak256("fheif.reason.incompatible");
    bytes32 internal constant REASON_UNDETERMINABLE = keccak256("fheif.reason.undeterminable");
    bytes32 internal constant REASON_RESOURCE = keccak256("fheif.reason.resource");
    bytes32 internal constant REASON_EXPIRED = keccak256("fheif.reason.expired");
    bytes32 internal constant REASON_NOT_YET_VALID = keccak256("fheif.reason.not-yet-valid");
    bytes32 internal constant REASON_SCOPE_PAUSED = keccak256("fheif.reason.scope-paused");
    bytes32 internal constant REASON_SCOPE_CLOSED = keccak256("fheif.reason.scope-closed");
    bytes32 internal constant REASON_POLICY_SUPERSEDED = keccak256("fheif.reason.policy-superseded");
    bytes32 internal constant REASON_EPOCH_NOT_USABLE = keccak256("fheif.reason.epoch-not-usable");
    bytes32 internal constant REASON_VIEW_RETIRED = keccak256("fheif.reason.view-retired");
    bytes32 internal constant REASON_NOT_AUTHORIZED = keccak256("fheif.reason.not-authorized");

    // Kinds of record that can be anchored by commitment.
    bytes32 internal constant KIND_DISCLOSURE_RECORD = keccak256("fheif.record-kind.disclosure");
    bytes32 internal constant KIND_BATCH_ROOT = keccak256("fheif.record-kind.batch-root");
}
