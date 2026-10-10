// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title EvaluatorRegistry mock with stake tracking — extends the slash
///        pattern from Scenario 2 with an EvaluatorStakeUpdated event for
///        stateless solvency assessment (Scenario 4).
/// @dev   Event signatures:
///        - EvaluatorSlashed: 4-field canonical signature agreed with
///          Demsys (github.com/Demsys/agent-settlement-protocol) in the
///          ERC-8183 Ethereum Magicians thread.
///        - EvaluatorStakeUpdated: designed collaboratively in the same
///          thread. oldBalance/newBalance refinement contributed by
///          ThoughtProof for stateless-indexer compatibility.
contract EvaluatorRegistryWithStake {
    event EvaluatorSlashed(
        address indexed evaluator,
        uint256 indexed jobId,
        uint256 amount,
        bytes32 reason
    );

    event EvaluatorStakeUpdated(
        address indexed evaluator,
        uint256 oldBalance,
        uint256 newBalance
    );

    struct SlashRecord {
        address evaluator;
        uint256 jobId;
        uint256 amount;
        bytes32 reason;
        uint256 timestamp;
    }

    mapping(address => uint256) public stakeBalances;
    mapping(uint256 => SlashRecord) public slashRecords;
    uint256 public slashCount;

    function depositStake(uint256 amount) external {
        require(amount > 0, "Registry: amount is 0");
        uint256 oldBalance = stakeBalances[msg.sender];
        stakeBalances[msg.sender] = oldBalance + amount;
        emit EvaluatorStakeUpdated(msg.sender, oldBalance, oldBalance + amount);
    }

    /// @dev Emits both EvaluatorSlashed and EvaluatorStakeUpdated in the
    ///      same transaction for stateless solvency assessment.
    function slashEvaluator(
        address evaluator,
        uint256 jobId,
        uint256 amount,
        bytes32 reason
    ) external {
        uint256 oldBalance = stakeBalances[evaluator];
        require(oldBalance >= amount, "Registry: insufficient stake");
        stakeBalances[evaluator] = oldBalance - amount;
        slashRecords[jobId] = SlashRecord({
            evaluator: evaluator,
            jobId:     jobId,
            amount:    amount,
            reason:    reason,
            timestamp: block.timestamp
        });
        slashCount++;
        emit EvaluatorSlashed(evaluator, jobId, amount, reason);
        emit EvaluatorStakeUpdated(evaluator, oldBalance, oldBalance - amount);
    }

    /// @dev Returns bytes32(0) for non-existent records.
    function buildEvidenceHash(uint256 jobId) external view returns (bytes32) {
        SlashRecord memory r = slashRecords[jobId];
        if (r.timestamp == 0) return bytes32(0);
        return keccak256(abi.encode(r.evaluator, r.jobId, r.amount, r.reason, r.timestamp));
    }

    function buildStakeEvidenceHash(address evaluator) external view returns (bytes32) {
        return keccak256(abi.encode(evaluator, stakeBalances[evaluator]));
    }
}
