// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  SAI — Swarm AI Framework: shared types (reference v0.2)
/// @notice A swarm is a purpose-bound collective with an explicit membership boundary, an
///         objective with attainment rules and a declared collaboration posture. Every
///         parameter the registry executes — roles, phases, authorities, activation rule,
///         contribution mode, fallback timers — lives in `SwarmSpec`, whose identifier is
///         keccak256(abi.encode(SwarmSpec)); the registered rule and the executed rule are
///         one object. Descriptive content (the charter text, the objective descriptor, the
///         resource manifest, the allocation formula) lives in the off-chain Swarm Pack
///         committed by `charterHash`.
library SAITypes {
    // ------------------------------------------------------------------ posture

    /// Executed dimension: who may enter during a phase.
    enum Boundary {
        OPEN,    // an eligible account joins by itself in a selfJoin role; others apply
        GATED,   // admission by the ADMIT authority plus the member's acceptance
        CLOSED   // no admission
    }

    /// Executed dimension: how a phase's roster is formed from the previous phase.
    enum Admission {
        RECRUIT,  // from scratch (phase 0 always)
        INHERIT,  // every member carries over
        SELECT    // the ADVANCE authority names who carries over; the rest exit
    }

    /// Declared dimensions — payoff, topology and coordination — are `bytes32` terms of a
    /// write-once vocabulary kept by the registry (ISwarmRegistry.registerTerm). Dimension
    /// identifiers are keccak256("sai.dimension.payoff" | ".topology" | ".coordination").
    /// Base terms, registered at deployment:
    ///   payoff:       keccak256("sai.payoff.shared" | ".exclusive" | ".mixed")
    ///   topology:     keccak256("sai.topology.redundant" | ".partitioned" | ".sequential" |
    ///                 ".hierarchical" | ".iterative" | ".free")
    ///   coordination: keccak256("sai.coordination.leader" | ".collective" | ".market" |
    ///                 ".automated" | ".none")
    /// Anyone may register a further term under a dimension, once, with a descriptor URI.
    bytes32 internal constant DIM_PAYOFF       = keccak256("sai.dimension.payoff");
    bytes32 internal constant DIM_TOPOLOGY     = keccak256("sai.dimension.topology");
    bytes32 internal constant DIM_COORDINATION = keccak256("sai.dimension.coordination");

    // ------------------------------------------------------------------ authority

    enum AuthorityKind {
        NONE,        // the decision point is disabled for this swarm
        ADDRESS,     // one account or contract (a coordinator, a verifier, a decision adapter)
        ROLE,        // any active member holding `roleId`
        ANY_MEMBER,  // any active member
        INITIATOR    // the account that formed the swarm
    }

    struct Authority {
        AuthorityKind kind;
        address       target;  // ADDRESS: the holder at formation; otherwise zero
        bytes32       roleId;  // ROLE: the role; otherwise zero
    }

    /// Decision points of a swarm. `SwarmSpec.authorities` has exactly one entry per value,
    /// indexed by this enum.
    enum DecisionPoint {
        ACTIVATE,     // FORMING -> ACTIVE (when activation is AUTHORITY or BOTH)
        ABORT,        // FORMING -> DISSOLVED before the recruitment window ends
        SUSPEND,      // ACTIVE -> SUSPENDED
        RESUME,       // SUSPENDED -> ACTIVE
        ADVANCE,      // next phase
        CONCLUDE,     // ACTIVE / SUSPENDED -> CONCLUDING with an outcome
        DISSOLVE,     // CONCLUDING -> DISSOLVED before the settlement window ends
        SUCCEED,      // form a successor swarm; this swarm concludes SUPERSEDED
        ADMIT,        // admit a candidate, drop a candidate, substitute a seat
        REMOVE,       // suspend or remove a member on judgment
        REINSTATE,    // lift a suspension
        AMEND,        // publish a new charter version; change the transport hint
        ATTACH,       // attach a resource
        DETACH,       // detach a resource
        SET_ACCOUNT,  // bind the swarm account
        REPRESENT     // act for the swarm through its account (submit, sign, execute)
    }

    uint256 internal constant DECISION_POINTS = 16;

    enum Activation {
        ROSTER_MET,  // anyone may activate once the roster thresholds hold
        AUTHORITY,   // the ACTIVATE authority activates
        BOTH         // the ACTIVATE authority activates, and the thresholds must hold
    }

    /// Who may record contributions.
    enum Contributions {
        DISABLED,  // the registry refuses contribution records for this swarm
        MEMBERS,   // active and suspended members
        OPEN       // anyone; non-member records are flagged
    }

    // ------------------------------------------------------------------ spec

    struct RoleSpec {
        bytes32 roleId;       // unique within the spec; `sai.role.*` names are reserved conventions
        uint32  min;          // active members required for activation; 0 = none
        uint32  max;          // seats (active + suspended); 0 = unbounded
        address eligibility;  // IEligibility module consulted at admission and on challenge; 0 = none
        bool    selfJoin;     // may an eligible account join without the ADMIT authority (OPEN phases)
    }

    struct PhaseSpec {
        bytes32   name;            // label
        bytes32   payoff;          // registered term under DIM_PAYOFF
        bytes32   topology;        // registered term under DIM_TOPOLOGY
        bytes32   coordination;    // registered term under DIM_COORDINATION
        Boundary  boundary;
        Admission admission;       // phase 0 MUST be RECRUIT
        uint64    inputWindow;     // seconds from phase start accepting admissions and contributions; 0 = unbounded
        bytes32   descriptorHash;  // informative reference to the phase's description in the Swarm Pack
    }

    struct SwarmSpec {
        RoleSpec[]    roles;
        PhaseSpec[]   phases;
        Authority[]   authorities;         // length == DECISION_POINTS, indexed by DecisionPoint
        Activation    activation;
        Contributions contributions;
        uint32        minMembers;          // active members required for activation; >= 1
        uint32        maxMembers;          // seats (active + suspended); 0 = unbounded
        uint64        recruitmentWindow;   // FORMING fallback: anyone may abort after formedAt + window; MUST be > 0
        uint64        maxDuration;         // hard cap from activation: anyone may enforce the deadline; 0 = none
        uint64        inactivityTimeout;   // anyone may suspend, then conclude, after this much inactivity; 0 = disabled
        uint64        ineligibleGrace;     // after this long in SUSPENDED(INELIGIBLE), anyone may expel
        uint64        settlementWindow;    // after this long in CONCLUDING, anyone may dissolve
        uint64        amendmentExitWindow; // members may leave without consequence for this long after a material amendment
        bytes32       descriptorHash;      // informative reference to the spec's description in the Swarm Pack
    }

    // ------------------------------------------------------------------ origin

    /// Where a swarm came from. `kind` is keccak256("sai.origin.initiator" | ".joint" | ".task" |
    /// ".trigger" | ".decision" | ".succession"); `ref` is an opaque reference the kind gives meaning to
    /// (a hash of the task reference, a decision issue id, a trigger rule hash, zero for a plain initiator).
    struct Origin {
        bytes32 kind;
        bytes32 ref;
    }

    // ------------------------------------------------------------------ objective

    enum ObjectiveKind {
        TERMINAL,     // one deliverable, one conclusion
        MILESTONED,   // a sequence of accepted milestones
        EXPLORATORY,  // search for a result under agreed resources; PARTIAL = best known result
        STANDING      // recurring or open-ended delivery
    }

    /// An external obligation the objective is bound to (a token-bound task tender, a job, any
    /// contract); zero when none.
    struct ExternalRef {
        uint256 chainId;
        address target;
        uint256 id;
    }

    struct ObjectiveInput {
        bytes32       objectiveHash;        // commitment to the objective descriptor in the Swarm Pack
        ObjectiveKind kind;
        address       acceptanceAuthority;  // records milestones and may conclude; 0 = CONCLUDE authority only
        ExternalRef   obligation;
        uint32        milestoneCount;       // MILESTONED: > 0; otherwise 0
    }

    struct Objective {
        bytes32       objectiveHash;
        uint32        version;              // charter version at which objectiveHash was last set (1 at formation)
        ObjectiveKind kind;
        address       acceptanceAuthority;
        ExternalRef   obligation;
        uint32        milestoneCount;
        uint32        milestonesAccepted;
    }

    enum MilestoneStatus { PENDING, ACCEPTED, REJECTED }

    // ------------------------------------------------------------------ lifecycle

    enum LifecycleState { NONE, FORMING, ACTIVE, SUSPENDED, CONCLUDING, DISSOLVED }

    enum OutcomeType { NONE, ACHIEVED, PARTIAL, FAILED, ABANDONED, SUPERSEDED }

    /// Why a transition happened; never a verdict on the merits.
    enum Reason {
        NONE,
        AUTHORITY,            // an authority enacted the transition
        ACCEPTANCE,           // the acceptance authority recorded the outcome
        RECRUITMENT_EXPIRED,  // FORMING aborted after the recruitment window
        TIMEOUT,              // hard deadline enforced
        INACTIVITY,           // inactivity timeout enforced
        ROSTER_LOST,          // active members below the thresholds
        SUCCESSION            // superseded by a successor swarm
    }

    struct Swarm {
        bytes32        specHash;
        bytes32        charterHash;
        uint32         charterVersion;     // incremented by every amendment
        uint32         commitmentVersion;  // incremented by material amendments only
        string         charterURI;
        address        initiator;          // the account that submitted the formation
        Origin         origin;             // what the formation came from
        bytes32        parentId;           // nesting; 0 for a root swarm
        bytes32        predecessorId;      // succession; 0 when none
        bytes32        successorId;        // set when SUPERSEDED
        address        account;            // swarm account; 0 when none
        LifecycleState state;
        OutcomeType    outcome;
        Reason         reason;
        bytes32        resultHash;
        uint32         phase;
        uint32         rosterPhase;        // last phase entered through SELECT or RECRUIT (lazy roster-wide exits)
        uint64         revision;           // incremented by every state-changing call
        uint64         formedAt;
        uint64         activatedAt;
        uint64         phaseStartedAt;
        uint64         suspendedAt;
        uint64         concludedAt;
        uint64         dissolvedAt;
        uint64         lastAmendedAt;
        uint64         exitWindowUntil;    // end of the current material-amendment exit window
        uint64         lastActivity;
    }

    // ------------------------------------------------------------------ membership

    enum MemberStatus { NONE, CANDIDATE, ACTIVE, SUSPENDED, EXITED }

    enum SuspensionCause { NONE, AUTHORITY, INELIGIBLE }

    enum ExitReason {
        NONE,
        LEFT,             // the member (or candidate) left
        REMOVED,          // the REMOVE authority removed the member (the ADMIT authority, for a candidate)
        INELIGIBLE,       // expelled after the ineligible grace period
        NOT_CARRIED,      // not carried into a SELECT or RECRUIT phase
        REPLACED,         // substituted by a successor account
        SWARM_DISSOLVED   // the swarm dissolved
    }

    struct Member {
        bytes32         roleId;
        MemberStatus    status;              // stored status; memberStatus() derives lazy exits
        SuspensionCause suspension;
        ExitReason      exitReason;
        bool            admitted;            // the authority side of admission is done
        bool            accepted;            // the member side is done for some version
        bool            substituted;         // seat opened by substitution: completion is exempt from boundary, window and maximum checks
        uint32          admittedPhase;
        uint32          carriedPhase;        // last phase this seat was carried into
        uint64          admittedAt;
        uint64          suspendedAt;
        uint64          exitedAt;
        uint64          lastActivity;
        bytes32         acceptedCharter;     // charterHash most recently accepted
        uint32          acceptedVersion;     // charterVersion most recently accepted
        uint32          acceptedCommitment;  // commitmentVersion most recently accepted
    }

    // ------------------------------------------------------------------ resources

    /// A non-principal element attached to a swarm: a token-bound executable skill, a dataset,
    /// a tool endpoint, a code digest, a model reference, a document, an oracle, a fund.
    /// Resources hold no seat, pass no eligibility check and receive no allocation.
    struct ResourceInput {
        bytes32 kind;        // keccak256("sai.resource.<name>")
        uint256 chainId;     // on-chain anchor; zero when the resource has none
        address target;
        uint256 id;
        bytes32 digest;      // commitment to the resource content; MUST be nonzero
        bytes32 digestKind;  // how `digest` was computed: keccak256("sha-256"), keccak256("keccak256"), or an adapter-defined kind
        string  uri;         // transport hint
        bytes32 roleId;      // role permitted to use it; 0 = every role
        address provider;    // who provides or manages the resource; 0 = unspecified
    }

    struct Resource {
        bytes32 kind;
        uint256 chainId;
        address target;
        uint256 id;
        bytes32 digest;
        bytes32 digestKind;
        string  uri;
        bytes32 roleId;
        address provider;
        address attachedBy;
        uint64  attachedAt;
        bool    detached;
    }
}
