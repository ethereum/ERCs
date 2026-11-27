// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Authorization, ConsumptionRequest, RequestRecord, Outcome, AcceptanceRule} from "./AITOTypes.sol";

/// @title Authorized consumption of AI inference entitlements
/// @notice An authorization is a ceiling. A hold reserves units for one logical request.
/// A settlement deducts what was accepted and releases the rest, once per logical request.
interface IAITOConsumption {
    event Authorized(
        bytes32 indexed authorizationId,
        address indexed holder,
        address indexed consumer,
        uint256 seriesId,
        uint256 cap,
        uint64 validAfter,
        uint64 validUntil,
        bytes32 scope,
        uint256 nonce
    );
    event Revoked(bytes32 indexed authorizationId, address indexed holder);
    event Held(
        bytes32 indexed requestKey,
        bytes32 indexed authorizationId,
        address indexed fulfiller,
        address consumer,
        bytes32 requestId,
        uint256 seriesId,
        address holder,
        uint256 amount,
        uint64 holdUntil
    );
    event UsageClaimed(
        bytes32 indexed requestKey,
        address indexed fulfiller,
        Outcome outcome,
        uint256[] usage,
        uint256 computed,
        uint256 claimed,
        bytes32 claimHash,
        bytes32 evidenceRoot
    );
    event Objected(bytes32 indexed requestKey, address indexed by, bytes32 reason);
    event Accepted(bytes32 indexed requestKey, address indexed acceptedBy, AcceptanceRule rule, uint256 amount);
    event Settled(
        bytes32 indexed requestKey,
        uint256 indexed seriesId,
        address indexed holder,
        uint256 deducted,
        uint256 released,
        bytes32 receiptHash
    );
    event Released(bytes32 indexed requestKey, uint256 indexed seriesId, address indexed holder, uint256 amount);

    /// @notice EIP-712 digest of an authorization. It is the authorization identifier.
    function hashAuthorization(Authorization calldata a) external view returns (bytes32);

    /// @notice EIP-712 digest of a consumption request.
    function hashRequest(ConsumptionRequest calldata r) external view returns (bytes32);

    /// @notice EIP-712 digest a consumer signs to accept a claim.
    function hashAcceptance(bytes32 requestKey, bytes32 claimHash, uint256 amount) external view returns (bytes32);

    /// @notice The key one logical request has on this ledger: `keccak256(abi.encode(consumer, requestId))`.
    function requestKeyOf(address consumer, bytes32 requestId) external pure returns (bytes32);

    /// @notice Register an authorization on chain. The caller MUST be `a.holder`.
    function authorize(Authorization calldata a) external returns (bytes32 authorizationId);

    /// @notice Revoke an authorization. The caller MUST be `a.holder`. Existing holds are unaffected.
    function revoke(Authorization calldata a) external;

    function isRevoked(bytes32 authorizationId) external view returns (bool);

    /// @notice Units currently reserved or already deducted under an authorization.
    function usedOf(bytes32 authorizationId) external view returns (uint256);

    /// @notice Reserve `r.maxAmount` units of the holder for one logical request.
    /// The caller MUST be `r.fulfiller`. `holderSig` may be empty when the authorization was registered on chain.
    function hold(
        Authorization calldata a,
        bytes calldata holderSig,
        ConsumptionRequest calldata r,
        bytes calldata consumerSig
    ) external returns (bytes32 requestKey);

    /// @notice Claim the usage of a held request. The deduction is computed from the series schedule
    /// and the outcome, and is bounded by the hold.
    function claimUsage(bytes32 requestKey, uint256[] calldata usage, Outcome outcome, bytes32 evidenceRoot)
        external;

    /// @notice Settle a claim with the consumer's signature over it.
    function accept(bytes32 requestKey, bytes calldata consumerSig) external;

    /// @notice Object to a claim inside the objection window. The caller MUST be the consumer or the holder.
    function object(bytes32 requestKey, bytes32 reason) external;

    /// @notice Decide a disputed claim. The caller MUST be the series resolver. `amount` MUST NOT exceed the claim.
    function resolve(bytes32 requestKey, uint256 amount) external;

    /// @notice Settle an unobjected claim after the objection window.
    function finalize(bytes32 requestKey) external;

    /// @notice Return all reserved units of a request that will not be settled.
    function release(bytes32 requestKey) external;

    function requestOf(bytes32 requestKey) external view returns (RequestRecord memory);

    /// @notice Whether `hash` is the receipt hash of a settled request on this ledger.
    function isReceipt(bytes32 hash) external view returns (bool);
}
