// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  ITaskTenderKernel — the subset of the token-bound task tender kernel interface
///         (TASK-KERNEL v3.0 of the task tender draft) used by the ACDF adapter. Struct layouts
///         and signatures are copied verbatim from that kernel so that ABI decoding of the
///         returned structs matches its deployed contract. Informative: the adapter, not the
///         registries, depends on it.
interface ITaskTenderKernel {
    struct TenderTerms {
        address asset;
        uint256 rewardPerCompletion;
        uint64  maxCompletions;
        uint64  submitBy;
        uint64  settleBy;
        uint64  epochLength;
        uint64  maxCompletionsPerEpoch;
        uint64  judgmentWindow;
    }

    enum SubmissionStatus { Pending, Accepted, Rejected }

    struct Submission {
        address          fulfiller;
        bytes32          resultHash;
        uint64           taskVersion;
        uint64           submittedAt;
        bool             machineSettled;
        SubmissionStatus status;
    }

    struct TaskBinding {
        bytes32 tdHash;
        bytes32 taskHash;
        uint64  version;
    }

    function tenderTermsOf(uint256 tokenId) external view returns (TenderTerms memory);
    function acceptanceAuthorityOf(uint256 tokenId) external view returns (address);
    function submissionOf(uint256 tokenId, uint256 submissionId) external view returns (Submission memory);
    function taskOf(uint256 tokenId) external view returns (TaskBinding memory);

    /// Judged settlement path. Only the acceptance authority. Reverts past `settleBy`.
    function acceptFulfillment(uint256 tokenId, uint256 submissionId) external;
    /// Terminal per submission; judged path only. Reverts past `submittedAt + judgmentWindow`.
    function rejectFulfillment(uint256 tokenId, uint256 submissionId) external;
}
