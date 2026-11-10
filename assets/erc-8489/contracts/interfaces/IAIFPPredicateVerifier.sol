// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IAIFPPredicateVerifier
/// @notice A leaf verifier. It answers one of the four outcomes and never reverts on a negative answer.
///         A revert, a check that does not complete within the composite verifier's gas bound, return data
///         that is not exactly one 32-byte word, or a word above 3 is recorded by the caller as
///         VERIFIER_ERROR for that leaf. The composite verifier gives a leaf its full gas bound or does not
///         call it at all, so the gas forwarded to an evaluation never changes what a leaf is given. Two
///         properties of a transaction still reach a leaf. State access is cheaper when warm, so a verifier
///         has to complete within the bound from a cold start for its answer to be the same in every
///         transaction. And the sender of a transaction is charged its gas limit times the gas price before
///         execution, so a verifier that reads the native balance of an account that can be the sender
///         answers according to the gas limit; a verifier should not do that.
interface IAIFPPredicateVerifier {
    /// @param channelId  the channel the subject is being evaluated for
    /// @param subject    canonical subject reference
    /// @param role       the single role bit being acquired
    /// @param scopeRef   scope the role is requested for (0 = whole channel)
    /// @param kind       leaf kind (EXTERNAL or a semantic kind), see AIFPPredicates
    /// @param ref        leaf reference committed in the predicate
    /// @param params     leaf parameters committed in the predicate
    /// @param evidence   caller-supplied evidence for this leaf (may be empty)
    /// @return outcome   0 SATISFIED, 1 NOT_SATISFIED, 2 UNDETERMINABLE, 3 VERIFIER_ERROR
    function verify(
        bytes32 channelId,
        bytes32 subject,
        uint16 role,
        bytes32 scopeRef,
        uint8 kind,
        bytes32 ref,
        bytes calldata params,
        bytes calldata evidence
    ) external view returns (uint8 outcome);
}

/// @title IAIFPCompositeVerifier
/// @notice Evaluates a whole predicate tree with four-valued composition.
interface IAIFPCompositeVerifier {
    /// @notice The evaluation could not give a leaf call its full gas bound. It is a failure of the call, not
    ///         an outcome, and nothing is recorded: the evaluation needs more gas than it was given.
    error AIFP_InsufficientGas();

    /// @notice Outcome of the predicate for the subject. The gas supplied by the caller does not decide the
    ///         outcome: the evaluation gives every leaf it calls the full bound, or reverts with
    ///         `AIFP_InsufficientGas`. Any revert of this function means that there is no outcome.
    function evaluate(
        bytes32 channelId,
        bytes32 subject,
        uint16 role,
        bytes32 scopeRef,
        bytes calldata predicate,
        bytes[] calldata evidence
    ) external view returns (uint8 outcome);

    function supportsKind(uint8 kind) external view returns (bool);

    /// @notice The fixed amount of gas given to every leaf call. An evaluation needs about 64/63 of it to be
    ///         available, beyond what it spends itself, each time it calls a leaf.
    function leafGasLimit() external view returns (uint256);
}

/// @title IAIFPSubjectSet
/// @notice A set of subject references used by ALLOWLIST leaves. `contains` MUST return exactly one word
///         equal to 0 or 1; anything else is recorded by the caller as VERIFIER_ERROR for that leaf.
interface IAIFPSubjectSet {
    function contains(bytes32 subject) external view returns (bool);
}
