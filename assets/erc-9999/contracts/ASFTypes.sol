// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title  ASFTypes — shared types of the Agent Safety and Security Framework (ASF)
/// @notice Two registry objects (Safety Specification, Safety Binding), the binding lifecycle,
///         the response-requirement bit set of suspensions, the enforcement-location bit set,
///         intervener rights and the requirement grammar consumed by `check`.
library ASFTypes {
    // ------------------------------------------------------------------ specification registry

    /// @notice One immutable version of a Safety Specification.
    struct SpecificationVersion {
        bytes32 contentHash;        // keccak256(UTF-8(JCS(document)))
        string locator;             // where the document can be fetched; mutable, the hash is not
        uint64 publishedAt;         // block.timestamp of publication
        bool deprecated;            // publisher's informative signal; never changes a binding
        bytes32[] requiredProfiles; // profile identifiers a consumer MUST understand to rely on the version
    }

    // ----------------------------------------------------------------------- binding registry

    /// @notice Lifecycle of a Safety Binding. `None` means the record does not exist.
    enum BindingState {
        None,       // 0 — no record
        Active,     // 1 — the adopter maintains the adoption
        Suspended,  // 2 — the adoption is paused under a set of response requirements
        Terminated  // 3 — the adoption ended; terminal, the record is never reused
    }

    /// @notice Response requirements that accompany a suspension, as a combinable bit set. They are
    ///         different dimensions of one response (prohibitions, capability reductions, duties to continue,
    ///         permitted recovery paths, a stop target) and can be set together; the response document
    ///         referenced by `responseRef` carries scope, parameters, in-flight handling, duration and who may
    ///         resume. `RESTRICT_FULL_STOP` dominates every other bit for the paths it covers.
    uint8 internal constant RESTRICT_NO_NEW_RISK = 1;    // no action that adds exposure, obligations or counterparties
    uint8 internal constant RESTRICT_SHRINK = 2;         // only actions that reduce scope, exposure or authority
    uint8 internal constant RESTRICT_ESSENTIAL_ONLY = 4; // the duties a profile lists as necessary continue
    uint8 internal constant RESTRICT_DERISK_ONLY = 8;    // unwinding, repayment, cancellation and recovery stay open
    uint8 internal constant RESTRICT_FULL_STOP = 16;     // nothing under the binding may proceed
    uint8 internal constant RESTRICT_ALL = 31;

    /// @notice Intervener rights bit set.
    uint8 internal constant RIGHT_SUSPEND = 1;
    uint8 internal constant RIGHT_RESUME = 2;
    uint8 internal constant RIGHT_TERMINATE = 4;
    uint8 internal constant RIGHT_ALL = 7;

    /// @notice Enforcement-location bit set (where the adopted arrangement is actually enforced).
    ///         Ordered from the weakest to the strongest independence from the bound subject.
    uint16 internal constant ENFORCED_SELF = 1;        // the subject promises to comply
    uint16 internal constant ENFORCED_ACCOUNT = 2;     // the subject's account or wallet enforces
    uint16 internal constant ENFORCED_RUNTIME = 4;     // the execution environment enforces
    uint16 internal constant ENFORCED_CUSTODIAN = 8;   // a resource custodian or API enforces
    uint16 internal constant ENFORCED_CONTRACT = 16;   // an on-chain contract or guard enforces
    uint16 internal constant ENFORCED_COLLECTIVE = 32; // a collective decision mechanism enforces

    /// @notice Maximum depth of a derived-binding chain (root has depth 0).
    uint8 internal constant MAX_DEPTH = 8;

    /// @notice An account entitled to some lifecycle transitions of a binding besides the adopter.
    struct Intervener {
        address account;
        uint8 rights; // bit set of RIGHT_*
    }

    /// @notice Input of `adopt`. The adopter is always `msg.sender`.
    struct BindingInput {
        bytes32 subjectKey;        // keccak256(UTF-8(subject reference))
        bytes32 scopeKey;          // keccak256(UTF-8(JCS(scope object)))
        address specRegistry;      // Specification Registry holding the adopted version
        bytes32 specId;
        uint32 version;
        bytes32 contentHash;       // pinned; MUST equal the registry's content hash of that version
        bytes32 paramsHash;        // keccak256(UTF-8(JCS(binding parameters document)))
        string paramsLocator;
        bytes32 authorityRef;      // opaque reference to the external permission basis
        uint16 enforcement;        // bit set of ENFORCED_*
        uint64 validFrom;          // 0 = from creation
        uint64 validUntil;         // 0 = open-ended
        bytes32 parentBindingId;   // 0 = root binding
        bytes32 salt;
        Intervener[] interveners;
    }

    /// @notice Stored binding record.
    struct Binding {
        address adopter;
        bytes32 subjectKey;
        bytes32 scopeKey;
        address specRegistry;
        bytes32 specId;
        uint32 version;
        bytes32 contentHash;
        bytes32 paramsHash;
        string paramsLocator;
        bytes32 authorityRef;
        uint16 enforcement;
        uint64 validFrom;
        uint64 validUntil;
        bytes32 parentBindingId;
        uint8 depth;
        uint64 createdAt;
        uint64 stateChangedAt;
        BindingState state;
        uint8 restrictions;        // bit set of RESTRICT_* while Suspended, else 0
        bytes32 responseRef;       // content hash of the response document while Suspended, else 0
        address suspendedBy;       // account that recorded the current suspension while Suspended, else 0
    }

    // ------------------------------------------------------------------------- requirements

    /// @notice Result of a registry-level check. `Unknown` never satisfies a requirement.
    enum Verdict {
        Unknown,      // 0 — a dependency of the check could not be evaluated
        Satisfied,    // 1
        NotSatisfied  // 2
    }

    /// @notice Reason attached to a clause result (the first failing check in evaluation order).
    enum Reason {
        None,                   // 0 — satisfied
        NoBinding,              // 1 — no binding supplied or unknown binding id
        Terminated,             // 2
        Suspended,              // 3 — see the returned restrictions bit set
        NotYetValid,            // 4 — before max(validFrom, createdAt)
        Expired,                // 5 — after validUntil
        SpecMismatch,           // 6 — other specRegistry or specId
        VersionMismatch,        // 7 — version not in the clause's allowed set
        AdopterMismatch,        // 8
        SubjectMismatch,        // 9
        ScopeMismatch,          // 10
        EnforcementMismatch,    // 11 — required enforcement locations not all declared
        ParentNotSatisfied,     // 12 — an ancestor binding is not currently satisfied
        SpecRegistryUnavailable,// 13 — the specification registry could not be queried (Unknown)
        IntervenerMismatch      // 14 — a required intervener is missing or holds fewer rights than required
    }

    /// @notice How the clause results of a requirement set combine.
    enum Combinator {
        All, // 0 — every clause
        Any, // 1 — at least one clause
        KOf  // 2 — at least `k` clauses
    }

    /// @notice One clause of a requirement set. Zero values are wildcards for `adopter`, `subjectKey`,
    ///         `scopeKey` and `enforcement`; an empty `versions` list admits every version. `interveners`
    ///         lists accounts that the binding must name as interveners with at least the given rights;
    ///         an entry whose account is zero stands for some intervener other than the adopter.
    struct Clause {
        address specRegistry;
        bytes32 specId;
        uint32[] versions;
        address adopter;
        bytes32 subjectKey;
        bytes32 scopeKey;
        uint16 enforcement;
        Intervener[] interveners;
    }

    struct RequirementSet {
        Combinator combinator;
        uint16 k;          // used by KOf only
        Clause[] clauses;
    }
}
