// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title ERC-8260 common types.
/// @notice Enums and structs shared by `IDiveLog` and implementations.
interface IDiveLogTypes {
    enum UnitSystem {
        Imperial,
        Metric
    }

    enum DiveMode {
        OCRecreational,
        OCTechnical,
        CCR,
        SCR,
        Freedive,
        SurfaceSupplied,
        Saturation
    }

    /// @notice Input to `logDive` and `batchLogDives`. The `id` is assigned by the contract.
    struct DiveInput {
        uint32 diveDate; // UTC calendar date as YYYYMMDD, e.g. 20260514; not a Unix timestamp
        uint64 startTime; // Unix seconds UTC: the instant the diver leaves the surface; MUST be > 0
        uint32 maxDepth; // tenths of FSW (Imperial) or MSW (Metric); MUST be > 0
        uint32 durationSeconds; // total dive time, surface to surface; MUST be > 0
        uint32 bottomTimeSeconds; // leave surface to beginning of ascent; 0 = not recorded
        DiveMode mode;
        UnitSystem units;
        uint16 o2Bps; // O2 of the primary gas in basis points (2100 = 21.00%); 0/0 = no cylinder
        uint16 heBps; // He of the primary gas in basis points; N2 implied as 10000 - o2Bps - heBps
        bytes16 tableSchedule; // ASCII `<TOKEN>` or `<TOKEN> <schedule>`, right-NUL-padded; bytes16(0) = not recorded
        uint32 surfaceIntervalSeconds; // surface interval before this dive, in seconds; 0 = not recorded / not applicable
        bytes1 repetitiveGroup; // ASCII 'A'-'Z' at the end of this dive; 0x00 = not recorded
        bytes1 repetitiveGroupAfterSI; // ASCII 'A'-'Z' after the surface interval preceding this dive; 0x00 = not recorded
        bytes4 coarseGeohash; // geohash precision 4 (four ASCII characters); bytes4(0) = not recorded
        bytes32 contentHash; // REQUIRED; SHA-256 of the exact attested UDDF 3.x file bytes
        string profileURI; // MAY be empty; SHOULD be content-addressed (ipfs:// or ar://)
    }

    /// @notice A stored dive header, as returned by `getDive`.
    struct DiveHeader {
        uint256 id; // contract-assigned sequence, starting at 1; this is the dive number
        uint32 diveDate;
        uint64 startTime;
        uint32 maxDepth;
        uint32 durationSeconds;
        uint32 bottomTimeSeconds;
        DiveMode mode;
        UnitSystem units;
        uint16 o2Bps;
        uint16 heBps;
        bytes16 tableSchedule;
        uint32 surfaceIntervalSeconds;
        bytes1 repetitiveGroup;
        bytes1 repetitiveGroupAfterSI;
        bytes4 coarseGeohash;
        bytes32 contentHash;
        string profileURI;
    }

    /// @notice Void/supersede overlay for a dive. The header itself is never mutated.
    struct VoidInfo {
        uint256 supersededById; // 0 = voided without replacement
        bool isVoided;
        address voidedBy;
        uint64 voidedAt;
        string reason;
    }

    /// @notice An on-chain record of one EIP-712 attestation that bound `diveId` to its `contentHash`.
    struct Attestation {
        address attester;
        uint64 attestedAt;
        uint256 nonce;
    }
}
