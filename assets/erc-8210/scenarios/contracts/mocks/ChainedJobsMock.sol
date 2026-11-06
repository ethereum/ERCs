// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title Chained-jobs mock — simulates a pipeline of dependent jobs (Scenario 1).
/// @dev   Models a simplified A → B → C → D pipeline where each job depends on
///        the previous one.  When a job fails, downstream jobs can be traced back
///        to the root cause via the `upstream` field.
contract ChainedJobsMock {
    // ── Enums ──────────────────────────────────────────────────────────
    enum JobStatus { Pending, Running, Completed, Failed }

    // ── Events ─────────────────────────────────────────────────────────
    event JobCreated(uint256 indexed jobId, bytes32 indexed upstreamJobHash, bytes32 label);
    event JobStatusChanged(uint256 indexed jobId, JobStatus status);

    // ── State ──────────────────────────────────────────────────────────
    struct Job {
        bytes32   label;
        JobStatus status;
        uint256   upstreamJobId;    // 0 = root job (no upstream)
        bool      exists;
    }

    mapping(uint256 => Job) public jobs;
    uint256 public nextJobId;

    // ── Functions ──────────────────────────────────────────────────────

    /// @notice Create a new job in the pipeline.
    function createJob(bytes32 label, uint256 upstreamJobId) external returns (uint256 jobId) {
        if (upstreamJobId != 0) {
            require(jobs[upstreamJobId].exists, "ChainedJobs: upstream does not exist");
        }
        jobId = ++nextJobId; // 1-based
        jobs[jobId] = Job({
            label:         label,
            status:        JobStatus.Pending,
            upstreamJobId: upstreamJobId,
            exists:        true
        });
        bytes32 upHash = upstreamJobId == 0
            ? bytes32(0)
            : keccak256(abi.encode(upstreamJobId, jobs[upstreamJobId].label));
        emit JobCreated(jobId, upHash, label);
    }

    /// @notice Transition a job to a new status.
    function setStatus(uint256 jobId, JobStatus status) external {
        require(jobs[jobId].exists, "ChainedJobs: job does not exist");
        jobs[jobId].status = status;
        emit JobStatusChanged(jobId, status);
    }

    /// @notice Walk the chain from a given job back to the root, returning all
    ///         job IDs in reverse order (leaf → root).
    function traceToRoot(uint256 jobId) external view returns (uint256[] memory chain) {
        // First pass: count depth.
        uint256 depth;
        uint256 cursor = jobId;
        while (cursor != 0) {
            require(jobs[cursor].exists, "ChainedJobs: broken chain");
            depth++;
            cursor = jobs[cursor].upstreamJobId;
        }

        // Second pass: fill array.
        chain  = new uint256[](depth);
        cursor = jobId;
        for (uint256 i = 0; i < depth; i++) {
            chain[i] = cursor;
            cursor   = jobs[cursor].upstreamJobId;
        }
    }

    /// @notice Build a deterministic upstream hash that AAP can store.
    function upstreamHash(uint256 jobId) external view returns (bytes32) {
        require(jobs[jobId].exists, "ChainedJobs: job does not exist");
        return keccak256(abi.encode(jobId, jobs[jobId].label, jobs[jobId].upstreamJobId));
    }
}
