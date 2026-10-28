// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";

/// @title  IADRFObligationSource — what a bound business contract (or its adapter) attests to the registry
/// @notice The source derives every attested value from its own state, never from the caller: the
///         event instant and the business adoption deadline (its own clock), the obligation the event
///         belongs to, the norm it recognises and when that norm was declared, the obligation kind, and
///         who is a party. The registry cross-checks a claim against these attestations at admission.
interface IADRFObligationSource {
    /// ERC-165: implementers MUST report `type(IADRFObligationSource).interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function eventInfo(T.ObjectRef calldata object, bytes32 eventRef) external view returns (T.EventInfo memory);
    function isParty(T.ObjectRef calldata object, bytes32 eventRef, address account) external view returns (bool);
}
