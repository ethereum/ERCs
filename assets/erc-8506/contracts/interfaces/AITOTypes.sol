// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Kinds of content-addressed record.
/// Unit, Grade, Source, Terms and Receipt are the five core objects.
/// Method, MethodApplication and Assessment belong to the optional modules.
enum RecordKind {
    Unit,
    Grade,
    Source,
    Terms,
    Receipt,
    Method,
    MethodApplication,
    Assessment
}

/// @notice How a usage claim becomes an accepted deduction.
/// CoSign          the consumer signs the claim; no signature, no deduction.
/// Optimistic      the claim stands after the objection window unless the consumer or holder objects.
/// ProviderMetered the fulfiller's claim is accepted as made, bounded by the hold.
enum AcceptanceRule {
    CoSign,
    Optimistic,
    ProviderMetered
}

/// @notice Result class of one request. Each class selects which usage components are charged.
enum Outcome {
    Completed,
    Partial,
    Refused,
    TimedOut,
    CancelledByConsumer,
    ProviderError
}

/// @notice State of one logical request on the home ledger.
enum RequestState {
    None,
    Held,
    Claimed,
    Disputed,
    Settled,
    Released
}

/// @notice How a carrier token relates to a series.
enum BindingType {
    Native,
    Wrap
}

/// @notice How units reached through a carrier are consumed.
/// Direct      consumed on the home ledger from the carrier balance itself.
/// UnwrapFirst the carrier must be converted back to native units before consumption.
enum ConsumptionPath {
    Direct,
    UnwrapFirst
}

/// @notice An extension of the terms of a series.
struct SeriesExtension {
    /// Identifier of the extension. A new version of an extension has a new identifier.
    bytes32 id;
    /// True when a party that does not understand the extension must not operate on the series.
    bool critical;
    /// Parameters of the extension, in the encoding its definition gives.
    bytes data;
}

/// @notice Machine-enforced terms of a series. The series identifier is
/// `uint256(keccak256(abi.encode(terms)))`, so any change to any member is a new series.
/// Terms that the ledger does not enforce live in the terms document committed by `termsHash`.
struct SeriesTerms {
    /// The only account that may issue units of the series.
    address issuer;
    /// The account that owes supply to holders.
    address responsibleParty;
    /// Record identifiers of the Unit, Grade and Source this series is issued under.
    bytes32 unit;
    bytes32 grade;
    bytes32 source;
    /// Identifier of the full terms document.
    bytes32 termsHash;
    /// Maximum total issuance, in denomination units.
    uint256 cap;
    /// Units are consumable from `validFrom` to `validUntil`, both inclusive.
    uint64 validFrom;
    uint64 validUntil;
    /// Whether holders may transfer units to other accounts.
    bool transferable;
    /// Whether any party may change the deduction schedule after creation.
    bool scheduleMutable;
    /// Rounding of a deduction to whole denomination units: up when true, down when false.
    bool roundUp;
    AcceptanceRule acceptanceRule;
    /// Seconds during which a claim may be objected to (Optimistic).
    uint32 objectionWindow;
    /// Seconds the resolver has to decide a disputed claim.
    uint32 resolutionWindow;
    /// Longest permitted hold, in seconds.
    uint32 maxHoldDuration;
    /// Account that decides disputed claims, or zero for none.
    address resolver;
    /// Usage components of the Unit, in the order usage vectors are reported.
    bytes32[] components;
    /// Denomination units deducted per component unit, scaled by 1e6.
    uint256[] weights;
    /// One bitmask per Outcome: bit i set means component i is charged for that outcome.
    uint256[] outcomeMasks;
    /// Extensions of the terms, with their parameters.
    SeriesExtension[] extensions;
}

/// @notice A holder's permission for a consumer to consume. It is a ceiling, not a reservation.
struct Authorization {
    address holder;
    address consumer;
    uint256 seriesId;
    /// Cumulative ceiling across all requests made under this authorization.
    uint256 cap;
    uint64 validAfter;
    uint64 validUntil;
    /// Zero for unrestricted; otherwise only requests carrying the same scope may use it.
    bytes32 scope;
    uint256 nonce;
}

/// @notice A consumer's instruction to reserve units for one logical request.
struct ConsumptionRequest {
    bytes32 authorizationId;
    /// Chosen by the consumer. Retries and mirrors of the same logical request reuse it.
    bytes32 requestId;
    /// The fulfiller allowed to place the hold and claim usage.
    address fulfiller;
    /// Upper bound of the deduction for this request.
    uint256 maxAmount;
    uint64 holdUntil;
    bytes32 scope;
}

/// @notice The on-chain part of a Receipt.
struct RequestRecord {
    RequestState state;
    Outcome outcome;
    uint64 holdUntil;
    uint64 claimedAt;
    uint64 disputedAt;
    uint256 seriesId;
    address holder;
    address consumer;
    address fulfiller;
    bytes32 authorizationId;
    /// Units reserved by the hold.
    uint256 held;
    /// Deduction computed from the claimed usage, before the hold bound is applied.
    uint256 computed;
    /// Deduction claimed, never above `held`.
    uint256 claimed;
    /// Units finally deducted.
    uint256 deducted;
    bytes32 claimHash;
    bytes32 evidenceRoot;
    bytes32 receiptHash;
}
