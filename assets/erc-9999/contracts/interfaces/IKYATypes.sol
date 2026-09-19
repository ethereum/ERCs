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

    struct Scheme {
        address controller;
        string schemeURI;
        bytes32 schemeHash;
        uint8 mode;
        address verifier;    // non-zero iff mode == PROVED
        bytes32 predecessor; // previous version's schemeId or 0x0
        bool frozen;
    }

    struct Assertion {
        bytes32 subjectKey;
        bytes32 schemeId;
        address issuer;      // attester (ATTESTED) or verifier contract (PROVED)
        uint8 level;
        bytes32 claimDigest;
        uint64 issuedAt;
        uint64 expiresAt;    // 0 = no expiry (NOT RECOMMENDED)
        bytes32 evidenceHash;
        uint8 status;        // AssertionStatus
    }

    // ---- errors ---------------------------------------------------------
    error KYA_SchemeNotFound(bytes32 schemeId);
    error KYA_ModeMismatch(bytes32 schemeId, uint8 expected, uint8 actual);
    error KYA_InvalidMode(uint8 mode);
    error KYA_VerifierRequired();
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
