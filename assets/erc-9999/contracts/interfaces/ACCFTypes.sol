// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title ACCFTypes
/// @notice Shared types and constants of the AI Cell Completeness Framework (ACCF).
library ACCFTypes {
    // ---------------------------------------------------------------------
    // Axes
    // ---------------------------------------------------------------------

    uint8 internal constant AXIS_INFRASTRUCTURE = 0;
    uint8 internal constant AXIS_PROTOCOL = 1;
    uint8 internal constant AXIS_ECONOMIC = 2;

    // ---------------------------------------------------------------------
    // Manifest entries and dependency masks
    // ---------------------------------------------------------------------

    /// @dev Entries 0..7 are the configuration sections of the manifest.
    uint8 internal constant SEC_EXECUTION = 0;
    uint8 internal constant SEC_INTELLIGENCE = 1;
    uint8 internal constant SEC_STATE = 2;
    uint8 internal constant SEC_CAPABILITY = 3;
    uint8 internal constant SEC_MAINTENANCE = 4;
    uint8 internal constant SEC_PROTOCOL = 5;
    uint8 internal constant SEC_ECONOMIC = 6;
    uint8 internal constant SEC_CONTROL = 7;

    /// @dev Entries 8..11 are the schemes of the four lifecycle capabilities.
    uint8 internal constant SCH_LINEAGE = 8;
    uint8 internal constant SCH_INTERACTION = 9;
    uint8 internal constant SCH_MAINTENANCE = 10;
    uint8 internal constant SCH_COMPOSITION = 11;

    /// @dev Entries 12..239 are extension entries defined by a manifest schema or a profile.
    uint8 internal constant FIRST_EXTENSION_ENTRY = 12;
    uint8 internal constant LAST_ENTRY = 239;

    /// @dev A dependency mask has bit `i` set for manifest entry `i`, bit 253 for the authorization
    ///      configuration, bit 254 for the controller and bit 255 for the boundary (subject, duties and
    ///      boundary). Bits 240..252 are reserved and zero.
    uint256 internal constant ENTRY_MASK = (uint256(1) << 240) - 1;
    uint256 internal constant DEP_AUTHORIZATION = uint256(1) << 253;
    uint256 internal constant DEP_CONTROL = uint256(1) << 254;
    uint256 internal constant DEP_BOUNDARY = uint256(1) << 255;
    uint256 internal constant DEPENDENCY_MASK = ENTRY_MASK | DEP_AUTHORIZATION | DEP_CONTROL | DEP_BOUNDARY;

    /// @dev Domain tag of the manifest root.
    bytes32 internal constant MANIFEST_DOMAIN = keccak256("ACCF manifest root v1");

    // ---------------------------------------------------------------------
    // Results and states
    // ---------------------------------------------------------------------

    /// @notice Result of a statement or of a derived view. `Undetermined` never counts as satisfied.
    ///         `NotApplicable` is a statement result only and only for conditional requirements.
    enum Result {
        Undetermined,
        Satisfied,
        NotSatisfied,
        NotApplicable
    }

    /// @notice Operating state of a unit. It is reported next to results and is never folded into them.
    enum OperatingState {
        None,
        Active,
        Degraded,
        Suspended,
        Maintenance,
        Retired
    }

    /// @notice What an evidence adapter reports for one reference. A call that reverts or returns
    ///         malformed data is an adapter error and is reported separately.
    enum ProbeStatus {
        Undetermined,
        Supported,
        NotSupported
    }

    // ---------------------------------------------------------------------
    // Transition kinds
    // ---------------------------------------------------------------------

    uint8 internal constant KIND_REGISTRATION = 0;
    uint8 internal constant KIND_DERIVATION = 1;
    uint8 internal constant KIND_MIGRATION = 2;
    uint8 internal constant KIND_SUCCESSION = 3;
    uint8 internal constant KIND_REPAIR = 4;
    uint8 internal constant KIND_UPGRADE = 5;
    uint8 internal constant KIND_COMPOSITION = 6;
    uint8 internal constant KIND_DECOMPOSITION = 7;
    uint8 internal constant KIND_CONTROL_CHANGE = 8;
    uint8 internal constant KIND_RETIREMENT = 9;
    uint8 internal constant KIND_SUSPENSION = 10;
    uint8 internal constant KIND_RESUMPTION = 11;
    uint8 internal constant KIND_BOUNDARY_CHANGE = 12;
    /// @dev Kinds 128..255 are extension kinds.
    uint8 internal constant FIRST_EXTENSION_KIND = 128;

    // ---------------------------------------------------------------------
    // Operator scopes
    // ---------------------------------------------------------------------

    /// @dev A transition needs the scope of its kind and the scope of every change it makes: entries
    ///      need SCOPE_MANIFEST, a new descriptor SCOPE_BOUNDARY, a target operating state SCOPE_STATE.
    uint256 internal constant SCOPE_MANIFEST = 1 << 0; // migration, repair, upgrade; any entry or relation
    uint256 internal constant SCOPE_STATE = 1 << 1; // suspension, resumption; any target operating state
    uint256 internal constant SCOPE_BOUNDARY = 1 << 2; // boundary change; any new descriptor
    uint256 internal constant SCOPE_DERIVE = 1 << 3; // derivation
    uint256 internal constant SCOPE_SUCCEED = 1 << 4; // succession, either side
    uint256 internal constant SCOPE_COMPOSE = 1 << 5; // composition, decomposition
    uint256 internal constant SCOPE_CLAIM = 1 << 6; // exclusive claims
    /// @dev Bits 128..255 are application scopes, defined by the contracts that check them.
    uint256 internal constant FIRST_APPLICATION_SCOPE = uint256(1) << 128;

    // ---------------------------------------------------------------------
    // Derivation limits
    // ---------------------------------------------------------------------

    uint8 internal constant LIMIT_COUNT = 1;
    uint8 internal constant LIMIT_GENERATION = 2;
    uint8 internal constant LIMIT_BUDGET = 4;

    // ---------------------------------------------------------------------
    // Units
    // ---------------------------------------------------------------------

    /// @notice Cell Record: the on-chain form of a Unit Descriptor with the manifest commitment.
    struct Unit {
        bytes32 subjectKey; // keccak256(abi.encode(subjectType, subjectData))
        address controller; // account or contract through which the control mechanism acts
        address recovery; // authority of the pre-agreed recovery rule for control changes; zero if none
        bytes32 kind; // open label, for example keccak256("agent") or keccak256("composite")
        uint8 rank; // reference ordering that keeps membership acyclic: a member's rank is below its group's
        OperatingState state;
        uint32 boundaryVersion;
        uint32 controlVersion; // advances when the controller changes
        uint32 authorizationRevision; // advances when recovery, grants, approvals or allowances change
        uint48 authorizationExpiry; // earliest expiry of a grant made under this control version; 0 if none
        uint32 manifestVersion;
        uint32 generation; // 0 for a registered unit, parent's generation + 1 for a derived unit
        uint48 registeredAt;
        uint48 bornAt; // time of derivation for a derived unit, 0 otherwise
        bytes32 descriptorHash; // commitment to the Unit Descriptor document
        bytes32 manifestRoot;
        uint256 entries; // bitmap of committed manifest entries
        bytes32 parent; // unit this unit was derived from; zero if none
        bytes32 lineageCommitment; // commitment to a lineage disclosed elsewhere; zero if none
        uint32 memberCount; // members this unit has as a group
        uint32 groupCount; // groups this unit is a member of
        uint32 claimCount; // exclusive claims held
    }

    struct UnitInput {
        bytes32 subjectType;
        bytes subjectData;
        bytes32 kind;
        uint8 rank;
        OperatingState state;
        address recovery;
        bytes32 descriptorHash;
        string descriptorURI;
        uint8[] entries; // strictly ascending
        bytes32[] entryHashes;
        uint8[] relationEntries; // entries whose declared dependencies are set, strictly ascending
        uint256[] relationMasks; // dependency mask each of those entries depends on
        string manifestURI;
        bytes32 lineageCommitment;
        bytes32 detailsHash; // commitment to the Transition Record document of the registration
        string detailsURI;
    }

    /// @notice Input of a transition that concerns one unit.
    struct TransitionInput {
        uint8 kind;
        uint8[] entries; // manifest entries to set or reconfirm, strictly ascending; each advances its revision
        bytes32[] entryHashes; // new commitments; zero removes the entry; an unchanged value reconfirms it
        uint8[] relationEntries; // entries whose declared dependencies change, strictly ascending
        uint256[] relationMasks;
        string manifestURI;
        bytes32 descriptorHash; // zero leaves the boundary unchanged
        string descriptorURI;
        OperatingState state; // target operating state; None leaves it unchanged
        bytes32 detailsHash; // commitment to the Transition Record document
        string detailsURI;
    }

    /// @notice Stored Transition Record.
    struct Transition {
        bytes32 unitId;
        bytes32 counterpart; // other unit of a derivation, succession or (de)composition; zero otherwise
        address actor;
        uint8 kind;
        OperatingState state; // operating state after the transition
        uint48 at;
        uint32 boundaryVersion; // versions after the transition
        uint32 controlVersion;
        uint32 manifestVersion;
        uint256 changed; // dependency mask of what the transition changed or reconfirmed
        bytes32 manifestRoot; // root after the transition
        bytes32 detailsHash;
    }

    struct DerivationAllowance {
        bool enabled;
        uint8 limits; // bit set of LIMIT_*
        uint32 maxChildren;
        uint32 maxGeneration; // highest generation a descendant may have
        uint256 budget; // total allocation that may be granted to children
    }

    /// @notice Stored derivation state of a unit.
    struct Derivation {
        DerivationAllowance allowance;
        uint32 children;
        uint256 granted;
        uint8 inherited; // limits inherited from the lineage
        uint32 inheritedMaxGeneration;
        uint256 inheritedBudget; // allocation received from the parent
    }

    struct DerivationTerms {
        uint256 budget; // allocation granted to the child out of the parent's budget
        bytes32[] claims; // exclusive claims moved from the parent to the child
    }

    struct SuccessionTerms {
        bytes32[] claims; // exclusive claims moved from the predecessor to the successor
        bool retirePredecessor;
        bytes32 predecessorDescriptorHash; // required when the predecessor continues
        string predecessorDescriptorURI;
        bytes32 detailsHash;
        string detailsURI;
        uint48 expiry;
    }

    // ---------------------------------------------------------------------
    // Profiles
    // ---------------------------------------------------------------------

    struct Requirement {
        uint8 axis;
        uint8 baselineClass; // 0: none; otherwise the Baseline class this requirement implements
        bool conditional; // may be answered NotApplicable under the profile's applicability rule
        uint256 dependencies; // minimum dependency mask of statements that cover it
    }

    struct Profile {
        address publisher;
        bytes32 contentHash;
        bytes32 supersedes;
        bool baseline; // claims the Baseline Requirements and was checked against them
        bool deprecated;
        uint16 count; // number of requirements
        uint48 publishedAt;
        uint256[3] axisMasks; // requirement indices of each axis
        uint256 conditionalMask;
    }

    // ---------------------------------------------------------------------
    // Statements
    // ---------------------------------------------------------------------

    /// @notice A reference to a record of another registry, read through an adapter.
    struct EvidenceRef {
        address adapter;
        address source; // registry holding the record
        bytes32 recordId;
        bytes32 commitment; // adapter-defined: expected subject, version or content commitment
        bool dynamic; // the record has to remain valid for the statement to support a current judgment
    }

    struct StatementInput {
        bytes32 unitId;
        bytes32 profileId;
        uint8 axis;
        Result result;
        uint256 coverage; // bitmap of requirement indices of the profile, all on `axis`
        uint256 dependencies; // dependency mask; includes the minimum of every covered requirement
        bytes32 expectedDigest; // dependency digest of the state the assessor assessed; issuance fails otherwise
        bytes32 methodId; // method and method version
        uint48 observedFrom; // observation window
        uint48 observedTo;
        uint48 validUntil;
        bytes32 evidenceHash; // commitment to the Completeness Statement document
        string evidenceURI;
        bytes32 supersedes; // earlier statement of the same assessor that this one replaces; zero if none
        EvidenceRef[] refs;
    }

    struct Statement {
        bytes32 unitId;
        bytes32 profileId;
        address assessor;
        uint8 axis;
        Result result;
        uint48 issuedAt;
        uint32 manifestVersion; // versions at issuance
        uint32 boundaryVersion;
        uint32 controlVersion;
        uint48 observedFrom;
        uint48 observedTo;
        uint48 validUntil;
        uint48 revokedAt; // 0: not revoked
        uint256 coverage;
        uint256 dependencies;
        bytes32 dependencyDigest; // digest of the dependencies at issuance, equal to the expected digest
        bytes32 manifestRoot; // root at issuance
        bytes32 methodId;
        bytes32 evidenceHash;
        bytes32 supersedes;
        bytes32 revocationReason;
    }

    // ---------------------------------------------------------------------
    // Evaluation policies
    // ---------------------------------------------------------------------

    uint8 internal constant MIX_SINGLE_ASSESSOR = 0; // one assessor supports all three axes
    uint8 internal constant MIX_PER_AXIS = 1; // each axis is supported by one assessor
    uint8 internal constant MIX_PER_REQUIREMENT = 2; // any accepted assessor per requirement

    uint8 internal constant CONFLICT_UNDETERMINED = 0; // contradicting accepted results give Undetermined
    uint8 internal constant CONFLICT_PRIORITY = 1; // the first accepted assessor with a determinate result governs
    uint8 internal constant CONFLICT_UNANIMOUS = 2; // every accepted assessor has to support the result

    struct AssessorRule {
        address assessor;
        uint8 axes; // bit set over axes (1 << axis) the assessor is accepted for
    }

    struct PolicyInput {
        bytes32 profileId;
        AssessorRule[] assessors; // in priority order
        bytes32[] methods; // accepted methods; empty accepts any
        uint48 maxAge; // 0: no bound besides the statement's own validity
        uint8 mixing; // MIX_*
        uint8 conflictRule; // CONFLICT_*
        uint8 acceptedStates; // bit set over OperatingState values (1 << state)
        bool liveEvidence; // probe evidence references at evaluation
        bytes32 contentHash; // commitment to the policy document
        string uri;
    }

    struct Policy {
        address owner;
        bytes32 profileId;
        uint48 maxAge;
        uint8 mixing;
        uint8 conflictRule;
        uint8 acceptedStates;
        bool liveEvidence;
        bytes32 contentHash;
        AssessorRule[] assessors;
        bytes32[] methods;
    }

    uint32 internal constant FLAG_CONFLICT = 1 << 0; // accepted assessors contradict each other
    uint32 internal constant FLAG_ADAPTER_ERROR = 1 << 1; // an adapter call failed
    uint32 internal constant FLAG_STALE = 1 << 2; // a statement expired or is older than the policy accepts
    uint32 internal constant FLAG_REVOKED = 1 << 3; // a statement was revoked
    uint32 internal constant FLAG_INAPPLICABLE = 1 << 4; // a statement's dependencies changed
    uint32 internal constant FLAG_EVIDENCE_LAPSED = 1 << 5; // a referenced record no longer supports its statement
    uint32 internal constant FLAG_METHOD = 1 << 6; // a statement's method is not accepted
    uint32 internal constant FLAG_PROBE_UNDETERMINED = 1 << 7; // an adapter could not determine a reference
    uint32 internal constant FLAG_STATE = 1 << 8; // the operating state is not accepted by the policy
    uint32 internal constant FLAG_NOT_BASELINE = 1 << 9; // the profile does not claim the Baseline Requirements
    uint32 internal constant FLAG_PROFILE_DEPRECATED = 1 << 10; // the profile was deprecated by its publisher
    uint32 internal constant FLAG_AUTHORIZATION_LAPSED = 1 << 11; // a grant the authorization configuration includes expired
    uint32 internal constant FLAG_EVIDENCE_UNVERIFIED = 1 << 12; // a dynamic reference was not verified by this evaluation

    /// @notice Derived view of one unit under one policy at one timepoint. Nothing in it is stored.
    struct Evaluation {
        Result overall;
        Result[3] axes;
        bool cellComplete; // overall Satisfied, Baseline profile, operating state accepted, dynamic evidence verified
        bool baseline;
        bool stateAccepted;
        OperatingState state;
        uint32 flags; // bit set of FLAG_*
        uint48 timepoint;
        uint256 open; // requirements without an applicable supporting statement of an accepted assessor
        bytes32 receipt; // commitment to the unit's versions, the policy, the timepoint and every statement read
    }
}
