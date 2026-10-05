// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  ACDF — Agent Collective Decision Framework: shared types (reference v0.2)
/// @notice Every parameter that influences eligibility, voting weight, thresholds,
///         composition, timing or finality lives in `PolicySpec`. The policy id is
///         keccak256(abi.encode(PolicySpec)), so the registered rule and the executed
///         rule are one and the same object (no "JSON says 3-of-5, contract runs K=2").
///         The off-chain descriptor is referenced by `descriptorHash` and is
///         informative only.
library ACDFTypes {
    // ------------------------------------------------------------------ policy

    /// Built-in, fixed-version body kinds. The v0.2 kernel is non-upgradeable and
    /// has no pluggable external modules; dependency pinning is therefore trivial.
    enum BodyKind {
        ROSTER_KOFN,          // fixed roster, equal weight, K approvals / N-K+1 blocks
        AUTHORIZED_SUBMITTER  // one pre-pinned account/contract submits the body result
    }

    /// Result-acceptance mode, bound to a BODY (not to the whole policy).
    enum Acceptance {
        ON_CHAIN_TALLY,       // each ballot is a transaction by the voter
        SIGNED_BALLOTS,       // EIP-712 ballots, batch-submitted by anyone, same tally semantics
        AUTHORIZED_SUBMITTER  // the pinned submitter reports the body result; nothing re-tallied
    }

    enum Combinator { BODY, ALL, ANY, KOFM, VETO }

    /// What silence of the veto body means once the veto window closes.
    enum VetoSilence { PASS_THROUGH, REQUIRE_CLEARANCE }

    enum AppealStanding { ANYONE, CONSUMER_OR_FILER }

    struct BodySpec {
        BodyKind   kind;
        Acceptance acceptance;
        address[]  members;   // ROSTER_KOFN: roster (unique, non-zero); AUTHORIZED_SUBMITTER: exactly one
        uint32     k;         // ROSTER_KOFN: approvals needed, 1 <= k <= N; ignored otherwise
        uint64     window;    // seconds from round start during which input is accepted; > 0
    }

    struct Node {
        Combinator  op;
        uint32      body;      // BODY: index into bodies
        uint32      k;         // KOFM: required child approvals
        uint32      target;    // VETO: index of the guarded node (> own index)
        uint32      vetoBody;  // VETO: index of the veto body (its window is the veto window)
        VetoSilence silence;   // VETO
        uint32[]    children;  // ALL / ANY / KOFM: child node indices (> own index, unique)
    }

    struct PolicySpec {
        bytes32        family;           // policy family id; first version claims it
        uint32         version;          // strictly increasing within a family
        bytes32        previous;         // previous policyId in the family, or 0 for the first
        address        updateAuthority;  // who may publish the next version of this family
        BodySpec[]     bodies;
        Node[]         nodes;            // nodes[0] is the root
        uint32         maxAppeals;       // extra rounds allowed after the first
        uint64         appealWindow;     // seconds after a round's result during which an appeal may be filed
        uint8          appealable;       // bit0: Decided results appealable; bit1: NoDecision results appealable
        AppealStanding appealStanding;
        uint64         maxTotalDuration; // hard cap from admission; must cover every round and appeal window
        uint64         ackWindow;        // POST_ACK acknowledgment window; 0 disables POST_ACK
        bool           allowAdvisory;    // may an unacknowledged POST_ACK issue be admitted as Advisory
        bytes32        descriptorHash;   // informative: hash of the off-chain JSON descriptor
    }

    // ------------------------------------------------------------------ issue

    enum ProcedureState { None, Filed, Deciding, Provisional, Final, Withdrawn }
    enum OutcomeType    { None, Decided, NoDecision }
    enum AcceptanceMode { CONSUMER_FILED, STANDING_ACCEPTANCE, POST_ACK }
    enum EffectClass    { Advisory, Binding }
    enum NodeStatus     { Pending, Yes, No, NoDecision }

    enum Reason {
        NONE,
        QUORUM_NOT_MET,     // roster body closed without K approvals or N-K+1 blocks
        SUBMITTER_SILENT,   // authorized submitter did not report within its window
        VETOED,             // veto body exercised its veto within the window
        NO_CLEARANCE,       // REQUIRE_CLEARANCE veto body neither vetoed nor cleared
        NOT_REACHED,        // composite could not be determined from its children
        TOTAL_TIMEOUT,      // hard cap reached with the round still pending
        NO_ACCEPTANCE       // POST_ACK window lapsed without acknowledgment
    }

    enum EnactmentStatus { NotEnacted, Enacted, Failed }

    struct Subject {
        uint256 chainId;
        address target;
        uint256 id;
        bytes32 dataHash;
    }

    struct IssueInput {
        bytes32        policyId;
        AcceptanceMode mode;
        bytes32        acceptanceId;     // STANDING_ACCEPTANCE: the acceptance record
        address        consumer;         // CONSUMER_FILED: must equal msg.sender; POST_ACK: expected acknowledger
        Subject        subject;
        bytes32        question;
        bytes32        effectYes;        // CONSUMER_FILED: committed by the consumer; POST_ACK: proposal only
        bytes32        effectNo;
        bytes32        disposition;      // what the consumer does on NoDecision (opaque reference)
        uint64         consumerDeadline; // 0 = none; otherwise admission requires admittedAt + maxTotalDuration <= deadline
    }

    struct StandingAcceptanceInput {
        bytes32   policyId;        // exact policy version accepted
        address   subjectTarget;   // 0 = any
        bytes32   question;        // 0 = any
        address[] filers;          // empty = anyone
        bytes32   effectYes;
        bytes32   effectNo;
        bytes32   disposition;
        uint64    validUntil;      // 0 = none
    }

    struct Issue {
        bytes32        policyId;
        AcceptanceMode mode;
        EffectClass    effectClass;
        ProcedureState state;
        address        filer;
        address        consumer;
        bytes32        acceptanceId;
        Subject        subject;
        bytes32        question;
        bytes32        effectYes;
        bytes32        effectNo;
        bytes32        disposition;
        bytes32        obligationKey;
        uint64         filedAt;
        uint64         admittedAt;
        uint64         consumerDeadline;
        uint64         hardDeadline;
        uint64         finalAt;
        uint32         roundCount;
        // adopted result (valid once state == Final)
        OutcomeType    outcomeType;
        bool           outcomeYes;
        Reason         reason;
        uint32         sourceRound;   // 1-based round whose decision was adopted; 0 if none
        uint64         decidedAt;
    }

    struct RoundState {
        uint64     startedAt;
        uint64     deadline;        // startedAt + roundDuration(policy)
        bool       settled;
        NodeStatus status;          // root status when settled
        Reason     reason;
        uint64     at;              // instant the root value became determined
        uint64     appealOpenUntil; // at + appealWindow when an appeal was possible; else 0
    }

    struct BodyState {
        uint32     yes;
        uint32     no;
        bool       submitted;   // AUTHORIZED_SUBMITTER
        NodeStatus submitted_;  // AUTHORIZED_SUBMITTER: Yes / No / NoDecision as submitted
        uint64     decidedAt;   // instant the body became Decided (0 if not)
    }

    struct Enactment {
        EnactmentStatus status;
        address         reporter;
        bytes32         ref;
        uint64          at;
    }

    struct Result {
        ProcedureState state;
        OutcomeType    outcomeType;
        bool           outcomeYes;
        Reason         reason;
        uint64         decidedAt;
        uint64         finalAt;
        bytes32        policyId;
        uint32         roundCount;
        uint32         sourceRound;
        EffectClass    effectClass;
        address        consumer;
        bytes32        effectYes;
        bytes32        effectNo;
        bytes32        disposition;
    }
}
