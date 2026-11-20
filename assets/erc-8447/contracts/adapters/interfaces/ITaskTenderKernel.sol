// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  ITaskTenderKernel — the subset of the token-bound task tender kernel interface
///         (TASK-KERNEL v3.0 of the task tender draft) used by the swarm tender adapter. Struct
///         layouts and signatures are copied verbatim from that kernel so that ABI decoding of
///         the returned structs matches its deployed contract. Informative: the adapter, not the
///         registry, depends on it.
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
    function submissionCountOf(uint256 tokenId) external view returns (uint256);
    function isTenderCancelled(uint256 tokenId) external view returns (bool);
    function escrowBalanceOf(uint256 tokenId) external view returns (uint256);
    function creditOf(uint256 tokenId, address account) external view returns (uint256);

    /// Fulfiller path: the swarm account submits the deliverable and later withdraws its credit.
    function submitFulfillment(uint256 tokenId, bytes32 resultHash, string calldata resultURI) external returns (uint256 submissionId);
    function withdrawCredit(uint256 tokenId, address account) external;

    /// Judged settlement path. Only the acceptance authority. Reverts past `settleBy`.
    function acceptFulfillment(uint256 tokenId, uint256 submissionId) external;
    /// Terminal per submission; judged path only. Reverts past `submittedAt + judgmentWindow`.
    function rejectFulfillment(uint256 tokenId, uint256 submissionId) external;
}
