// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Match, SubjectRef, Request} from "./AWFTypes.sol";

/// @title Evaluator of a PREDICATE list
/// @notice Decides at query time whether a subject satisfies the criteria of a list.
interface IAWFEvaluator {
    /// @notice A value that changes whenever logic or configuration that can affect a result
    /// changes. A registry compares it, together with the code hash, with what the criteria pinned.
    function configHash() external view returns (bytes32);

    /// @param listId the list the result is for
    /// @param rule the parameter set named by the criteria
    /// @param subject the object the question is about
    /// @param request the request as established by the caller
    /// @param evidence what the requester presents; its format is defined by the evaluator
    /// @return result MATCH or NO_MATCH only where the criteria settle it; otherwise UNDETERMINED
    /// @return reason code from an open vocabulary
    /// @return validUntil until when the result may be relied on; 0 for this call only
    /// @return basis commitment to the evidence and sources the result rests on
    function evaluate(
        bytes32 listId,
        bytes32 rule,
        SubjectRef calldata subject,
        Request calldata request,
        bytes calldata evidence
    ) external view returns (Match result, bytes32 reason, uint64 validUntil, bytes32 basis);
}
