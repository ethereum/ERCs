// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title AUF shared types
/// @notice Structs and enums shared by the AIFi Unit Framework registries.

/// @notice Reference to a specific version of a Unit kept in the same Unit Registry.
struct UnitRef {
    uint256 unitId;
    uint32 version;
}

/// @notice Acknowledgment kinds (Section 5). Values above 4 are reserved for extensions.
enum AckKind {
    None, // 0, invalid
    Participation, // 1 the acknowledging account takes part in the Unit
    ResourceUse, // 2 the acknowledging account authorizes the stated use of the element
    FundOperation, // 3 the acknowledging account authorizes the stated fund operation
    DescriptionEndorsement // 4 the acknowledging account endorses the description of the element
}

/// @notice Assertion kinds (Section 6.1).
enum AssertionKind {
    None, // 0, invalid
    Characterization, // 1
    Observation, // 2
    Valuation, // 3
    Extension // 4
}

/// @notice Assertion status (Section 6.4).
enum AssertionStatus {
    None, // 0, unknown assertion
    Active, // 1
    Revoked, // 2
    Superseded // 3
}

/// @notice Input of `assertStatement` and `assertStatementBySig` (Section 11).
struct AssertionInput {
    AssertionKind kind;
    uint256 unitId;
    uint32 version;
    bytes32 profileId;
    bytes32 contentHash;
    string contentURI;
    uint64 validFrom;
    uint64 validUntil;
    bytes32 supersedes;
    bytes payload; // ABI-encoded ValuationCore for Valuation, ObservationCore for Observation, empty otherwise
}

/// @notice Stored assertion envelope (Section 6.1).
struct Assertion {
    AssertionKind kind;
    AssertionStatus status;
    bool byController;
    uint32 version;
    uint64 assertedAt;
    uint64 validFrom;
    uint64 validUntil;
    address asserter;
    uint256 unitId;
    bytes32 profileId;
    bytes32 contentHash;
    bytes32 supersedes;
    bytes32 supersededBy;
    string contentURI;
}

/// @notice On-chain core of a valuation receipt (Section 10.6).
struct ValuationCore {
    bytes32 methodId;
    bytes32 interestId;
    bytes32 assessmentBoundaryHash;
    bytes32 snapshotHash;
    uint8 resultKind;
    uint8 decimals;
    int256 value;
    bytes32 denominationId;
    uint64 asOf;
    uint64 horizonEnd;
}

/// @notice On-chain core of an observation record (Section 11).
struct ObservationCore {
    bytes32 snapshotHash;
    uint64 windowStart;
    uint64 windowEnd;
}

/// @notice Result kind codes (Section 10.5).
library AUFResultKind {
    uint8 internal constant MONETARY = 1;
    uint8 internal constant INTERVAL = 2;
    uint8 internal constant DISTRIBUTION = 3;
    uint8 internal constant SCENARIO = 4;
    uint8 internal constant VECTOR = 5;
    uint8 internal constant CONDITIONAL = 6;
    uint8 internal constant SCORE = 7;
    uint8 internal constant GRADE = 8;
    uint8 internal constant NOT_VALUABLE = 9;
    uint8 internal constant INSUFFICIENT_EVIDENCE = 10;
    uint8 internal constant NOT_APPLICABLE = 11;
    uint8 internal constant MAX = 11;

    /// @dev Result kinds whose on-chain `value` may be nonzero (Section 10.6).
    function carriesValue(uint8 kind) internal pure returns (bool) {
        return kind == MONETARY || kind == INTERVAL || kind == SCENARIO || kind == CONDITIONAL;
    }
}
