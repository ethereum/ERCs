# ERC-8210 — Reference Scenarios for Multi-Hop Workflows

> **Disclaimer:** These scenarios are independent of the test vectors in
> [PR #1647](https://github.com/ethereum/ERCs/pull/1647) and provide their own
> minimal mocks. They demonstrate composition patterns between ERC-8210 (Agent
> Assurance Protocol) and other specs — primarily ERC-8183 — using concrete,
> end-to-end Foundry tests.

## Architectural Context

The ERC-8183 discussion thread has converged on a **3-layer architecture** for
autonomous agent safety (articulated by [@wangbin9953](https://github.com/wangbin9953),
author of ERC-8210, in post #107 of the ERC-8183 Ethereum Magicians thread):

| Layer | Name | What it does | Enforced by |
|-------|------|-------------|-------------|
| **1** | **Structure** | Enforces what contracts can verify directly: auto-assignment, role separation, state machines | ERC-8183 core |
| **2** | **Behavior** | Evaluates behavioral independence and risk through hooks and oracles (`IRiskHook`, off-chain scorers) | Risk hooks, evaluator registries, scoring oracles |
| **3** | **Recovery** | Provides post-hoc redress when Layers 1 and 2 do not catch the attack in time | ERC-8210 / AAP |

The scenarios below demonstrate how Layer 3 (recovery) **composes** with
the other two layers through concrete, tested patterns. All scenarios use
the canonical ERC-8210 v1 interface, encoding their composition metadata
(upstream references, slash record references, off-chain scoring CIDs,
solvency snapshots) into the opaque `bytes calldata evidence` payload
that AAP's `fileClaim` already defines.

## Scenarios

| # | Scenario | Layers | Key pattern |
|---|----------|--------|-------------|
| 1 | [Multi-Hop Dependency Tracking](docs/scenario-1-multi-hop-dependency.md) | 3 (+ 1, 2 context) | Upstream reference encoded in `evidence` traces root cause across A→B→C→D pipeline |
| 2 | [EvaluatorSlashed → fileClaim](docs/scenario-2-evaluator-slash-claim.md) | 2 → 3 | Slash event serves as automatic proof for AAP claim — no re-adjudication |
| 3 | [Hybrid Off-chain Scoring](docs/scenario-3-hybrid-offchain-scoring.md) | 1 + 2 + 3 | Same `reasoningCID` consumed by task rejection and claim filing |
| 4 | [Solvency-Aware Claim Assessment](docs/scenario-4-solvency-aware-claim.md) | 2 → 3 | `EvaluatorSlashed` + `EvaluatorStakeUpdated` in the same tx enable stateless solvency assessment |

## Project Structure

```
scenarios/
├── README.md                                  # This file
├── foundry.toml
├── remappings.txt
├── .gitignore
├── contracts/
│   ├── interfaces/
│   │   ├── IAAP.sol                           # Minimal subset of ERC-8210 v1 interface
│   │   └── IERC20.sol                         # Minimal ERC-20 interface
│   └── mocks/
│       ├── AAPMockMinimal.sol                 # Minimal AAP implementation (deposit, commit, file, resolve, payout)
│       ├── MockERC20.sol                      # ERC-20 with mint
│       ├── EvaluatorRegistryMock.sol          # Slash events (Scenario 2)
│       ├── EvaluatorRegistryWithStake.sol     # Slash + stake tracking (Scenario 4)
│       ├── OffchainScorerMock.sol             # AHS-style scoring (Scenario 3)
│       └── ChainedJobsMock.sol                # Job pipeline A→B→C→D (Scenario 1)
├── docs/
│   ├── scenario-1-multi-hop-dependency.md
│   ├── scenario-2-evaluator-slash-claim.md
│   ├── scenario-3-hybrid-offchain-scoring.md
│   └── scenario-4-solvency-aware-claim.md
└── test/
    ├── Scenario1_MultiHopDependency.t.sol
    ├── Scenario2_EvaluatorSlashClaim.t.sol
    ├── Scenario3_HybridOffchainScoring.t.sol
    └── Scenario4_SolvencyAwareClaimAssessment.t.sol
```

## Build & Test

```bash
cd assets/erc-8210/scenarios

# Install dependencies (first time only)
forge install foundry-rs/forge-std --no-commit

# Run all scenario tests
forge test -vv
```

### Expected output

```
[PASS] test_MultiHopDependencyTracking()
[PASS] test_EvaluatorSlashToClaim()
[PASS] test_HybridOffchainScoring()
[PASS] test_SolvencyAwareClaimAssessment()
[PASS] test_ZeroStakePostSlash_FullWipeout()
```

## Spec Reference

- [ERC-8210: Agent Assurance Protocol](https://eips.ethereum.org/ERCS/erc-8210)
- [ERC-8183: Agent Task Coordination](https://eips.ethereum.org/ERCS/erc-8183)
