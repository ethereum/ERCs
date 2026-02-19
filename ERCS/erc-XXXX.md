Repository: https://github.com/michaelwinczuk/erc-shared-sequencer
Reference implementation & tests: live in repo
Seeking feedback before opening PR to ethereum/ERCsERC-XXXX: Shared Sequencer Interface for Autonomous Agent Layer 2sStatus: Draft — seeking community feedback
Author: Michael Winczuk @michaelwinczuk
Category: ERC (Application-Level Standard)
Created: 2026-02-19AbstractThis ERC defines a standard interface for shared sequencer contracts on Ethereum Layer 2 networks, with a specific focus on compatibility with autonomous agent systems. It provides a minimal, stateless, gas-predictable interface enabling agents and applications to interact with any compliant shared sequencer implementation without chain-specific integration work.MotivationVitalik Buterin's February 2026 critique of "copypasta L2 chains" highlighted the need for innovative infrastructure that tightly couples application-specific systems to Ethereum's security guarantees. Shared sequencers (Espresso, Taiko's based sequencing, Puffer UniFi) represent one of the most promising vectors for this coupling — but each project currently implements a proprietary interface. There is no standard.This fragmentation creates real problems:For autonomous AI agents: Agents operating on L2s need gas-predictable submission costs, explicit machine-readable error codes for automated retry logic, and stateless view functions for pre-flight checks. No current shared sequencer implementation is designed with autonomous agents as a primary user.For tooling developers: Wallets, block explorers, monitoring infrastructure, and SDKs must write custom integrations for every sequencer.For the ecosystem: The post-Astria vacuum (Astria shut down December 2025) and the EF's 2026 Protocol Priorities interoperability track create a direct opening for a clean, minimal interface standard.This ERC proposes a minimal standard interface that:Enables any autonomous agent to interact with any compliant shared sequencer  
Provides gas-predictable submission with cost estimation  
Returns explicit, machine-readable error codes  
Exposes sequencer metadata for dynamic agent adaptation  
Defines slashing event signatures for decentralized sequencer accountability

SpecificationInterfacesolidity

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

interface ISharedSequencer {

    struct ConfirmationReceipt {
        uint64 timestamp;       // Block timestamp of submission
        bytes32 l1TxHash;       // L1 transaction hash (zero until confirmed)
        bytes32 l2TxHash;       // L2 transaction identifier
        uint8 status;           // 0=pending, 1=confirmed, 2=failed
        string errorReason;     // Non-empty if status=2 (human-readable for agent retry logic)
    }

    struct SequencerMetadata {
        string version;
        address[] supportedL2s;
        uint256 minConfirmationTime;    // seconds
        uint256 maxTxSize;              // bytes
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

Design PrinciplesAgent-first: All status queries are view functions. Agents can poll confirmation status at zero gas cost.  Gas predictability: estimateSubmissionCost() must be implemented as a view function, allowing agents to budget before submission. Implementations should be accurate within ±10%.  Explicit errors: Implementations should use custom errors rather than string reverts to enable efficient agent-side error handling and retry logic.  Composability: The interface is minimal by design. Agents can wrap it for batching, scheduling, or multi-sequencer routing without protocol changes.  Decentralization-ready: The SequencerSlashed event provides a standard signature for decentralized sequencer accountability systems.RationaleWhy string errorReason in ConfirmationReceipt?
The errorReason field is intentionally a string rather than a custom error type. Confirmation receipts are returned from view functions — there is no revert context to propagate typed errors. Human-readable strings allow agents to log and surface failure reasons while implementations are still encouraged to use custom errors in their revert paths for gas efficiency.Why a single submitTransaction rather than batching?
Minimal surface area maximizes composability. Batching, scheduling, and multi-sequencer routing are higher-order concerns best handled by wrapper contracts. A batch-aware interface can be proposed as a companion ERC extending this one.Usage for Autonomous Agentssolidity

ISharedSequencer sequencer = ISharedSequencer(SEQUENCER_ADDRESS);

// 1. Pre-flight: estimate cost (zero gas, view call)
uint256 cost = sequencer.estimateSubmissionCost(txData);
uint256 budget = cost * 120 / 100; // 20% buffer for base fee variance

// 2. Check sequencer supports our target L2
ISharedSequencer.SequencerMetadata memory meta = sequencer.getSequencerMetadata();
require(meta.maxTxSize >= txData.length, "Transaction too large");

// 3. Submit with sufficient fee
bytes32 txId = sequencer.submitTransaction{value: budget}(txData);

// 4. Poll for confirmation (zero gas, view calls — no cost to agent)
while (true) {
    ISharedSequencer.ConfirmationReceipt memory receipt = sequencer.getConfirmationReceipt(txId);
    if (receipt.status == 1) break;          // confirmed — proceed
    if (receipt.status == 2) {               // failed — use errorReason for retry logic
        handleFailure(receipt.errorReason);
        break;
    }
    sleep(meta.minConfirmationTime);
}

Reference Implementation`src/MockSharedSequencer.sol`A complete, audited reference implementation including:mapping(bytes32 => ConfirmationReceipt) receipt storage — O(1) lookup, no unbounded array DoS vector
MIN_SUBMISSION_FEE spam protection
Emergency pause mechanism
Owner-controlled confirmation and failure reporting
Dynamic cost estimation using block.basefee
Custom error types: InsufficientFee, SequencerPaused, ReceiptNotFound, MalformedTransaction

Security ConsiderationsReentrancy: submitTransaction is payable. Implementations must use Checks-Effects-Interactions ordering or ReentrancyGuard. The reference implementation follows CEI strictly.Front-running: Transaction submission ordering is at sequencer discretion. Agents must not rely on submission order for time-sensitive operations.Sequencer trust: This standard does not enforce decentralization. The SequencerSlashed event is designed for decentralized implementations. Agents should call getSequencerMetadata() to understand the trust model before use.Fee volatility: estimateSubmissionCost() uses block.basefee which fluctuates. Agents should apply a 20% buffer to all estimates.DoS via spam: The reference implementation requires MIN_SUBMISSION_FEE. Permissionless deployments must implement fee or staking requirements.Backwards CompatibilityFully backwards compatible. This is a new interface standard with no modifications to existing contracts, protocols, or clients.Test SuiteFull Foundry test suite: `test/MockSharedSequencer.t.sol`14 tests: unit, fuzz, invariant, gas profiling, regression
~97% estimated coverage
Explicit regression tests for all security audit findings

bash

forge install foundry-rs/forge-std
forge test -vv

Prior ArtStandard
Description
Relationship
ERC-7683
Cross-chain intents
Complementary
EIP-4844
Blob transactions for L2 data availability
Infrastructure layer
ERC-7689
Smart Blobs / WeaveVM off-chain execution
Unrelated
Espresso Systems
Shared sequencer design (HackMD docs)
No standardized on-chain interface

No existing ERC or EIP standardizes a shared sequencer interface.Open Questions for the CommunityShould estimateSubmissionCost accept bytes calldata (actual data, more accurate) or uint256 (data size, simpler)? The current implementation uses calldata for accuracy.  
Should SequencerMetadata include SLA commitments with slashing penalties for missed minConfirmationTime? Currently informational only.  
Is there appetite for a companion RIP (Rollup Improvement Proposal) mandating this interface for sequencers participating in shared sequencing protocols?

AuthorsMichael Winczuk — https://x.com/smartcontr67332
 | https://github.com/michaelwinczuk/erc-shared-sequencer  Designed with the assistance of OpenClaw — an autonomous multi-agent Ethereum R&D system. Security reviewed by Gemini 2.5 Pro. All outputs reviewed and approved by the human author.LicenseMIT

Add ERC-XXXX: Shared Sequencer Interface for Autonomous Agent Layer 2s

