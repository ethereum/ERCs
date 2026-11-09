// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IAIFPPredicateVerifier
/// @notice A leaf verifier. It answers one of the four outcomes and never reverts on a negative answer.
///         A revert, running out of the gas the caller forwards, return data that is not exactly one
///         32-byte word, or a word above 3 is recorded by the caller as VERIFIER_ERROR for that leaf.
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
    function evaluate(
        bytes32 channelId,
        bytes32 subject,
        uint16 role,
        bytes32 scopeRef,
        bytes calldata predicate,
        bytes[] calldata evidence
    ) external view returns (uint8 outcome);

    function supportsKind(uint8 kind) external view returns (bool);
}

/// @title IAIFPSubjectSet
/// @notice A set of subject references used by ALLOWLIST leaves. `contains` MUST return exactly one word
///         equal to 0 or 1; anything else is recorded by the caller as VERIFIER_ERROR for that leaf.
interface IAIFPSubjectSet {
    function contains(bytes32 subject) external view returns (bool);
}
