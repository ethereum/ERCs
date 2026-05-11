// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

enum UnitSystem {
    Imperial,
    Metric
}

enum DiveMode {
    SSA,
    SCUBA
}

enum BreathingGas {
    Air,
    Nitrox,
    Heliox,
    Trimix,
    Oxygen,
    Mixed
}

enum DivePurpose {
    Training,
    Inspection,
    Repair,
    Search,
    Salvage,
    Recovery,
    Construction,
    Research,
    EOD,
    Security,
    Photographic,
    Recreational,
    Other
}

enum SuitType {
    Wet,
    Dry,
    HotWater,
    Swim
}

enum DecompressionType {
    NoneDecomp,
    Standard,
    SurfaceDecompO2,
    SurfaceDecompAir,
    Saturation,
    Repetitive,
    ExceptionalExposure
}

struct DiveData {
    uint32 leaveSurfaceTime;
    uint32 leaveBottomTime;
    uint32 reachSurfaceTime;
    uint32 bottomTimeMinutes;
    uint32 maxDepth;
    int32 averageDepth;
    DiveMode mode;
    DivePurpose purpose;
    SuitType suit;
}

struct Environment {
    int32 airTemp;
    int32 waterTemp;
    int16 currentKnots;
    string location;
    string bottomType;
    string weatherConditions;
}

struct Decompression {
    DecompressionType decompType;
    uint32 totalDecompTimeMinutes;
    int32 maxDepthAttained;
    bytes32 tableSchedule;
    bytes1 repetitiveGroup;
    uint32 surfaceIntervalMinutes;
    bytes1 newRepetitiveGroup;
}

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

struct DiveInput {
    uint64 diveDate;
    UnitSystem units;
    DiveData data;
    Environment env;
    Decompression decomp;
    GasData gas;
    string remarks;
}

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

struct VoidInfo {
    uint256 supersededById;
    bool isVoided;
    address voidedBy;
    uint64 voidedAt;
    string reason;
}

struct Attestation {
    address attester;
    uint64 attestedAt;
}
