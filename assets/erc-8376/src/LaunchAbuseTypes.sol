// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @dev Canonical pattern identifiers. Extensible under the `erc.launch.` prefix.
library Patterns {
    bytes32 internal constant HARD_RUG            = keccak256("erc.launch.hard-rug");
    bytes32 internal constant SOFT_RUG            = keccak256("erc.launch.soft-rug");
    bytes32 internal constant INSIDER_ALLOCATION  = keccak256("erc.launch.insider-allocation");
    bytes32 internal constant SNIPER_COORDINATION = keccak256("erc.launch.sniper-coordination");
    bytes32 internal constant HONEYPOT            = keccak256("erc.launch.honeypot");
    bytes32 internal constant MINT_DILUTION       = keccak256("erc.launch.mint-dilution");
    bytes32 internal constant RETAINED_CONTROL    = keccak256("erc.launch.retained-control");
    bytes32 internal constant WASH_LAUNCH         = keccak256("erc.launch.wash-launch");
    bytes32 internal constant UNLOCK_EXIT         = keccak256("erc.launch.unlock-exit");
    bytes32 internal constant SERIAL_DEPLOYER     = keccak256("erc.launch.serial-deployer");
    bytes32 internal constant IMPERSONATION       = keccak256("erc.launch.impersonation");
}

/// @dev Extension schema identifiers, namespaced under `erc.launch.schema.`.
///      A schema publishes name, type, units, definition, polarity and
///      threshold for every field it adds, or a third party cannot recompute
///      the score it feeds.
library Schemas {
    bytes32 internal constant IMPERSONATION = keccak256("erc.launch.schema.impersonation");
}

/// @dev Bit assignments for `SignalVector.privilegedPowers`.
library Powers {
    uint16 internal constant MINT       = 0x0001;
    uint16 internal constant PAUSE      = 0x0002;
    uint16 internal constant BLACKLIST  = 0x0004;
    uint16 internal constant FEE        = 0x0008;
    uint16 internal constant UPGRADE    = 0x0010;
    uint16 internal constant SEIZE      = 0x0020;
    uint16 internal constant LIMITS     = 0x0040;
    uint16 internal constant EXEMPT     = 0x0080;

    /// @dev Powers that permit unilateral expropriation or dilution.
    uint16 internal constant DANGEROUS = MINT | UPGRADE | SEIZE;
}

/// @notice The twelve base signals describing deployer conduct. Never buyer
///         outcome. Version 1 of the vector is exactly these fields.
/// @dev Unavailable signals MUST be reported as the type maximum, not zero.
struct SignalVector {
    uint16 deployerSupplyShare;    // bps, adverse
    uint16 insiderAllocationShare; // bps, adverse
    uint16 sniperConcentration;    // bps, adverse
    uint16 lpLockedShare;          // bps, protective
    uint32 lpLockRemaining;        // seconds, protective
    uint16 liquidityRemoved;       // bps, adverse
    uint16 deployerSellRatio;      // bps, adverse
    uint16 proceedsWithdrawnShare; // bps, adverse
    uint16 privilegedPowers;       // bitmask, adverse
    uint16 priorUpheldClaims;      // count, adverse
    uint16 supplyInflation;        // bps, adverse: supply minted after launch
    uint16 washTradeRatio;         // bps, adverse: volume returning to its origin
}

/// @dev Version of the base signal vector a report was computed under. A
///      consumer that does not implement the version MUST reject the report
///      rather than misread it.
uint16 constant BASE_VECTOR_VERSION = 1;

/// @notice Fields of the reference impersonation extension schema, in the
///         order `extensionSignals` encodes them.
/// @dev The abuse is entirely in the identity claim, so none of it is
///      expressible in the base vector: a deployer may retain no supply,
///      lock liquidity, hold no powers, and read clean on all twelve.
struct ImpersonationSignals {
    uint16 symbolCollision; // bitmask, adverse: 1 any, 2 older, 4 deeper
    uint16 nameSimilarity;  // bps, adverse
    uint16 metadataReuse;   // bps, adverse
}

struct AbuseReport {
    bytes32      patternId;
    bytes32      launchId;         // as listed in ILaunchDirectory
    address      token;
    address      deployer;
    address[]    linkedAddresses;
    uint8        abuseScore;
    uint8        confidence;
    uint16       vectorVersion;    // 1 for the base twelve signals
    uint64       launchedAt;
    uint64       windowEnd;
    SignalVector signals;
    bytes32      extensionSchema;  // zero where no extension is used
    bytes        extensionSignals; // ABI-encoded, in schema-declared order
    bytes32      evidenceRoot;
    string       evidenceURI;
}

enum LaunchState  { None, Active, Releasing, Frozen, Settled, Refunding }
enum ClaimStatus  { None, Open, Contested, Settled, Upheld, Rejected, Executed, Expired }
enum ContainmentAction { None, Flag, ExtendSchedule, SuspendRelease, Freeze, Refund }

// --- errors -----------------------------------------------------------------

error UnknownReport(bytes32 reportId);
error ReportAlreadyRetracted(bytes32 reportId);
error ReportStale(uint64 windowEnd, uint64 maxAge);
error InsufficientScore(uint8 score, uint8 required);
error InsufficientConfidence(uint8 confidence, uint8 required);
error OutcomeSignalNotPermitted();
error InvalidSignalVector();
error UnsupportedVectorVersion(uint16 declared, uint16 supported);
error UnknownExtensionSchema(bytes32 extensionSchema);
error InvalidPattern(bytes32 patternId);
error DetectorNotBonded(address detector, uint256 held, uint256 required);
error UnknownLaunch(bytes32 launchId);
error LaunchNotFreezable(bytes32 launchId, LaunchState state);
error LaunchSettledAlready(bytes32 launchId);
error FreezeExpired(bytes32 launchId, uint64 frozenUntil);
error ReleaseScheduleExceeded(uint256 requested, uint256 available);
error NotVenue(address caller);
error NotRemediation(address caller);
error PurchaseAlreadyRecorded(bytes32 launchId, address buyer);
error NothingToRefund(bytes32 launchId, address buyer);
error RefundWindowClosed(bytes32 launchId, uint64 closedAt);
error ClaimNotOpen(bytes32 claimId, ClaimStatus status);
error ContestWindowClosed(bytes32 claimId, uint64 closedAt);
error NotAdjudicator(address caller);
error InsufficientBond(uint256 held, uint256 required);
error BondLocked(bytes32 launchId, uint64 unlockAt);
error ContainmentNotPermitted(ContainmentAction requested, ContainmentAction maximum);
