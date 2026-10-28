// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  ADRF — AI Dispute Resolution Framework: shared types (reference v0.1)
/// @notice Four core objects (Dispute Policy, Dispute Binding, Case, Ruling) and two auxiliary records
///         (Report, Enactment). Every parameter that the registries execute lives in `PolicySpec`;
///         `policyId = keccak256(abi.encode(PolicySpec))`, so the registered rule and the executed rule
///         are one object. Off-chain documents are referenced by hash and never influence execution.
library ADRFTypes {
    // ------------------------------------------------------------------ vocabularies

    /// Sub-question type: what kind of answer can exist for the proposition.
    enum QuestionType {
        FORMAL,    // decidable by a deterministic verifier contract over pinned inputs
        EVIDENCED, // decidable by an evidence rule over material supplied under that rule
        JUDGED     // decidable by a judgment method (reference: an ERC-8436 collective decision)
    }

    /// Value of a finding. UNDETERMINED is a legitimate, final value of a resolved sub-question.
    enum Value { UNDETERMINED, TRUE, FALSE }

    /// How a binding establishes the respondent's acceptance of the procedure.
    enum AcceptanceMode {
        PRE_COMMIT,   // the obligation source accepted the procedure before the event; filing admits atomically
        POST_DISPUTE  // the respondent accepts after filing and before any hearing; otherwise the case is not admitted
    }

    enum EffectClass { Advisory, Binding }

    /// Category of an effect identifier declared by a policy.
    enum EffectCategory {
        SUBSTANTIVE,          // a remedy on the object or obligation (refund, withhold, mark, release)
        PROCEDURAL_ECONOMIC   // a consequence of the procedure itself (bond flows, fee allocation, rewards)
    }

    /// What an UNDETERMINED decisive finding means for the claim (the burden rule of a method binding).
    enum OnUndetermined { NOT_SUSTAINED, NO_DECISION }

    /// Who may start a Binding procedure (standing level L1); a binding may narrow, never widen.
    enum StandingMode { PARTIES, BENEFICIARIES, OPEN }

    /// Optimistic track: what the respondent's silence within the answer window means.
    enum SilenceRule { NONE, SUSTAIN, NOT_SUSTAIN }

    /// What a review round that ends without a substantive result means for the decision under review.
    enum ReviewMode { PRESERVE_UNLESS_OVERTURNED, REQUIRE_FRESH_DECISION }

    /// Procedure state (one of four dimensions of a case). Admitted covers evidence and resolution
    /// ("resolving"); Provisional means a round decision exists and a review window is open.
    enum ProcedureState { None, Filed, Admitted, Provisional, Final, NotAdmitted, Withdrawn, Expired }

    /// Substantive result (second dimension). Sustained always means "the claim was supported".
    enum SubstantiveResult { None, Sustained, NotSustained, NoDecision }

    /// Reason codes (third dimension). They explain a state or a result; they are never a verdict on the merits.
    enum Reason {
        NONE,
        MISSING_ELEMENT,          // an element of the eight-element case record is missing
        NO_BINDING_AUTHORITY,     // no binding covers the object, or a requested effect is not authorized
        CLOCK_INCOMPATIBLE,       // the business window cannot hold the procedure plus the enactment margin
        DUPLICATE,                // an active or final Binding case already holds the exclusivity key
        PREMISE_NOT_ESTABLISHED,  // a dependency finding has a value other than the required one
        METHOD_UNDETERMINED,      // the method returned UNDETERMINED (verifier, evidence rule or judgment)
        BURDEN_NOT_MET,           // UNDETERMINED decisive finding mapped to NotSustained by the burden rule
        TIMEOUT,                  // a window lapsed without the required step
        REVIEW_LAPSED,            // the review window lapsed; the provisional decision was adopted
        ACCEPTANCE_LAPSED,        // POST_DISPUTE: the respondent did not accept in time
        SILENCE,                  // optimistic track: the respondent did not answer; the silence rule applied
        PROCEDURE_FAILURE         // a required step could not be completed (method unavailable, revert)
    }

    /// Enactment status per effect (fourth dimension). Unknown is not Failed.
    enum EnactmentStatus { NotRequested, Pending, Enacted, Failed, Unknown }

    /// Support kinds of a finding (bit set; several may apply; no ordering is defined).
    uint8 internal constant SUPPORT_SIGNED = 1;
    uint8 internal constant SUPPORT_COMPUTED = 2;
    uint8 internal constant SUPPORT_EVIDENCED = 4;
    uint8 internal constant SUPPORT_JUDGED = 8;

    /// Review types (bit set in `Track.reviewTypes`).
    uint8 internal constant REVIEW_FACT = 1;
    uint8 internal constant REVIEW_EVIDENCE = 2;
    uint8 internal constant REVIEW_RULE_APPLICATION = 4;
    uint8 internal constant REVIEW_CONFLICT = 8;
    uint8 internal constant REVIEW_PROCEDURE = 16;

    /// Result profile implemented by this version of the kernel. A consumer that does not know a
    /// policy's result profile MUST reject its rulings instead of reading them as booleans.
    bytes32 internal constant RESULT_PROFILE_V1 = keccak256("adrf:result/v1");

    uint256 internal constant MAX_SUB_QUESTIONS = 16;
    uint256 internal constant MAX_METHODS = 32;
    uint256 internal constant MAX_EFFECTS = 32;

    // ------------------------------------------------------------------ object reference

    struct ObjectRef {
        uint256 chainId;
        address target;      // the registry, namespace or contract that holds the object
        uint256 id;          // the object within the target
        bytes32 versionHash; // content hash or version pin of the object as evaluated
    }

    // ------------------------------------------------------------------ policy

    /// Binds one (obligation kind, question type) pair to a method contract.
    struct MethodBinding {
        uint8        obligationKind;  // 0 = any kind; otherwise the kind this entry serves
        QuestionType qType;
        address      method;          // FORMAL: IADRFVerifier; EVIDENCED: IADRFEvidenceRule; JUDGED: IADRFJudgmentMethod
        bytes32      params;          // opaque parameters passed to the method (JUDGED reference: the ERC-8436 policyId)
        OnUndetermined onUndetermined;
    }

    struct Effect {
        bytes32        id;
        EffectCategory category;
    }

    /// Procedure strength parameters. Windows are seconds of the registry clock.
    struct Track {
        uint64     filingWindow;      // from the event instant: a case may be filed until eventAt + filingWindow
        uint64     acceptanceWindow;  // POST_DISPUTE: the respondent may accept until filedAt + acceptanceWindow; 0 disables the mode
        uint64     evidenceWindow;    // from admission (and from each review): evidence may be attached until then
        uint64     decisionWindow;    // from admission (and from each review): the decisive finding must exist by then
        uint64     reviewWindow;      // from a round decision: a review may be requested until then
        uint32     maxReviews;        // review rounds allowed after the first
        uint8      reviewTypes;       // bit set of review types that may be requested
        ReviewMode reviewMode;
        uint64     maxTotalDuration;  // hard cap from admission (T_max)
        uint64     enactmentMargin;   // M: time the business window must keep after T_max for enactment
        bool       optimistic;        // the respondent must answer within answerWindow or the silence rule applies
        uint64     answerWindow;      // optimistic: from admission
        SilenceRule silenceRule;      // optimistic: meaning of silence
    }

    struct PolicySpec {
        bytes32         family;
        uint32          version;
        bytes32         previous;            // previous policyId in the family, or 0 for the first
        address         updateAuthority;     // who may publish the family's next version
        bytes32         objectKind;          // informative object kind label the policy serves (0 = any)
        MethodBinding[] methods;
        Effect[]        effects;
        Track           track;
        StandingMode    standing;            // widest standing a binding under this policy may grant
        bytes32         resultProfile;       // MUST equal RESULT_PROFILE_V1 for this kernel version
        bytes32         economicDeclaration; // hash of the economic declaration document (informative)
        bytes32         descriptorHash;      // hash of the full policy document (informative)
    }

    // ------------------------------------------------------------------ binding

    struct BindingInput {
        bytes32        policyId;
        bytes32        scopeKey;           // 0 = any object of the source; otherwise keccak256(abi.encode(ObjectRef))
        AcceptanceMode mode;
        bytes32[]      authorizedEffects;  // subset of the policy's effect identifiers
        address[]      executors;          // accounts that may report enactment besides the source
        address[]      beneficiaries;      // third parties with filing standing (policy standing >= BENEFICIARIES)
        bool           openChallenge;      // anyone may file (policy standing == OPEN)
        bool           downgradeOnClock;   // admit as Advisory when the business window is too short
        uint64         validUntil;         // 0 = none; stops new filings only
        bytes32        termsHash;          // hash of the binding document (fund authorization, third-party terms)
    }

    struct Binding {
        address        source;             // the obligation source (msg.sender of bind)
        bytes32        policyId;
        bytes32        scopeKey;
        AcceptanceMode mode;
        bool           openChallenge;
        bool           hasBeneficiaries;
        bool           downgradeOnClock;
        bool           revoked;
        uint64         validUntil;
        uint64         createdAt;
        bytes32        termsHash;
    }

    /// What an obligation source attests about an event on one of its objects.
    struct EventInfo {
        bool    known;
        uint64  eventAt;          // instant of the contested event or state
        uint64  adoptionDeadline; // last instant at which the source can still adopt a ruling; 0 = none
        bytes32 obligationRef;    // the business obligation the event belongs to (exclusivity scope)
        bytes32 normRef;          // the norm the source recognises for this obligation (0 = not attested)
        uint64  normDeclaredAt;   // when that norm was declared; MUST NOT be later than eventAt
        uint8   obligationKind;   // 0 = not attested
    }

    // ------------------------------------------------------------------ case

    struct SubQuestionInput {
        bytes32      proposition;
        QuestionType qType;
        uint8        obligationKind;
        bytes32      inputsHash;      // FORMAL: keccak256 of the inputs that will be passed to the verifier
        uint32[]     dependsOn;       // indices of sub-questions whose findings are premises
        Value[]      requiredValues;  // required value of each premise (same length as dependsOn)
    }

    struct ClaimInput {
        ObjectRef         object;
        bytes32           eventRef;
        bytes32           proposition;           // the contested point (hash of the claim statement)
        bytes32           normRef;
        bytes32           clause;
        uint8             obligationKind;
        address           respondent;
        bytes32[]         requestedEffects;      // substantive effects requested (Binding: subset of the authorized set)
        bytes32           effectOnSustained;     // one of requestedEffects, or 0
        bytes32           effectOnNotSustained;  // one of requestedEffects, or 0
        bytes32           fallbackRef;           // reference to the pre-committed NoDecision disposition
        bytes32           evidenceScopeHash;
        bytes32           documentHash;          // hash of the eight-element case document
        uint32            decisive;              // index of the decisive sub-question
        Value             supportsWhen;          // the claim is Sustained iff the decisive finding has this value
        SubQuestionInput[] subQuestions;
    }

    struct SubQuestion {
        bytes32      proposition;
        QuestionType qType;
        uint8        obligationKind;
        bytes32      inputsHash;
        address      method;
        bytes32      params;
        OnUndetermined onUndetermined;
        uint32[]     dependsOn;
        Value[]      requiredValues;
        bytes32      handle;          // JUDGED: handle returned by the method when opened
    }

    /// Provenance of a JUDGED finding.
    struct JudgmentSource {
        address registry;
        bytes32 issueId;
        bytes32 policyId;
        uint32  sourceRound;
        uint32  roundCount;
        bool    adoptedFromEarlierRound;
        uint8   reason;      // the source registry's own reason code
    }

    struct Finding {
        bool           resolved;
        Value          value;
        uint8          supportKinds;  // bit set of SUPPORT_*
        bytes32        resultHash;
        address        acceptedBy;    // the method that produced the finding (0 for a kernel-recorded one)
        Reason         reason;
        uint32         round;
        uint64         at;
        JudgmentSource source;
    }

    struct RoundRecord {
        SubstantiveResult result;
        Reason            reason;
        uint64            at;
        bool              bySilence;
        uint8             supportKinds;  // union of the support kinds of the findings the result cites (provenance only)
        Value             decisiveValue;
        JudgmentSource    judgment;      // provenance of the decisive finding when it was JUDGED
    }

    struct CaseHeader {
        bytes32        policyId;
        bytes32        bindingId;        // 0 for an Advisory case filed without a binding
        address        source;           // 0 for an Advisory case
        EffectClass    effectClass;
        ProcedureState state;
        address        claimant;
        address        respondent;
        ObjectRef      object;
        bytes32        eventRef;
        bytes32        proposition;
        bytes32        normRef;
        bytes32        clause;
        uint8          obligationKind;
        bytes32        obligationRef;
        bytes32        exclusivityKey;   // keccak256(abi.encode(source, obligationRef, proposition)) for Binding cases
        bytes32        effectOnSustained;
        bytes32        effectOnNotSustained;
        bytes32        fallbackRef;
        bytes32        evidenceScopeHash;
        bytes32        documentHash;
        uint32         decisive;
        Value          supportsWhen;
        uint32         subQuestionCount;
    }

    struct CaseClock {
        uint64 eventAt;
        uint64 filedAt;
        uint64 admittedAt;
        uint64 evidenceCloseAt;
        uint64 decisionDeadline;
        uint64 hardDeadline;
        uint64 reviewOpenUntil;
        uint64 answerDeadline;   // optimistic
        bool   answered;         // optimistic
        uint32 roundCount;
        uint32 reviewsUsed;
    }

    /// The terminal record of a case (valid once state is Final or Expired).
    struct Ruling {
        ProcedureState    state;
        SubstantiveResult result;
        EffectClass       effectClass;
        Reason            reason;          // reason of the adopted result (never a verdict on the merits)
        Reason            closure;         // how the procedure closed: NONE, REVIEW_LAPSED or TIMEOUT
        uint64            decidedAt;
        uint64            finalAt;
        uint32            roundCount;
        uint32            sourceRound;
        bool              adoptedFromEarlierRound;
        bool              bySilence;
        uint8             supportKinds;     // provenance of the adopted round (union; confers nothing)
        bytes32           allowedEffect;    // the substantive effect the result authorizes (0 = none)
        bytes32           fallbackRef;      // NoDecision: the pre-committed disposition reference
        bytes32           policyId;
        bytes32           bindingId;
        address           source;
        bytes32           proposition;
        JudgmentSource    judgment;         // provenance of the decisive finding when it was JUDGED
    }

    struct Enactment {
        EnactmentStatus status;
        address         reporter;
        bytes32         ref;
        uint64          at;
    }
}
