// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title ERC-KYA shared types
/// @notice Common structs, enums and errors for the Know-Your-Agent (KYA) Framework.
interface IKYATypes {
    /// @dev A KYA subject: the entity an assertion is about.
    ///      subjectKey = keccak256(abi.encode(subjectType, subjectData))
    struct Subject {
        bytes32 subjectType; // keccak256 of a registered type string, e.g. keccak256("erc8004")
        bytes subjectData;   // ABI-encoded per subjectType
    }

    /// @dev Scheme admission mode. Values >= 2 are reserved for future profiles.
    enum SchemeMode {
        ATTESTED, // 0: assertions recorded by an issuer
        PROVED    // 1: assertions admitted by an IKYAVerifier (ZK-KYA profile)
    }

    enum AssertionStatus {
        ACTIVE,
        REVOKED,
        SUPERSEDED
    }

    /// @dev What an assertion under a scheme attaches to (Section 2.1). Values >= 3 reserved.
    enum BindingKind {
        IDENTITY,   // 0: the subject record itself
        CONTROLLER, // 1: the party controlling the subject at issuance (erc8004: ERC-721 owner)
        INSTANCE    // 2: a specific code/model/config instance committed by claimDigest
    }

    /// @dev Result of evaluating an assertion's binding predicate at resolution time.
    enum BindingStatus {
        NOT_APPLICABLE, // 0: identity-bound; nothing to evaluate
        SATISFIED,      // 1: witness still matches current state
        VIOLATED,       // 2: current state differs from the witness (e.g. controller changed)
        UNEVALUABLE     // 3: registry cannot evaluate natively (foreign chain / unknown subject type)
    }

    /// @dev A scheme's semantics (schemeHash, mode, verifier, predecessor) are IMMUTABLE after
    ///      registration; only the descriptor pointer (schemeURI) may be re-pointed to another copy
    ///      of the same bytes. Any semantic change is a new scheme with `predecessor` set.
    struct Scheme {
        address controller;
        string schemeURI;
        bytes32 schemeHash;       // keccak256 of the descriptor bytes; MUST be non-zero
        uint8 mode;
        uint8 binding;            // BindingKind
        address verifier;         // non-zero iff mode == PROVED
        bytes32 verifierCodehash; // EXTCODEHASH of verifier at registration (PROVED); pinned
        bytes32 predecessor;      // previous version's schemeId or 0x0
        bool frozen;
    }

    struct Assertion {
        bytes32 subjectKey;
        bytes32 schemeId;
        address issuer;      // attester (ATTESTED) or admitting verifier contract (PROVED)
        uint8 level;         // scheme-defined ordinal result; 0 when the scheme is not ordered
        bytes32 claimDigest; // commitment to the scheme-defined result / disclosed claims
        uint64 issuedAt;
        uint64 expiresAt;    // 0 = no expiry (NOT RECOMMENDED)
        bytes32 evidenceHash;
        bytes32 anchor;         // PROVED: verifier-defined trust anchor (e.g. issuer-set root); ATTESTED: 0x0
        bytes32 bindingWitness; // committed binding state at issuance (CONTROLLER: keccak256(abi.encode(controller)); INSTANCE: claimDigest; IDENTITY: 0x0)
        uint8 status;           // AssertionStatus
    }

    // ---- errors ---------------------------------------------------------
    error KYA_SchemeNotFound(bytes32 schemeId);
    error KYA_ModeMismatch(bytes32 schemeId, uint8 expected, uint8 actual);
    error KYA_InvalidMode(uint8 mode);
    error KYA_VerifierRequired();
    error KYA_SchemeHashRequired();
    error KYA_InvalidBinding(uint8 binding);
    error KYA_VerifierNotContract(address verifier);
    error KYA_VerifierCodeChanged(bytes32 schemeId, bytes32 expected, bytes32 actual);
    error KYA_BindingUnevaluable(bytes32 subjectKey, uint8 binding);
    error KYA_VerifierRejected();
    error KYA_SubjectMismatch(bytes32 expected, bytes32 actual);
    error KYA_NullifierUsed(bytes32 schemeId, bytes32 nullifier);
    error KYA_EmptyIssuers();
    error KYA_Frozen(bytes32 schemeId);
    error KYA_NotController(bytes32 schemeId, address caller);
    error KYA_NotIssuer(bytes32 assertionId, address caller);
    error KYA_AssertionNotFound(bytes32 assertionId);
    error KYA_AssertionNotActive(bytes32 assertionId);
    error KYA_BadPredecessor(bytes32 predecessor);
    error KYA_Expired(uint64 expiresAt);
    error KYA_PolicyNotFound(bytes32 policyId);
    error KYA_NoOnchainRules(bytes32 policyId);
}
