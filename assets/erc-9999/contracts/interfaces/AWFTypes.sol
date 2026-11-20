// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @dev Whether matching a list speaks for admitting or for refusing. Fixed when the list is
/// created and part of its identifier.
enum Polarity {
    NONE,
    ALLOW,
    DENY
}

/// @dev How a list determines its members.
enum Mode {
    NONE,
    ENUMERATED, // entries written by the manager
    COMMITTED, // a committed set; members are shown by proofs against its root
    PREDICATE, // whatever satisfies the criteria, decided by an evaluator at query time
    DERIVED // members of a source list, or objects related to them under a declared relation
}

/// @dev Result of asking one list about one subject. The zero value is the undetermined one.
enum Match {
    UNDETERMINED, // the question could not be settled
    MATCH, // the subject is a member
    NO_MATCH // it is confirmed that the subject is not a member
}

/// @dev Result of applying a binding to one request. The zero value is the indeterminate one.
enum Outcome {
    INDETERMINATE, // missing information, a failed evaluation or an unresolved conflict
    ALLOW,
    DENY,
    NOT_APPLICABLE // the binding forms no conclusion for this request
}

/// @dev What the adopter does with an outcome. The zero value is the refusing one.
enum Disposition {
    REFUSE,
    PROCEED,
    DEFER, // hold the request for more evidence or for review
    PROCEED_RESTRICTED // proceed within limits the adopter defines for this case
}

/// @dev Stored status of an entry. Pending and expired follow from its validity window.
enum EntryStatus {
    NONE,
    ACTIVE,
    SUSPENDED,
    REVOKED
}

/// @dev What an entry rests on.
enum Basis {
    DESIGNATION, // the manager's own choice; it asserts nothing about the subject
    EVIDENCED // a statement of fact about the subject; basisHash commits to the evidence
}

/// @dev What a committed set can show.
enum SetKind {
    NONE,
    MEMBERSHIP, // membership only; a negative query stays undetermined
    SORTED // sorted and complete; membership and non-membership
}

/// @dev Part the subject plays in a request.
enum Role {
    ACTOR, // the subject acts; the presenter must be entitled to act for it
    OBJECT // the subject is what the action is directed at
}

/// @dev Typed reference to the object a list entry or a request is about.
/// subjectKey = keccak256(abi.encode(kind, chainId, namespace, id))
struct SubjectRef {
    bytes32 kind; // keccak256 of the type name
    uint256 chainId; // chain of the namespace; 0 where the type is not tied to a chain
    address namespace; // contract or account that defines the identifier space; zero where the type has none
    bytes32 id; // identifier inside the namespace, encoded as the type prescribes
}

/// @dev Where a rule is meant to apply.
/// scopeId = keccak256(abi.encode(SCOPE_TAG, block.chainid, anchor, context, documentHash))
struct Scope {
    address anchor; // contract or account whose actions are in scope
    bytes32 context; // one activity of the anchor (a task, a group, a resource); zero for all of them
    bytes32 documentHash; // keccak256 of the scope document
}

/// @dev One immutable version of the rules a list applies.
/// criteriaId = keccak256(abi.encode(CRITERIA_TAG, block.chainid, documentHash, module,
///                                   moduleCodeHash, moduleConfig, rule, fanout))
struct Criteria {
    bytes32 documentHash; // keccak256 of the criteria document
    address module; // PREDICATE: evaluator. DERIVED: relation source, zero for none. Otherwise zero
    bytes32 moduleCodeHash; // code hash of the module when the criteria were registered
    bytes32 moduleConfig; // configHash() of the module when the criteria were registered
    bytes32 rule; // PREDICATE: parameter set defined by the evaluator. DERIVED: relation type
    uint8 fanout; // DERIVED with a relation: most origins considered for one subject
}

/// @dev Input of createList.
struct ListConfig {
    Polarity polarity;
    Mode mode;
    bytes32 scopeId; // scope the list is published for; zero for none
    bytes32 criteriaId; // zero for none
    uint32 noticePeriod; // seconds between adding an entry and its earliest effect
    bytes32 source; // DERIVED: source list in the same registry
    bytes32 sourcePin; // DERIVED: state of the source the list holds to; zero to follow the source
    bytes32 salt;
}

struct ListInfo {
    address manager;
    Polarity polarity;
    Mode mode;
    bool closed;
    uint8 depth; // length of the chain of sources below the list
    uint32 noticePeriod;
    uint64 revision; // raised by every act of the manager that can change a result
    bytes32 scopeId;
    bytes32 criteriaId;
    bytes32 source;
    bytes32 sourcePin;
    bytes32 setRoot;
    SetKind setKind;
    uint64 setSize;
}

/// @dev Input of addEntry.
struct EntryInput {
    uint64 validFrom; // zero for the earliest time the notice period allows
    uint64 validUntil; // zero for no expiry
    Basis basis;
    bytes32 basisHash; // keccak256 of the basis document; required for EVIDENCED
    bytes32 reason; // code from an open vocabulary
    address controller; // non-zero: the entry holds only while this account controls the subject
}

struct Entry {
    EntryStatus status;
    Basis basis;
    uint32 serial; // counts the entries this list has had for the subject
    uint64 listedAt;
    uint64 validFrom;
    uint64 validUntil;
    uint64 changedAt;
    address controller;
    bytes32 basisHash;
    bytes32 reason;
}

/// @dev The request a result is asked for, as established by the caller.
struct Request {
    address consumer; // whose action is being decided
    bytes32 action;
    bytes32 context;
    address presenter; // account that invokes the subject's standing; zero for none
    address controller; // controller of the subject; zero where not established
}

/// @dev What one list says about one subject, with everything needed to check it again.
struct Finding {
    bytes32 listId;
    Polarity polarity;
    Match result;
    bytes32 reason;
    uint64 revision;
    bytes32 stateHash;
    bytes32 criteriaId;
    uint64 validUntil; // the result holds until then if the list state does not change; 0 for this call only
    bytes32 basis; // entry basis, set root or evidence commitment
    bytes32 derivedFrom; // subjectKey of the listed origin of a derived match
}

/// @dev Proof against a committed set. abi.encode(SetProof) is the evidence of a COMMITTED list.
struct SetProof {
    bool member; // true: the subject is leaf `index`. false: it lies between leaves `index` and `index + 1`
    uint256 index;
    bytes32[] path;
    bytes32 lowKey; // non-membership: key of leaf `index`
    bytes32 highKey; // non-membership: key of leaf `index + 1`
    bytes32[] highPath; // non-membership: path of leaf `index + 1`
}

/// @dev Reference from a binding to a list.
struct ListRef {
    address registry;
    bytes32 listId;
    bytes32 pin; // list state the binding holds to; zero to follow the list
}

struct ActionRule {
    bytes32 action;
    bool once; // a decision to proceed is recorded per context and subject and honoured afterwards
}

/// @dev What an adopter declares when it puts lists to use.
struct BindingConfig {
    Scope scope; // scope.anchor is the consumer
    Role role;
    ActionRule[] actions;
    ListRef[] allow;
    uint8 allowThreshold; // number of ALLOW lists that must match; 1 is ANY, allow.length is ALL
    ListRef[] deny;
    uint8 denyThreshold;
    Outcome onConflict; // both sides match: ALLOW, DENY or INDETERMINATE
    Outcome onNoMatch; // neither side matches: ALLOW, DENY or NOT_APPLICABLE
    Disposition onIndeterminate;
    Disposition onNotApplicable;
    address resolver; // decides who may act for a subject; zero for the built-in rules
    bytes32 documentHash; // keccak256 of the binding document; zero for none
}

struct BindingInfo {
    address consumer;
    address adoptedBy;
    uint64 version;
    bool retired;
    bytes32 scopeId;
    bytes32 configHash; // keccak256(abi.encode(config))
}

/// @dev The standard result of one assessment.
struct Assessment {
    bytes32 bindingId;
    uint64 bindingVersion;
    bytes32 subjectKey;
    address presenter;
    address controller;
    bytes32 action;
    bytes32 context;
    Match standing; // ACTOR: whether the presenter may act for the subject
    Match allowSide;
    Match denySide;
    Outcome outcome;
    bytes32 reason;
    Disposition disposition;
    uint64 assessedAt;
    uint64 validUntil; // earliest validUntil of the findings; 0 for this call only
    bytes32 stateDigest; // commits to the binding version and the state of every list used
    Finding[] findings; // ALLOW lists in binding order, then DENY lists
}

struct Admission {
    uint64 at;
    uint64 bindingVersion;
    Outcome outcome; // the outcome under which the adopter proceeded
    Disposition disposition;
}

// Identifier tags.
bytes32 constant SCOPE_TAG = keccak256("AWF.Scope.v1");
bytes32 constant CRITERIA_TAG = keccak256("AWF.Criteria.v1");
bytes32 constant LIST_TAG = keccak256("AWF.List.v1");
bytes32 constant STATE_TAG = keccak256("AWF.ListState.v1");
bytes32 constant SET_LEAF_TAG = keccak256("AWF.SetLeaf.v1");
bytes32 constant BINDING_TAG = keccak256("AWF.Binding.v1");
bytes32 constant DIGEST_TAG = keccak256("AWF.StateDigest.v1");

// Subject kinds defined by this specification.
bytes32 constant KIND_ACCOUNT = keccak256("awf.subject.account");
bytes32 constant KIND_ENTRY = keccak256("awf.subject.entry");
bytes32 constant KIND_GROUP = keccak256("awf.subject.group");
bytes32 constant KIND_INSTANCE = keccak256("awf.subject.instance");
bytes32 constant KIND_DIGEST = keccak256("awf.subject.digest");
bytes32 constant KIND_NAME = keccak256("awf.subject.name");

// Reason codes of the registry. Codes are short ASCII strings; the vocabulary is open.
bytes32 constant R_LISTED = "LISTED";
bytes32 constant R_NOT_LISTED = "NOT_LISTED";
bytes32 constant R_ENTRY_PENDING = "ENTRY_PENDING";
bytes32 constant R_ENTRY_EXPIRED = "ENTRY_EXPIRED";
bytes32 constant R_ENTRY_SUSPENDED = "ENTRY_SUSPENDED";
bytes32 constant R_ENTRY_REVOKED = "ENTRY_REVOKED";
bytes32 constant R_CONTROLLER_UNKNOWN = "CONTROLLER_UNKNOWN";
bytes32 constant R_CONTROLLER_CHANGED = "CONTROLLER_CHANGED";
bytes32 constant R_LIST_UNKNOWN = "LIST_UNKNOWN";
bytes32 constant R_LIST_CLOSED = "LIST_CLOSED";
bytes32 constant R_SET_MEMBER = "SET_MEMBER";
bytes32 constant R_SET_NON_MEMBER = "SET_NON_MEMBER";
bytes32 constant R_SET_MISSING = "SET_MISSING";
bytes32 constant R_PROOF_MISSING = "PROOF_MISSING";
bytes32 constant R_PROOF_INVALID = "PROOF_INVALID";
bytes32 constant R_NEGATIVE_UNSUPPORTED = "NEGATIVE_UNSUPPORTED";
bytes32 constant R_MODULE_CHANGED = "MODULE_CHANGED";
bytes32 constant R_MODULE_FAILED = "MODULE_FAILED";
bytes32 constant R_SOURCE_STATE_CHANGED = "SOURCE_STATE_CHANGED";
bytes32 constant R_EXTENSION_LIMIT = "EXTENSION_LIMIT";
bytes32 constant R_RELATED = "RELATED";
bytes32 constant R_NOT_RELATED = "NOT_RELATED";
bytes32 constant R_RELATION_INCOMPLETE = "RELATION_INCOMPLETE";

// Reason codes of the guard.
bytes32 constant R_ALLOW_MATCH = "ALLOW_MATCH";
bytes32 constant R_DENY_MATCH = "DENY_MATCH";
bytes32 constant R_CONFLICT = "CONFLICT";
bytes32 constant R_DEFAULT = "DEFAULT";
bytes32 constant R_UNDETERMINED_INPUT = "UNDETERMINED_INPUT";
bytes32 constant R_BINDING_UNKNOWN = "BINDING_UNKNOWN";
bytes32 constant R_BINDING_RETIRED = "BINDING_RETIRED";
bytes32 constant R_CONSUMER_MISMATCH = "CONSUMER_MISMATCH";
bytes32 constant R_ACTION_NOT_COVERED = "ACTION_NOT_COVERED";
bytes32 constant R_CONTEXT_NOT_COVERED = "CONTEXT_NOT_COVERED";
bytes32 constant R_LIST_STATE_CHANGED = "LIST_STATE_CHANGED";
bytes32 constant R_REGISTRY_UNAVAILABLE = "REGISTRY_UNAVAILABLE";
bytes32 constant R_POLARITY_MISMATCH = "POLARITY_MISMATCH";
bytes32 constant R_PRESENTER_NOT_AUTHORIZED = "PRESENTER_NOT_AUTHORIZED";
bytes32 constant R_STANDING_UNVERIFIED = "STANDING_UNVERIFIED";
bytes32 constant R_ADMISSION_HONOURED = "ADMISSION_HONOURED";
