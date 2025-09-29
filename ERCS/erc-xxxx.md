---
title: Agent Council Oracles
description: Multi-agent councils to resolve information queries decentralized
author: Rohan Parikh (@phiraml), Jon Michael Ross (@jonmross)
discussions-to: Link will be added
status: Draft
type: Standards Track  
category: ERC  
created: 2025-09-28  
---

## Abstract

This ERC defines a standard interface for oracle contracts that use multi-agent councils to resolve information queries in a decentralized manner.  It enables dApps to request resolutions, general information arbitration, and build consensus and validation in a trust-minimized way, with agents submitting information on-chain. The interface supports permissionless participation, bond-based incentives, and optional extensions for reputation, disputes, and callbacks, making it suitable for applications like semantic data oracles and prediction markets. 

## Motivation

With AI agents advancing rapidly, we can build trust-minimized oracles that are cheaper, faster, and more scalable than traditional human or node-based systems. Traditional data oracles primarily provide quantitative feeds and are often centralized or expensive for arbitrary, one-off queries. With AI agents becoming reliable for factual resolutions from public sources, this EIP standardizes an interface for agent councils to handle query resolution via commit-reveal-judging flows, fostering interoperability across implementations. It is generalizable for discrete (defined options) or open-ended queries, with hooks for collusion deterrence and verification. Integration with reputation systems (such as that in ERC-8004) is recommended but optional to keep the core lightweight.

This is generalizable for any resolvable information, making it useful for both qualitative and quantitative data. Existing examples we see this standard being useful for are, tracing information tasks (off-chain data processing with on-chain validation hooks), resolving prediction markets, and creating verified info feeds for DeFi platforms (aggregating real-time semantic data from multiple sources).

We envision an information market evolving where agents compete to answer queries, exchanging data resolutions for tokenized incentives.


## Specification

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “NOT RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119 and RFC 8174.

This EIP proposes the `IAgentCouncilOracle` interface, which defines methods and events for a council-based resolution flow. Implementations MUST support the core flow: request creation, agent commitment, reveal, judging/aggregation, and reward distribution. Off-chain processing (LLM inference and analysis) is handled by agents, with on-chain elements opened to coordination and verification of information.

The council consists of two agent roles: Info Agents (who submit individual information) and Judge Agents (who aggregate and resolve consensus). We make this distinction to clarify how responsibilities from this standard are assigned.

### Main Types

```solidity
   // Struct for query requests
    struct AgentCapabilities {
        string[] capabilities; // text, vision, audio etc
        string[] domains; // Expertise areas
    }

    struct Request {
        address requester;
        uint256 reward;  // Total reward (native token or ERC-20)
        address rewardToken;  // native or ERC-20 token
        uint256 bondAmount;  // Bond per agent
        uint256 numInfoAgents;  // Target number of info agents
        uint256 deadline;  // Timestamp for commit phase end
        string query;  // The information query
        string specifications; // Additional miscellaneous instructions (optional in implementations)
        AgentCapabilities requiredCapabilities;  // For filtering agents (optional in implementations)
    }
```

### Interface

```solidity
interface IAgentCouncilOracle {
    // Events for transparency and monitoring
    event RequestCreated(uint256 indexed requestId, address requester, string query, uint256 reward, uint256 numInfoAgents, uint256 bondAmount);
    event AgentCommitted(uint256 indexed requestId, address agent, bytes32 commitment);
    event AgentRevealed(uint256 indexed requestId, address agent, bytes answer);  // Or bytes for flexibility
    event JudgeSelected(uint256 indexed requestId, address judge);
    event ResolutionFinalized(uint256 indexed requestId, bytes finalAnswer);  // Or bytes
    event RewardsDistributed(uint256 indexed requestId, address[] winners, uint256[] amounts);
    event ResolutionFailed(uint256 indexed requestId, string reason);
    event DisputeInitiated(uint256 indexed requestId, address disputer, string reason);
    event DisputeWindowOpened(uint256 indexed requestId, uint256 endTimestamp);
    event DisputeResolved(uint256 indexed requestId, bool overturned, bytes finalAnswer);
    

    // Core methods
    function createRequest(string calldata query, uint256 numInfoAgents, uint256 bondAmount, uint256 deadline, address rewardToken, string calldata specifications, AgentCapabilities calldata requiredCapabilities) external payable returns (uint256 requestId);
    // Commit: Permissionless, with bond
    function commit(uint256 requestId, bytes32 commitment) external payable;
    // Reveal: Submit answer matching commitment
    function reveal(uint256 requestId, bytes calldata answer, uint256 nonce) external;
    // Judge/Aggregate: Called by selected judge or automatic for discrete option queries
    function aggregate(uint256 requestId, bytes calldata finalAnswer, address[] calldata winners, bytes calldata reasoning) external;  // Winners for reward classification
    // Distribute: Auto or manual post-aggregation
    function distributeRewards(uint256 requestId) external;
    // Get final resolution
    function getResolution(uint256 requestId) external view returns (bytes memory finalAnswer, bool finalized);

    // Optional Dispute Methods
    function initiateDispute(uint256 requestId, string calldata reason) external payable;
    function resolveDispute(uint256 requestId, bool overturn, bytes calldata newAnswer, address[] calldata newWinners) external;

    // Getters for oracle flow data
    function getRequest(uint256 requestId) external view returns (Request memory);
    function getCommits(uint256 requestId) external view returns (address[] memory agents, bytes32[] memory commitments);
    function getReveals(uint256 requestId) external view returns (address[] memory agents, bytes[] memory answers);
}
```

### Core Flow

Implementations MUST follow this sequence for interoperability:

1. **Request Creation**: Requester calls `createRequest`, providing query, params (ex. `numInfoAgents`, `bondAmount`), and reward (with `msg.value` or ERC-20 transfer). Emits `RequestCreated`. Bond is a stake to deter spam and actual enforcement or amount is implementation-specific.

2. **Commit Process**: Permissionless Info Agents call `commit` with a hash (RECOMMENDED: `keccak256(abi.encode(answer, nonce))`) and bond. Caps at `numInfoAgents`. Phase ends at deadline or when all InfoAgents are committed. Emits `AgentCommitted`. 

3. **Reveal/Collection Process**: Committed Info Agents call `reveal` to submit answers. MUST match commitment. Emits `AgentRevealed`. Proceed only if quorum (RECOMMENDED:  >50% reveals) otherwise emit `ResolutionFailed` and refund. This helps reduce coordination/collusion of submissions as they aren’t revealed early.

4. **Judging Process**: After reveals, select a Judge Agent (RECOMMENDED: randomly from a separate pool, distinct from Info Agents) and emit `JudgeSelected`. The Judge Agent calls `aggregate` to submit the final answer and classify winners (majority agents). For discrete queries (predefined options), implementations MUST auto-count revealed votes and pick majority (>50%). For open-ended queries, the Judge MUST synthesize revealed submissions (semantic consensus via LLM) and provide reasoning as part of the submission. In ties for discrete queries, the Judge MAY provide a tie-breaker with reasoning. Emits `ResolutionFinalized`.

5. **Reward Distribution Process**: Call `distributeRewards` to payout correct Info Agents / Judge Agent based on config (proportional or equal splits, with implementation specific params for ratios like Judge fee percentage). Refund bonds to correct Info Agents; forfeit others. Emits `RewardsDistributed`. Implementations MAY forfeit the Judge Agent’s bond and redistribute to correct Info Agents or proposer if the judge fails to resolve within the allotted window.

Off-chain storage (such as IPFS for reveals/reasoning) MAY be used, with on-chain hashes for verifiability.

### Optional Extensions

 **Dispute Standard**: Implementations MAY add a dispute mechanism post-finalization.  

Suggested flow: After finalization, open a dispute window. Any party MAY call `initiateDispute` with a `disputeBond` (ex.  1.5-2x original bond) and on-chain reason (such as  a hash of detailed reasoning, optionally on IPFS), emitting `DisputeInitiated`. Re-select a Judge (randomly, with higher minReputation threshold). Judge reviews and calls `resolveDispute` to uphold or overturn, submitting new answers/winners if overturned. If upheld, the disputer’s bond is forfeited to the correct agents and arbitration creator. If overturned, return the disputer's bond, provide reimbursement (ex. a portion of the base fee), slash the original Judge's fee/bond, and redistribute. Dispute Judge receives reimbursement (ex. some fixed/percentage fee). Emits `DisputeResolved`. 

Configurable params: `disputeWindow` (duration), `disputeBond`, `minDisputeJudgeReputation` (higher than original), `disputerReimbursement`, `judgeReimbursement`. MAY integrate ERC-8004 for re-runs/proofs with validation hooks; partial payouts/escrow during window for efficiency.


**Reputation Hooks**: MAY integrate with ERC-8004 for filtering (min reputation for agents or judges) or proportional rewards. RECOMMENDED: Set a minimum reputation for Judge Agents, higher than for Info Agents, as they make a final decision. This creates an identifiable on-chain trail for accountability.


**Callbacks**: MAY add `callback(address target, uint256 requestId)` for notifying requester contracts.


**ERC-20 Rewards**: Extend with token transfers instead of the native token.

Configs (such as phase durations, quorums, reward ratios) are implementation-specific parameters.

## Rationale

This interface standardizes a council flow for AI-driven oracles, balancing minimal on-chain logic with off-chain flexibility. Commit-reveal prevents front-running and judging enables consensus on complex queries. Bonds and optional reputation help deter attacks.

Reputation scores provide a rationale for enhanced security: they enable proportional reward distribution, gating participation to experienced agents, and reducing collusion risks by aligning incentives with proven performance. Without reputation, attack vectors may increase, but the core bond system offers baseline protection and we expect this baseline to allow for a self regulating rewards incentive market that drives agents to act in good faith.

## Backwards Compatibility

No conflicts with existing standards. 

## Test Cases
This protocol allows for:
Standardized interfaces for AI agent councils to resolve complex queries in dApps, such as aggregating semantic data from multiple sources or handling one-off factual resolutions
Permissionless participation in oracle resolution with bond-based incentives for Info and Judge Agents, allowing scalable, trust-minimized data validation
Interoperability across oracle implementations for use in prediction markets, DeFi info feeds, betting, insurance, and knowledge arbitration
Optional extensions for disputes and reputation (such as ERC-8004) to enhance security for high-stakes queries, including verifiable off-chain reasoning trails

## Reference Implementation

We are currently working on a full implementation of this protocol. Reach out on Twitter `(@phiralm or @MythyProd)` if you would like to contribute!

## Security Considerations

- Collusion: Mitigated by bonds (refundable for honest participation, forfeited for failures), random judge selection, and optional reputation. Bonds disincentivize spam and non-reveals by redistributing to participants.
- Spam: Prevented by bonds and caps.
- Failures: Refunds for low participation or abandonment.
- Disputes: Optional for high-stakes, with higher stakes/thresholds.

Implementations SHOULD audit for reentrancy and use verifiable randomness.

## Copyright

Copyright and related rights waived via CC0.
