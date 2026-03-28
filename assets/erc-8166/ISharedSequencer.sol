// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

interface ISharedSequencer {

    struct ConfirmationReceipt {
        uint64 timestamp;
        bytes32 l1TxHash;
        bytes32 l2TxHash;
        uint8 status;
        string errorReason;
    }

    struct SequencerMetadata {
        string version;
        address[] supportedL2s;
        uint256 minConfirmationTime;
        uint256 maxTxSize;
    }

    event TransactionSubmitted(address indexed sender, bytes32 indexed transactionId, uint256 paidAmount);
    event TransactionConfirmed(bytes32 indexed transactionId, bytes32 l1TxHash, bytes32 l2TxHash);
    event TransactionFailed(bytes32 indexed transactionId, string errorReason);
    event SequencerSlashed(address indexed sequencer, uint256 slashAmount, string reason);

    function submitTransaction(bytes calldata transactionData) external payable returns (bytes32 transactionId);
    function getConfirmationReceipt(bytes32 transactionId) external view returns (ConfirmationReceipt memory);
    function estimateSubmissionCost(bytes calldata transactionData) external view returns (uint256 totalCostWei);
    function getSequencerMetadata() external view returns (SequencerMetadata memory);
}
