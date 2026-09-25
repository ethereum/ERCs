// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Minimal reference surface for the agent off-chain conditional
/// settlement extension. A complete reference implementation with tests is
/// maintained at https://github.com/Aboudjem/erc-8203-ref.
interface IAgentConditionalSettlementExtension {
    enum LockStatus {
        None,
        Locked,
        Settled,
        Refunded
    }

    struct ConditionalLock {
        bytes32 channelId;
        address initiator;
        address responder;
        bytes32 assetId;
        uint256 amount;
        uint256 fee;
        uint256 expiry;
        bytes32 conditionType;
        bytes32 conditionCommitment;
        bytes32 applicationCommitment;
        bytes32 escrowCommitment;
        uint256 channelNonce;
    }

    struct SettlementProofRef {
        bytes32 channelId;
        bytes32 lockId;
        bytes32 proofType;
        bytes32 settlementRoot;
        bytes32 proofDigest;
        address verifier;
        bytes32 auxDataHash;
    }

    event ConditionalLockSettled(
        bytes32 indexed channelId,
        bytes32 indexed lockId,
        bytes32 indexed proofType,
        bytes32 proofDigest
    );

    event ConditionalLockRefunded(
        bytes32 indexed channelId,
        bytes32 indexed lockId
    );

    function settleConditional(
        bytes32 channelId,
        ConditionalLock calldata lock,
        SettlementProofRef calldata proofRef,
        bytes calldata proof
    ) external;

    function refundConditional(bytes32 channelId, bytes32 lockId) external;

    function lockStatus(bytes32 channelId, bytes32 lockId)
        external
        view
        returns (LockStatus);

    function supportsConditionType(bytes32 conditionType)
        external
        view
        returns (bool);

    function supportsProofType(bytes32 proofType)
        external
        view
        returns (bool);
}
