---
eip: <to be assigned>
title: Dive Logbook
description: A standard interface for storing, retrieving, and verifying dive log data.
author: Brad Myrick (@BradMyrick)
discussions-to: https://ethereum-magicians.org/t/erc-tbd-on-chain-dive-log-standard/28433?u=bradmyrick
status: Draft
type: Standards Track
category: ERC
created: 2026-05-09
requires: 165
---

## Abstract

This proposal defines a standard interface (`IDiveLog`) for storing, retrieving, and cryptographically verifying dive log data on EVM-compatible blockchains. A single contract implementing this interface serves as a diver's sovereign logbook — no registry or factory contract is required. The standard specifies an append-only data schema derived from U.S. military diving log forms (DD Form 2544, ENG Form 4615), a corrective ledger mechanism (void/supersede) that preserves immutable integrity while allowing error correction, and EIP-712 typed data structures for cryptographic attestation by buddies, instructors, or dive supervisors.

## Motivation

Dive logs are safety-critical records that track decompression history, demonstrate qualifications, and provide evidence of experience. Current storage methods are fragile: paper logbooks are lost or destroyed, centralized applications shut down when companies fail, and institutional databases disappear when organizations restructure. No interoperability exists between logging systems — each application defines its own schema, creating proprietary silos.

Additionally, no cryptographic proof mechanism exists for buddy sign-offs. This enables "pencil-whipping" (faking log entries), undermining the integrity of commercial and scientific diving operations where verified experience is a safety requirement.

A blockchain-based standard addresses these problems:

- **Permanence**: Data survives any single point of failure.
- **Ownership**: Divers control their own records via wallet keys.
- **Interoperability**: A single schema that any application can read and write.
- **Portability**: No vendor lock-in. Any compliant tool can render a diver's career from a contract address and chain ID.
- **Cryptographic trust**: EIP-712 signed attestations provide verifiable proof of dive verification.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

Every ERC-XXXX compliant contract MUST implement the `IDiveLog` and `ERC165` interfaces:

```solidity
pragma solidity ^0.8.20;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
```

### Enums

```solidity
enum UnitSystem { Imperial, Metric }
enum DiveMode { SSA, SCUBA }
enum BreathingGas { Air, Nitrox, Heliox, Trimix, Oxygen, Mixed }
enum BiologicalSex { Male, Female, Unspecified }
enum DivePurpose {
    Training, Inspection, Repair, Search, Salvage,
    Recovery, Construction, Research, EOD, Security,
    Photographic, Recreational, Other
}
enum SuitType { Wet, Dry, HotWater, Swim }
enum DecompressionType {
    NoneDecomp, Standard, SurfaceDecompO2, SurfaceDecompAir,
    Saturation, Repetitive, ExceptionalExposure
}
```

### Data Structures

Every dive record and every diver profile MUST declare a unit system. Consumers MUST interpret numeric fields according to the declared unit system:

| Field | Imperial | Metric |
|-------|----------|--------|
| Temperature | Degrees Fahrenheit (°F) | Degrees Celsius (°C) |
| Depth | Feet of Seawater (FSW) | Meters of Seawater (MSW) |
| Height | Inches | Centimeters |
| Weight | Pounds (lbs) | Kilograms (kg) |
| Pressure | PSI | Bar |
| Current | Knots | Knots |

Divers MAY log individual dives in a different unit system than their profile. Each dive record carries its own `UnitSystem` field.

#### DiverProfile

```solidity
struct DiverProfile {
    string name;         // Diver's full name (Last, First, Middle Initial)
    uint8 age;           // Age at time of last profile update
    uint16 height;       // Height (unit per profile's UnitSystem)
    uint16 weight;       // Weight (unit per profile's UnitSystem)
    BiologicalSex sex;   // Biological sex
    UnitSystem units;    // Default unit system for this diver
}
```

The `age` field represents the diver's age at the time of the last profile update. It does not automatically track current age. Consumers SHOULD treat this value as "age at time of last `updateProfile()` call."

#### DiveData

Core dive parameters:

```solidity
struct DiveData {
    uint32 leaveSurfaceTime;     // Unix timestamp — diver descends from surface
    uint32 leaveBottomTime;      // Unix timestamp — diver leaves bottom
    uint32 reachSurfaceTime;     // Unix timestamp — diver reaches surface
    uint32 bottomTimeMinutes;    // Total bottom time in minutes
    int32 maxDepth;              // Maximum depth attained (positive = below surface)
    int32 averageDepth;          // Average depth (OPTIONAL, 0 = not recorded)
    DiveMode mode;               // Dive mode
    DivePurpose purpose;         // Purpose of the dive
    SuitType suit;               // Exposure suit type
}
```

**Constraints:**
- `maxDepth` MUST be greater than 0.
- `bottomTimeMinutes` MUST be greater than 0.
- `leaveSurfaceTime`, `leaveBottomTime`, `reachSurfaceTime` SHOULD be monotonically increasing.

#### Environment

```solidity
struct Environment {
    int32 airTemp;               // Air temperature (unit per dive's UnitSystem)
    int32 waterTemp;             // Water temperature (unit per dive's UnitSystem)
    int16 currentKnots;          // Current speed in knots
    string location;             // Human-readable dive location
    string bottomType;           // Bottom composition (e.g., "Mud", "Coral", "Concrete")
    string weatherConditions;    // Weather description
}
```

All environment fields are OPTIONAL. Empty strings or zero values indicate not recorded.

#### Decompression

```solidity
struct Decompression {
    DecompressionType decompType;
    uint32 totalDecompTimeMinutes;
    int32 maxDepthAttained;
    bytes32 tableSchedule;       // Table/schedule identifier (e.g., "USN 9-7")
    bytes1 repetitiveGroup;      // Repetitive group designator (ASCII letter)
    uint32 surfaceIntervalMinutes;
    bytes1 newRepetitiveGroup;
}
```

For no-decompression dives, `decompType` SHOULD be set to `NoneDecomp` and time fields to 0.

#### GasData

```solidity
struct GasData {
    BreathingGas gasType;
    uint16 o2Percent;
    uint16 hePercent;
    uint16 n2Percent;
    uint32 cylinderPressureIn;
    uint32 cylinderPressureOut;
    uint32 gasConsumed;
    uint32 bailoutPressure;
}
```

Pressure fields store values in PSI when `UnitSystem` is `Imperial`, and in Bar when `UnitSystem` is `Metric`. Consumers MUST interpret pressure values according to the dive's declared `UnitSystem`.

#### DiveLog

```solidity
struct DiveLog {
    uint256 id;
    uint64 diveDate;
    UnitSystem units;
    DiveData data;
    Environment env;
    Decompression decomp;
    GasData gas;
    string remarks;
}
```

#### VoidInfo

The corrective ledger structure. Used to void or supersede a dive record without deletion.

```solidity
struct VoidInfo {
    bool isVoided;
    uint256 supersededById;     // 0 = voided without replacement
    address voidedBy;
    uint64 voidedAt;
    string reason;
}
```

#### Attestation

Cryptographic buddy/instructor sign-off record.

```solidity
struct Attestation {
    address attester;
    uint64 attestedAt;
}
```

### Interface Definition

```solidity
/// @title ERC-XXXX Dive Logbook Interface
///  Note: the ERC-165 identifier for this interface is 0x<to be calculated>.
interface IDiveLog is IERC165 {

    /// @dev Emitted when a new dive is logged.
    ///  The diveId is the sequential identifier assigned to the dive.
    ///  The diveDate is the Unix timestamp of the dive date.
    event DiveLogged(uint256 indexed diveId, uint64 indexed diveDate);

    /// @dev Emitted when a dive is voided or superseded.
    ///  supersededById is 0 if the dive is voided without replacement,
    ///  or the diveId of the correcting dive.
    event DiveVoided(
        uint256 indexed diveId,
        uint256 indexed supersededById,
        address indexed voidedBy,
        string reason
    );

    /// @dev Emitted when a third party cryptographically attests to a dive.
    ///  The attester is recovered from the EIP-712 signature, not msg.sender.
    event DiveAttested(uint256 indexed diveId, address indexed attester);

    /// @dev Emitted when the diver profile is updated.
    event ProfileUpdated();

    /// @dev Thrown when a non-owner attempts a restricted operation.
    error NotOwner();

    /// @dev Thrown when maxDepth is zero or negative.
    error InvalidDepth();

    /// @dev Thrown when bottomTimeMinutes is zero.
    error InvalidTimes();

    /// @dev Thrown when a dive lookup fails for the given diveId.
    error DiveNotFound(uint256 diveId);

    /// @dev Thrown when batch array lengths do not match.
    error ArrayLengthMismatch();

    /// @dev Thrown when attempting to void an already-voided dive.
    error DiveAlreadyVoided(uint256 diveId);

    /// @dev Thrown when the supersede target is invalid.
    error InvalidSupersede(uint256 voidedId, uint256 supersededId);

    /// @dev Thrown when the same attester attempts to attest the same dive twice.
    error AlreadyAttested(uint256 diveId, address attester);

    /// @dev Thrown when an attestation signature cannot be recovered.
    error InvalidSignature();

    /// @notice Log a single dive record.
    /// @dev Throws unless msg.sender is the owner. Throws if maxDepth <= 0
    ///  or bottomTimeMinutes == 0. Assigns a sequential diveId starting at 1.
    /// @param diveDate Unix timestamp of the dive date
    /// @param units Unit system for this dive's numeric fields
    /// @param data Core dive parameters
    /// @param env Environmental conditions
    /// @param decomp Decompression data
    /// @param gas Breathing gas data
    /// @param remarks Free-text remarks
    /// @return diveId The sequential identifier assigned to this dive
    function logDive(
        uint64 diveDate,
        UnitSystem units,
        DiveData calldata data,
        Environment calldata env,
        Decompression calldata decomp,
        GasData calldata gas,
        string calldata remarks
    ) external returns (uint256 diveId);

    /// @notice Log multiple dive records in a single transaction.
    /// @dev Throws unless msg.sender is the owner. Throws if any array lengths
    ///  do not match. Validates each dive identically to logDive. Reverts the
    ///  entire batch if any single dive is invalid. Emits one DiveLogged per dive.
    function batchLogDives(
        uint64[] calldata diveDates,
        UnitSystem[] calldata units,
        DiveData[] calldata dataArr,
        Environment[] calldata envArr,
        Decompression[] calldata decompArr,
        GasData[] calldata gasArr,
        string[] calldata remarksArr
    ) external returns (uint256[] memory diveIds);

    /// @notice Void or supersede a dive record.
    /// @dev Throws unless msg.sender is the owner. The original dive data
    ///  remains readable via getDive even after voiding. A dive can only be
    ///  voided once. If supersededById is 0, the dive is voided without
    ///  replacement. If supersededById > 0, it MUST reference an existing
    ///  dive that is not the dive being voided.
    /// @param diveId The dive to void
    /// @param supersededById The dive that replaces this one, or 0 for void-only
    /// @param reason Human-readable explanation for the void
    function voidDive(
        uint256 diveId,
        uint256 supersededById,
        string calldata reason
    ) external;

    /// @notice Submit a cryptographic attestation for a dive.
    /// @dev The attester is recovered from the signature, not msg.sender.
    ///  Any address MAY submit the transaction. The signature MUST be a valid
    ///  EIP-712 signature over the Attestation type hash (see EIP-712 Typed
    ///  Data section). Throws if the dive does not exist, has been voided,
    ///  the signature is invalid, or the attester has already attested.
    /// @param diveId The dive being attested
    /// @param signature The EIP-712 signature from the attester (65 bytes)
    function attestDive(
        uint256 diveId,
        bytes calldata signature
    ) external;

    /// @notice Retrieve a single dive record by its identifier.
    /// @dev Throws if diveId is zero or exceeds the total dive count.
    ///  Returns the dive data even if the dive has been voided.
    function getDive(uint256 diveId) external view returns (DiveLog memory);

    /// @notice Get all dive identifiers logged on a specific date.
    /// @param date Unix timestamp of the dive date
    /// @return An array of diveId values
    function getDivesByDate(uint64 date) external view returns (uint256[] memory);

    /// @notice Retrieve multiple dive records by their identifiers.
    /// @dev Throws if any requested diveId is invalid.
    function getMultipleDives(uint256[] calldata diveIds) external view returns (DiveLog[] memory);

    /// @notice Get all dive identifiers in this logbook.
    /// @return An array of all sequential diveId values (1 through diveCount)
    function getAllDiveIds() external view returns (uint256[] memory);

    /// @notice Get the total number of dives logged.
    function getDiveCount() external view returns (uint256);

    /// @notice Check whether a dive has been voided.
    /// @dev Throws if diveId is invalid.
    function isDiveVoided(uint256 diveId) external view returns (bool);

    /// @notice Get the void/supersede information for a dive.
    /// @dev Throws if diveId is invalid. Returns a VoidInfo with
    ///  isVoided == false if the dive has not been voided.
    function getVoidInfo(uint256 diveId) external view returns (VoidInfo memory);

    /// @notice Get all attestations for a dive.
    /// @dev Throws if diveId is invalid. Returns an empty array if
    ///  no attestations exist.
    function getAttestations(uint256 diveId) external view returns (Attestation[] memory);

    /// @notice Get the diver's profile.
    function profile() external view returns (DiverProfile memory);

    /// @notice Update the diver's profile.
    /// @dev Throws unless msg.sender is the owner.
    function updateProfile(
        string calldata name,
        uint8 age,
        uint16 height,
        uint16 weight,
        BiologicalSex sex,
        UnitSystem units
    ) external;
}
```

### EIP-712 Typed Data

This standard defines [EIP-712](./eip-712.md) typed data structures for attestation signature generation and verification. This ensures that a signature created by one application is valid when submitted via any other compliant application.

#### Domain

```solidity
keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
// name: "DiveLog"
// version: "1"
```

The `verifyingContract` is the dive log contract address. The `chainId` is the chain ID where the contract is deployed. This prevents cross-contract and cross-chain replay.

#### Attestation Type

```solidity
keccak256("Attestation(uint256 diveId,address verifyingContract)")
```

An attester signs the EIP-712 typed hash of this structure. The `verifyingContract` binds the attestation to a specific dive log contract.

#### Full Dive Data Types (Off-Chain)

For hardware interoperability (e.g., dive computers signing complete dive profiles via Bluetooth/app gateways), the following EIP-712 types are defined:

```solidity
keccak256("DiveData(uint32 leaveSurfaceTime,uint32 leaveBottomTime,uint32 reachSurfaceTime,uint32 bottomTimeMinutes,int32 maxDepth,int32 averageDepth,uint8 mode,uint8 purpose,uint8 suit)")

keccak256("Environment(int32 airTemp,int32 waterTemp,int16 currentKnots,string location,string bottomType,string weatherConditions)")

keccak256("Decompression(uint8 decompType,uint32 totalDecompTimeMinutes,int32 maxDepthAttained,bytes32 tableSchedule,bytes1 repetitiveGroup,uint32 surfaceIntervalMinutes,bytes1 newRepetitiveGroup)")

keccak256("GasData(uint8 gasType,uint16 o2Percent,uint16 hePercent,uint16 n2Percent,uint32 cylinderPressureIn,uint32 cylinderPressureOut,uint32 gasConsumed,uint32 bailoutPressure)")

keccak256("DiveLog(uint256 id,uint64 diveDate,uint8 units,DiveData data,Environment env,Decompression decomp,GasData gas,string remarks)")
```

Dynamic types (`string`, `bytes`) within structs MUST be hashed as `keccak256(abi.encode(...))` for the enclosing struct hash, using `keccak256(bytes(value))` for string fields, as specified by [EIP-712](./eip-712.md).

### Behavior Requirements

#### Dive Logging

- Dive identifiers MUST be sequential, starting at 1.
- Dive records MUST be append-only. No deletion or modification of existing records is permitted.
- `logDive` MUST revert with `InvalidDepth` if `maxDepth <= 0`.
- `logDive` MUST revert with `InvalidTimes` if `bottomTimeMinutes == 0`.
- `logDive` MUST emit `DiveLogged` with the assigned `diveId` and `diveDate`.
- `batchLogDives` MUST revert with `ArrayLengthMismatch` if input array lengths do not all match.
- `batchLogDives` MUST validate each dive identically to `logDive`.
- `batchLogDives` MUST revert the entire batch if any single dive is invalid. No partial writes.
- `batchLogDives` MUST emit one `DiveLogged` event per successfully logged dive.

#### Corrective Ledger (Void/Supersede)

The corrective ledger does NOT allow edit or delete operations. Instead, it provides a "Void/Supersede" mechanism that preserves the complete audit trail.

- `voidDive` MUST revert unless `msg.sender` is the owner.
- `voidDive` MUST revert with `DiveNotFound` if `diveId` is invalid (zero or exceeds dive count).
- `voidDive` MUST revert with `DiveAlreadyVoided` if the dive has been previously voided.
- `voidDive` MUST revert with `InvalidSupersede` if `supersededById` is non-zero and references the same dive as `diveId` or references a nonexistent dive.
- `voidDive` with `supersededById == 0` marks the dive as voided without replacement.
- `voidDive` with `supersededById > 0` marks the dive as superseded by the specified dive.
- `voidDive` MUST emit `DiveVoided` with all indexed fields.
- The original dive data MUST remain readable via `getDive` even after voiding.
- `isDiveVoided` MUST return `true` for voided dives.
- `getVoidInfo` MUST return the full `VoidInfo` struct including the reason and superseding dive ID.

#### Cryptographic Attestation

- `attestDive` MAY be callable by any address (the attester is recovered from the signature, not `msg.sender`).
- `attestDive` MUST revert with `DiveNotFound` if the dive does not exist.
- `attestDive` MUST revert with `DiveAlreadyVoided` if the dive has been voided.
- `attestDive` MUST revert with `InvalidSignature` if the signature cannot be recovered to a valid (non-zero) address.
- `attestDive` MUST revert with `AlreadyAttested` if the recovered attester has previously attested this dive.
- `attestDive` MUST emit `DiveAttested` with the recovered attester address.
- `getAttestations` MUST return all attestations for a dive in the order they were recorded.

#### Profile Management

- `updateProfile` MUST revert unless `msg.sender` is the owner.
- `updateProfile` MUST emit `ProfileUpdated`.
- `profile` MUST return a `DiverProfile` memory struct.

#### ERC-165 Compliance

- Implementations MUST implement [ERC-165](./eip-165.md) interface detection.
- `supportsInterface` MUST return `true` when queried with the `IDiveLog` interface ID.
- `supportsInterface` MUST return `true` when queried with the `IERC165` interface ID (`0x01ffc9a7`).
- `supportsInterface` MUST return `false` when queried with `0xffffffff`.

### Events

Events are designed for efficient off-chain indexing without a central registry:

| Event | Indexed Fields | Use Case |
|-------|---------------|----------|
| `DiveLogged` | `diveId`, `diveDate` | Filter dives by date across contracts |
| `DiveVoided` | `diveId`, `supersededById`, `voidedBy` | Track void/supersede chains, filter by voiding authority |
| `DiveAttested` | `diveId`, `attester` | Find all dives attested by a specific address |
| `ProfileUpdated` | (none) | Track profile changes |

The emitting contract address is implicitly available in every event log, enabling per-diver filtering without an additional indexed field.

## Rationale

### Sovereign Interface (No Registry)

A central registry creates a single point of failure and a gatekeeper for the ecosystem. The sovereign model allows any entity — training agencies (PADI, NAUI), military units, commercial diving operators, or individual developers — to deploy compliant contracts without permission from a registry operator. [ERC-165](./eip-165.md) interface detection allows any tool to verify compliance at the contract level. A diver presents their contract address and chain ID; any compliant application queries the `IDiveLog` interface and renders the full career.

### Corrective Ledger (Void/Supersede)

Dive logs are safety records. Allowing modification or deletion undermines their evidentiary value. The void/supersede mechanism preserves the complete audit trail: the original dive remains readable, its void status is queryable, and the superseding dive is linked. This mirrors professional accounting practices where corrections are made via journal entries, not by erasing the ledger.

### EIP-712 Attestations

[EIP-712](./eip-712.md) provides a standardized, human-readable signing format. This ensures that a signature generated by one application (e.g., a dive instructor's mobile app) is verifiable by any other application (e.g., a dive boat's verification system). Without EIP-712, each application would define its own hashing scheme, breaking cross-application portability.

### Structs Instead of Individual Fields

Grouping related data into structs (`DiveData`, `Environment`, `Decompression`, `GasData`) reduces the number of function parameters, improves readability, and maps cleanly to the military source forms (DD Form 2544, ENG Form 4615) which group fields into sections.

### Dual Unit System

The U.S. military diving community operates in Imperial units (FSW, PSI, °F). International and scientific diving communities use Metric (MSW, bar, °C). Supporting both maximizes adoption. Per-dive unit declarations allow a single diver to mix conventions across dives without ambiguity.

### On-Chain Storage vs. Events

Events are not reliably accessible from smart contracts and may be pruned by nodes. Struct storage in contract state ensures data is always retrievable by any on-chain or off-chain consumer.

### Append-Only with Void Overlay

The core dive data is append-only (immutable). The void/supersede mechanism is an overlay that marks a dive as voided without modifying the underlying data. This separation keeps the core storage simple while allowing for error correction.

### Separated Void and Attestation Queries

Void info and attestations are queried via dedicated functions (`getVoidInfo`, `getAttestations`) rather than embedded in the `DiveLog` struct. This keeps the core data structure compact and allows implementations to optimize storage independently.

## Backwards Compatibility

This proposal does not conflict with any existing ERC standards. It does not modify or extend any existing token or interface standard.

Contracts implementing this standard MUST also implement [ERC-165](./eip-165.md) interface detection.

## Reference Implementation

A reference implementation is provided in the assets directory as `../assets/eip-XXXX/SovereignDiveLog.sol`. It implements the complete `IDiveLog` interface with:

- Sequential dive ID assignment
- Append-only storage with date indexing
- Void/supersede corrective ledger
- EIP-712 signature verification for attestations
- Owner-restricted write operations

## Security Considerations

**Access control**: Write operations (`logDive`, `voidDive`, `updateProfile`) are restricted to the contract owner. The owner is set at construction and SHOULD be immutable. Implementations deployed with upgradeable proxy patterns MUST preserve the invariant that only the designated owner can write.

**No sensitive data**: Dive logs do not contain personally identifying information beyond what a diver chooses to include in the `name` string field. Social security numbers, military IDs, and other sensitive identifiers are explicitly excluded from this standard. Implementors SHOULD NEVER store such data on-chain.

**Corrective ledger integrity**: Void/supersede preserves immutable integrity. A voided dive cannot be un-voided. The original data is never modified or deleted, maintaining a complete audit trail.

**Attestation security**: EIP-712 signatures bind the attestation to a specific (`diveId`, `verifyingContract`, `chainId`) tuple, preventing replay attacks across contracts or chains. The attester is recovered from the signature, not from `msg.sender`, so front-running an attestation transaction has no impact on the recorded attester identity.

**Gas costs**: Storing a full `DiveLog` struct requires significant gas (approximately 350,000 gas per dive). Consumers SHOULD use `batchLogDives` for gas efficiency when logging multiple dives. Implementations on Layer 2 chains or chains with lower gas costs are RECOMMENDED for cost-sensitive use cases.

**Immutable contracts**: Implementations SHOULD be deployed without proxy upgradeability to guarantee the append-only property and the immutability of void records. If proxies are used, the implementation MUST NOT expose functions that modify or delete existing dive records.

**Attestation on voided dives**: The specification requires that `attestDive` reverts for voided dives. This prevents attestations on records that the diver has explicitly marked as incorrect.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
