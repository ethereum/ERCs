// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IADRFJudgmentMethod — method for JUDGED sub-questions
/// @notice A judgment method runs a procedure elsewhere (the reference bridges to an ERC-8436 registry),
///         then pushes the finding to the dispute registry through `recordJudgedFinding`, which accepts it
///         only from the method bound to that sub-question. `open` is called by the registry when a JUDGED
///         sub-question is opened; `review` when a review round targets it; `maxDuration` is checked at
///         policy registration against the policy's decision window.
interface IADRFJudgmentMethod {
    /// ERC-165: implementers MUST report `type(IADRFJudgmentMethod).interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function maxDuration(bytes32 params) external view returns (uint64);
    function open(bytes32 caseId, uint32 subQuestion, bytes32 proposition, bytes32 params, uint64 deadline)
        external returns (bytes32 handle);
    function review(bytes32 caseId, uint32 subQuestion) external;
}
