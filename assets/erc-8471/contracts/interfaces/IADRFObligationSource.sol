// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";

/// @title  IADRFObligationSource — what a bound business contract (or its adapter) attests to the registry
/// @notice The source derives every attested value from its own state, never from the caller: the
///         event instant and the business adoption deadline (its own clock), the obligation the event
///         belongs to, the norm it recognises and when that norm was declared, the obligation kind, who
///         is a party, and which propositions, taking which value, are breaches of which obligation under
///         that norm. The registry cross-checks a claim against these attestations at admission.
interface IADRFObligationSource {
    /// ERC-165: implementers MUST report `type(IADRFObligationSource).interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function eventInfo(T.ObjectRef calldata object, bytes32 eventRef) external view returns (T.EventInfo memory);
    function isParty(T.ObjectRef calldata object, bytes32 eventRef, address account) external view returns (bool);

    /// Whether, under the norm the source attests for this event, `proposition` taking the value `breachWhen` is
    /// a breach of an obligation of kind `obligationKind`. The registry requires this of the decisive sub-question
    /// of every Binding claim, with the claim's direction: the source, not the filer, says what counts as a breach
    /// and in which sense an answer sustains a claim.
    function recognizesBreach(T.ObjectRef calldata object, bytes32 eventRef, uint8 obligationKind, bytes32 proposition, T.Value breachWhen)
        external view returns (bool);
}
