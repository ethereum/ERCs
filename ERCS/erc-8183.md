---
eip: 8183
title: Agentic Commerce
description: Job escrow with evaluator attestation for agent commerce.
author: Davide Crapis (@dcrapis), Bryan Lim (@ai-virtual-b), Tay Weixiong (@twx-virtuals), Chooi Zuhwa (@Zuhwa)
discussions-to: https://ethereum-magicians.org/t/erc-8183-agentic-commerce/27902
status: Draft
type: Standards Track
category: ERC
created: 2026-02-25
requires: 20
---

## Abstract

This specification defines the **Agentic Commerce Protocol**: a **job** with escrowed budget, four states (Open → Funded → Submitted → Terminal), and an **evaluator** who alone may mark the job completed. The client funds the job; the provider submits work; the evaluator attests completion or rejection once submitted (or the evaluator rejects while Funded before submission, or the client rejects while Open, or the job expires and the client is refunded). Optional attestation **reason** (e.g. hash) on complete/reject enables audit and composition with reputation (e.g. [ERC-8004](./eip-8004.md)).

## Motivation

Many use cases need only: client locks funds, provider submits work, one attester (evaluator) signals "done" and triggers payment—or client rejects or timeout triggers refund. The Agentic Commerce Protocol specifies that minimal surface so implementations stay small and composable. The evaluator can be the client (e.g. `evaluator = client` at creation) when there is no third-party attester.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### State Machine

A **job** has exactly one of six states:


| State         | Meaning                                                                                                           |
| ------------- | ----------------------------------------------------------------------------------------------------------------- |
| **Open**      | Created; budget not yet set or not yet funded. Client may set budget, then fund or reject.                        |
| **Funded**    | Budget escrowed. Provider may submit work; evaluator may reject. After `expiredAt`, anyone may trigger refund.    |
| **Submitted** | Provider has submitted work. Only evaluator may complete or reject. After `expiredAt`, anyone may trigger refund. |
| **Completed** | Terminal. Escrow released to provider (minus optional platform fee).                                              |
| **Rejected**  | Terminal. Escrow refunded to client.                                                                              |
| **Expired**   | Terminal. Same as Rejected; escrow refunded to client.                                                            |


Allowed transitions:

- **Open → Funded**: Client or provider calls `setBudget(jobId, amount)` to agree on price, then client calls `fund(jobId, expectedBudget)`; contract pulls `job.budget` from client into escrow.
- **Open → Rejected**: Client calls `reject(jobId, reason?)`.
- **Funded → Submitted**: Provider calls `submit(jobId, deliverable)`; signals that work has been completed and is ready for evaluation.
- **Funded → Rejected**: Evaluator calls `reject(jobId, reason?)`; contract refunds client.
- **Funded → Expired**: When `block.timestamp >= job.expiredAt`, anyone (or client) may call `claimRefund(jobId)`; contract sets state to Expired and refunds client.
- **Submitted → Completed**: Evaluator calls `complete(jobId, reason?)`; contract distributes escrow to provider (and optional fee to treasury).
- **Submitted → Rejected**: Evaluator calls `reject(jobId, reason?)`; contract refunds client.
- **Submitted → Expired**: When `block.timestamp >= job.expiredAt`, anyone (or client) may call `claimRefund(jobId)`; contract sets state to Expired and refunds client.

No other transitions are valid.

### Roles

- **Client**: Creates job (with description), may set provider via `setProvider(jobId, provider)` when job was created with no provider, sets budget with `setBudget(jobId, amount)`, funds escrow with `fund(jobId, expectedBudget)`, may reject **only when status is Open**. Receives refund on Rejected/Expired.
- **Provider**: Set at creation or later via `setProvider`. May call `setBudget(jobId, amount)` to propose or negotiate a price. Calls `submit(jobId, deliverable)` when work is done to move the job from Funded to Submitted for evaluation. Receives payment when job is Completed. Does not call `complete` or `reject`.
- **Evaluator**: Single address per job, set at creation. When status is Submitted, **only** the evaluator MAY call `complete(jobId, reason?)` or `reject(jobId, reason?)`. When status is Funded, the evaluator MAY call `reject(jobId, reason?)` (before submission). MAY be the client (e.g. `evaluator = client`) so the client can complete or reject the job without a third party, or MAY be a **smart contract** that performs arbitrary checks (e.g. verifying a zero‑knowledge proof or aggregating off‑chain signals) before deciding whether to call `complete` or `reject` on the job.

### Job Data

Each job SHALL have at least:

- `client`, `provider`, `evaluator` (addresses). **Provider MAY be zero at creation** (see Optional provider below).
- `description` (string) — set at creation (e.g. job brief, scope reference).
- `budget` (uint256)
- `expiredAt` (uint256 timestamp)
- `status` (Open | Funded | Submitted | Completed | Rejected | Expired)
- `hook` (address) — OPTIONAL. External hook contract called before and after core functions (see Hooks below). MAY be `address(0)` (no hook).

Payment SHALL use a single [ERC-20](./eip-20.md) token (global for the contract or specified at creation). Implementations MAY support a per-job token; the specification only requires one token per contract.

### Optional provider (set later)

Jobs MAY be created **without a provider** by passing `provider = address(0)` to `createJob`. In that case the client SHALL set the provider later via `setProvider(jobId, provider)` before funding. This supports flows such as bidding or assignment after creation.

- **setProvider(jobId, provider)**  
Called by **client** only. SHALL revert if job is not Open, current `job.provider != address(0)`, or `provider == address(0)`. SHALL set `job.provider = provider` and SHALL emit an event (e.g. ProviderSet). Implementations MAY allow an operator role to call setProvider in the future; this specification only requires client-only for the minimal protocol.
- **fund(jobId, expectedBudget)**
SHALL revert if `job.provider == address(0)` (provider MUST be set before funding) or if `job.budget != expectedBudget` (front-running protection).

### Core Functions

- **createJob(provider, evaluator, expiredAt, description, hook?)**
Called by client. Creates job in Open with `client = msg.sender`, `provider`, `evaluator`, `expiredAt`, `description`, and optional `hook` address. SHALL revert if `evaluator` is zero or `expiredAt` is not in the future. **Provider MAY be zero**; if so, client MUST call `setProvider` before `fund`. `hook` MAY be `address(0)` (no hook). Returns `jobId`.
- **setProvider(jobId, provider, optParams?)**
Called by client. SHALL revert if job is not Open, current `job.provider != address(0)`, or `provider == address(0)`. SHALL set `job.provider = provider`. `optParams` (bytes, OPTIONAL) is forwarded to the hook contract if set (see Hooks).
- **setBudget(jobId, amount, optParams?)**
Called by client or provider. Sets `job.budget = amount`. SHALL revert if job is not Open or caller is not client or provider. `optParams` forwarded to hook if set.
- **fund(jobId, expectedBudget, optParams?)**
Called by client. SHALL revert if job is not Open, caller is not client, budget is zero, **provider is not set** (`job.provider == address(0)`), or `job.budget != expectedBudget` (front-running protection). SHALL transfer `job.budget` of the payment token from client to the contract (escrow) and set status to Funded. `optParams` forwarded to hook if set.
- **submit(jobId, deliverable, optParams?)**
Called by provider only. SHALL revert if job is not Funded or caller is not the job's provider. SHALL set status to Submitted. `deliverable` (`bytes32`) is a reference to submitted work (e.g. hash of off-chain deliverable, IPFS CID, attestation commitment). SHALL emit an event including `deliverable` (e.g. JobSubmitted). `optParams` forwarded to hook if set.
- **complete(jobId, reason, optParams?)**
Called by evaluator only. SHALL revert if job is not Submitted or caller is not the job's evaluator. SHALL set status to Completed. SHALL transfer escrowed funds to provider (minus optional platform fee to a configurable treasury). `reason` MAY be `bytes32(0)` or an attestation hash (OPTIONAL). SHALL emit an event including `reason` if provided. `optParams` forwarded to hook if set.
- **reject(jobId, reason, optParams?)**
Called by **client when job is Open** or by **evaluator when job is Funded or Submitted**. SHALL revert if job is not Open, Funded, or Submitted, or caller is not the client (when Open) or the evaluator (when Funded or Submitted). SHALL set status to Rejected. If Funded or Submitted, SHALL refund escrow to client. `reason` OPTIONAL. SHALL emit an event including `reason` and the caller (rejector) if provided. `optParams` forwarded to hook if set.
- **claimRefund(jobId)**
Callable when job is Funded or Submitted and the job has expired (`block.timestamp >= expiredAt`). SHALL revert if job is not Funded or Submitted, or if the job has not yet expired. SHALL transfer full escrow to client and set status to Expired. MAY restrict caller (e.g. client only) or allow anyone; the specification RECOMMENDS allowing anyone to trigger refund after expiry.

### Attestation

- **complete(jobId, reason, optParams?)**: `reason` is an optional attestation commitment (e.g. `bytes32` hash of off-chain evidence). Implementations MAY use `string` and hash it internally. Events SHOULD include `reason` for indexing and composition with reputation systems. `optParams` forwarded to hook if set.
- **reject(jobId, reason, optParams?)**: Optional `reason` for audit; same treatment as above. `optParams` forwarded to hook if set.

### Fees

Implementations MAY charge a **platform fee** (basis points) on Completed, paid to a configurable treasury. The specification does not require a fee. If present, fee SHALL be deducted only on completion (not on refund).

### Hooks (OPTIONAL)

Implementations MAY support an optional **hook contract** per job to extend the core protocol without modifying it. The hook address is set at job creation (or `address(0)` for no hook) and stored on the job. A **non‑hooked kernel** that ignores the `hook` field (or always sets it to `address(0)`) is fully compliant with this specification; the reference `AgenticCommerce` contract follows this minimal pattern, while `AgenticCommerceHooked` is an **extension** that layers the hook callbacks on top of the same lifecycle.

A hook contract SHALL implement the `IACPHook` interface — just two functions:

```solidity
interface IACPHook {
    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
}
```

The `selector` parameter identifies which core function is being called (e.g. the function selector for `fund`). The `data` parameter contains function-specific parameters encoded as bytes (see Data encoding below). The hook uses the selector to route internally:

```solidity
function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external {
    if (selector == FUND_SELECTOR) {
        // custom pre-fund logic using data (optParams)
    } else if (selector == COMPLETE_SELECTOR) {
        // custom pre-complete logic using data (reason, optParams)
    }
}
```

When a job has a hook set, the core contract SHALL call `hook.beforeAction(...)` and `hook.afterAction(...)` around each hookable function:

| Core function  | Hookable |
| -------------- | -------- |
| `setProvider`  | Yes      |
| `setBudget`    | Yes      |
| `fund`         | Yes      |
| `submit`       | Yes      |
| `complete`     | Yes      |
| `reject`       | Yes      |
| `claimRefund`  | **No** — permissionless safety mechanism, SHALL NOT be hookable |

#### Data encoding

The `data` parameter passed to hooks contains the core function's parameters encoded as bytes. The encoding per selector:

| Core function  | `data` encoding                                      |
| -------------- | ---------------------------------------------------- |
| `setProvider`  | `abi.encode(address provider, bytes optParams)`       |
| `setBudget`    | `abi.encode(uint256 amount, bytes optParams)`         |
| `fund`         | `optParams` (raw bytes)                               |
| `submit`       | `abi.encode(bytes32 deliverable, bytes optParams)`    |
| `complete`     | `abi.encode(bytes32 reason, bytes optParams)`         |
| `reject`       | `abi.encode(bytes32 reason, bytes optParams)`         |

#### Hook behaviour

- The `optParams` field (`bytes`, OPTIONAL) on each hookable core function is an opaque payload forwarded to the hook via the `data` parameter. Callers that do not use hooks MAY pass empty bytes. The core contract SHALL NOT interpret `optParams`; it is for the hook only.
- **Before hooks** (`beforeAction`) are called before the core logic executes. A before hook MAY revert to block the action (e.g. enforce custom validation, allowlists, or preconditions).
- **After hooks** (`afterAction`) are called after the core logic completes (including state changes and token transfers). An after hook MAY perform side effects (e.g. emit events, update external state, trigger notifications) or revert to roll back the entire transaction.
- If `job.hook == address(0)`, the core contract SHALL skip hook calls and execute normally.

#### Hook security

- Hooks are **trusted** contracts chosen by the client at job creation. A malicious or buggy hook can revert valid actions or execute arbitrary logic in callbacks. Clients SHOULD audit or use well-known hook implementations.
- **Liveness:** A reverting hook can block all hookable actions for that job until `expiredAt`. This is by design — the hook is part of the job's policy. The guaranteed recovery path is `claimRefund` after expiry, which is deliberately **not hookable** so that refunds cannot be blocked.
- **Atomicity:** After-callbacks run after state changes but within the same transaction. If an after-callback reverts, the entire transaction (including the core state change) is rolled back. This is intentional — it enables atomic multi-step flows (e.g. escrow funding + side token transfer must both succeed or both revert).
- `onlyACP` modifiers on hooks are RECOMMENDED so that hook functions cannot be called directly by external actors.
- Hooks SHOULD NOT be upgradeable after a job is created, as this would allow the hook to change behaviour mid-job.
- Implementations MAY maintain an allowlist or registry of audited hook contracts to reduce risk for clients.

#### Convenience base contract (non-normative)

Implementations MAY provide a `BaseACPHook` that routes the generic `beforeAction`/`afterAction` calls to named virtual functions (e.g. `_preFund`, `_postComplete`) so hook developers only override what they need. This is NOT part of the standard — only `IACPHook` is normative.

#### Example use cases

- Pre-fund validation (e.g. KYC check, allowlist gate)
- Post-complete reputation updates (e.g. writing attestations to ERC-8004)
- Custom fee logic or payment splitting
- Atomic side transfers (e.g. fund transfer hook)
- Provider bidding (e.g. bidding hook)

---

#### Example 1 — Fund Transfer Hook (two-phase escrow)

**Problem:** A client hires an agent to convert/bridge/swap tokens (e.g. USDC → DAI). The client provides capital to the provider, who uses it to produce output tokens. The hook must ensure the provider deposits the output tokens before the job completes, then release them to the designated buyer.

**Solution:** A `FundTransferHook` that (a) stores a transfer commitment at `setBudget`, (b) forwards capital to the provider at `fund`, (c) pulls output tokens from the provider at `submit`, and (d) releases them to the buyer at `complete`.

```
Step 1 — createJob
  Client → createJob(provider, evaluator, expiredAt, desc, hook=FundTransferHook)
  Job created (Open), hook address stored.

Step 2 — setBudget
  Client → setBudget(jobId, serviceFee, optParams=abi.encode(buyer, transferAmount))
    → hook.beforeAction: decode optParams, store {buyer, transferAmount} as commitment.
    → core: job.budget = serviceFee

Step 3 — fund
  Client approves: core contract for serviceFee, hook for transferAmount.
  Client → fund(jobId, serviceFee, "")
    → hook.beforeAction: verify client approved hook for transferAmount. Revert if not.
    → core: pull serviceFee into escrow, set Funded.
    → hook.afterAction: pull transferAmount from client, forward to provider (capital).

Step 4 — provider uses capital to produce output tokens

Step 5 — submit
  Provider approves hook for transferAmount (output tokens).
  Provider → submit(jobId, deliverable, "")
    → hook.beforeAction: pull transferAmount from provider into hook (escrow).
    → core: set Submitted.

Step 6 — complete
  Evaluator → complete(jobId, reason, "")
    → core: release serviceFee to provider (minus platform fee).
    → hook.afterAction: release transferAmount from hook to buyer.

Recovery:
  - reject: hook.afterAction returns escrowed tokens to provider (if deposited).
  - expiry: claimRefund (not hookable) refunds serviceFee to client.
    Provider calls recoverTokens(jobId) on hook to recover deposited tokens.
```

**Key properties:** (1) The provider cannot submit without depositing output tokens. (2) The buyer only receives tokens when the evaluator completes the job. (3) On rejection or expiry, tokens are returned to the provider.

---

#### Example 2 — Bidding Hook

**Problem:** A client wants to hire the cheapest (or best) agent for a job but does not know upfront who to assign. The selection should be determined by an open bidding process, not unilaterally by the client after the fact.

**Solution:** A `BiddingHook` that verifies off-chain signed bids. Providers sign bid commitments off-chain; the client collects bids, selects the winner, and submits the winning bid's signature via `setProvider`. The hook's `beforeAction` callback recovers the signer and verifies it matches the chosen provider — proving the provider actually committed to that price.

Zero direct calls to the hook. All interactions flow through the core contract → hook callbacks.

```
Step 1 — createJob
  Client → createJob(provider=0, evaluator, expiredAt, desc, hook=BiddingHook)
  Job created (Open), provider = address(0).

Step 2 — setBudget (opens bidding via hook callback)
  Client → setBudget(jobId, maxBudget, optParams=abi.encode(biddingDeadline))
    → hook.beforeAction: store deadline for this jobId.

Step 3 — bidding happens OFF-CHAIN
  Providers sign: keccak256(abi.encode(chainId, hookAddress, jobId, bidAmount))
  Client collects signed bids and selects the winner.
  Core contract is unaware of bids.

Step 4 — setProvider + setBudget (hook verifies winning bid signature and enforces budget)
  Client → setProvider(jobId, winnerAddress, optParams=abi.encode(bidAmount, signature))
    → hook.beforeAction: verify deadline passed, recover signer from signature,
      validate signer == provider, store committed bidAmount. Revert if invalid.
    → core: job.provider = winnerAddress
    → hook.afterAction: mark bidding finalised (no further setProvider possible).
  Client → setBudget(jobId, bidAmount, "")
    → hook.beforeAction: enforce budget == committedAmount. Revert if mismatch.

Step 5 — job continues normally
  Client → fund(jobId, bidAmount, "")
  Provider → submit(jobId, deliverable, "")
  Evaluator → complete(jobId, reason, "")
```

**Key property:** The client cannot fabricate a provider commitment. The hook verifies the chosen provider actually signed a bid at the claimed price. The client is incentivised to pick the lowest bidder since they are the one paying.

---

### Events

Implementations SHOULD emit at least:

- **JobCreated**(jobId, client, provider, evaluator, expiredAt)
- **ProviderSet**(jobId, provider) — when provider is set on a job that was created without one
- **BudgetSet**(jobId, amount)
- **JobFunded**(jobId, client, amount)
- **JobSubmitted**(jobId, provider, deliverable) — when provider submits work for evaluation
- **JobCompleted**(jobId, evaluator, reason)
- **JobRejected**(jobId, rejector, reason)
- **JobExpired**(jobId)
- **PaymentReleased**(jobId, provider, amount)
- **Refunded**(jobId, client, amount)

## Rationale

- **Single attester after submission**: Once Submitted, only the evaluator can complete or reject; the client cannot pull funds back unilaterally, so the provider is protected after starting work. Evaluator = client covers the "no third party" case.
- **Explicit submission**: The Submitted state gives the evaluator (and indexers/UIs) a clear signal that the provider considers work done and ready for evaluation, separating "funded and in progress" from "work delivered".
- **Minimal surface**: Attestation is the optional `reason` on complete/reject; no additional ledger is required.
- **Four states**: Open, Funded, Submitted, and Terminal (Completed, Rejected, or Expired) are enough for "fund → work → submit → evaluate or refund".
- **Expiry**: Refund after `expiredAt` gives client a way to reclaim funds without an explicit reject.
- **Hooks over inheritance**: Optional hook contracts let integrators extend the protocol (validation, reputation, fees) without modifying or inheriting from the core contract. The core stays minimal; complexity lives in the hook.
- **Generic hook interface**: The `IACPHook` interface uses just two functions (`beforeAction`/`afterAction`) with a selector parameter rather than named functions per action. This keeps the interface stable as the core protocol evolves — new hookable functions simply produce new selector values without changing the interface.

### Extensions (OPTIONAL)

The following extensions are OPTIONAL and do not modify the core protocol. Implementations MAY adopt them independently.

#### Reputation / Attestation Interop (ERC-8004)
 
Agentic Commerce is intentionally minimal and does not embed a reputation system. For on-chain reputation and trust relationships between agents, implementations are RECOMMENDED to integrate with [ERC-8004](./eip-8004.md) (Trustless Agents).

The following patterns are RECOMMENDED:

- **Outcome‑based trust signals**
  - Each job outcome SHOULD be mapped into a trust signal for the participants:
    - `Completed`: positive signal for provider (and optionally evaluator) based on successful delivery.
    - `Rejected`: negative or neutral signal, depending on the reason and who rejected (client vs evaluator).
    - `Expired`: neutral or mildly negative signal for client (for not evaluating) or for provider (for not submitting), depending on higher‑level policy.
  - Implementations MAY emit ERC‑8004 compatible events or call ERC‑8004 registries when a job reaches a terminal state.

- **Evaluator attestations**
  - On `complete(jobId, reason, optParams?)` and `reject(jobId, reason, optParams?)`, the evaluator (which MAY be a contract) SHOULD:
    - produce an attestation or structured log that can be added to the ERC‑8004 **reputation registry** as feedback (e.g. "provider successfully completed job", "job rejected for reason X"). Attestations MAY reference the job, parties, and `reason` (e.g. a hash of off‑chain evidence).
    - and/or post a proof to the ERC‑8004 **validation registry**, which a hook (or evaluator contract) then reads in order to decide whether to mark the job as `Completed` or `Rejected`.
  - Hooks MAY be used to call into ERC‑8004 registries in `afterAction` for `complete`/`reject`, keeping the core ACP contract unaware of the registry details.

- **Reputation‑aware policy via hooks**
  - Hooks MAY consult ERC‑8004 data before allowing certain actions, for example:
    - preventing `setProvider` from assigning providers below a reputation threshold,
    - enforcing higher budgets or additional safeguards for low‑reputation agents,
    - dynamically selecting evaluators based on reputation.
  - Such checks belong in policy‑oriented `beforeAction` hooks so they can safely revert and block actions that violate reputation policies.

- **Separation of concerns**
  - ACP remains the **payment and escrow** layer; ERC‑8004 is the **identity and reputation** layer.
  - Interop is achieved by:
    - emitting events that ERC‑8004 indexers can consume, and/or
    - calling ERC‑8004 contracts from hooks or evaluator contracts.

---

#### Meta-Transactions / Facilitator Relay ([ERC-2771](./eip-2771.md))

To support gasless execution — where a client, provider, or evaluator signs an intent off-chain and a **facilitator** submits the transaction on their behalf — implementations SHOULD support [ERC-2771](./eip-2771.md) (Secure Protocol for Native Meta Transactions).

**How it works:**

1. A participant (client, provider, or evaluator) signs a meta-transaction off-chain (e.g. `createJob`, `fund`, `submit`).
2. A facilitator submits the signed payload to a **trusted forwarder** contract.
3. The forwarder verifies the signature and calls the ACP contract, appending the original signer's address.
4. The ACP contract uses `_msgSender()` (from `ERC2771Context`) instead of `msg.sender` to identify the caller.

**Implementation requirements:**

- The ACP contract SHALL inherit `ERC2771Context` (or equivalent) and use `_msgSender()` for all authorization checks (`client`, `provider`, `evaluator`).
- All role checks (e.g. "caller is client", "caller is provider") SHALL use `_msgSender()` rather than `msg.sender`.
- The trusted forwarder address SHALL be set at deployment and SHOULD be immutable.

```solidity
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

contract AgenticCommerce is ERC2771Context, ... {
    constructor(address trustedForwarder, ...)
        ERC2771Context(trustedForwarder) { ... }

    // Example: fund() using _msgSender() instead of msg.sender
    function fund(uint256 jobId, uint256 expectedBudget) external {
        Job storage job = jobs[jobId];
        if (_msgSender() != job.client) revert Unauthorized();
        if (job.budget != expectedBudget) revert BudgetMismatch();
        // ...
    }
}
```

**Token approvals:** For functions that pull tokens (e.g. `fund`), the signer SHOULD use [ERC-2612](./eip-2612.md) (`permit`) to approve token spending via signature. The facilitator can then call `permit` and `fund` in a single transaction — no on-chain approval tx needed from the signer.

**x402 compatibility:** This extension enables compatibility with HTTP-native payment protocols such as x402, where an AI agent signs payment intents off-chain and a payment facilitator handles on-chain execution. The agent only needs a private key and tokens — no gas, no RPC management, no chain-specific logic.

---

## Backwards Compatibility

No backward compatibility issues found.

## Reference Implementation

The reference implementation consists of two contracts: `IACPHook`, the optional and minimal hook interface that developers implement, and `AgenticCommerce`, the core Job primitive with escrow and optional hook extension points.

### IACPHook.sol

```solidity
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IACPHook is IERC165 {
    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
}
```

### AgenticCommerce.sol

```solidity
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import "./IACPHook.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

contract AgenticCommerce is Initializable, AccessControlUpgradeable, ReentrancyGuardTransient, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    enum JobStatus {
        Open,
        Funded,
        Submitted,
        Completed,
        Rejected,
        Expired
    }

    struct Job {
        uint256 id;
        address client;
        address provider;
        address evaluator;
        string description;
        uint256 budget;
        uint256 expiredAt;
        JobStatus status;
        address hook;
    }

    IERC20 public paymentToken;
    uint256 public platformFeeBP;
    address public platformTreasury;
    uint256 public evaluatorFeeBP;

    mapping(uint256 => Job) public jobs;
    uint256 public jobCounter;
    mapping(address => bool) public whitelistedHooks;
    mapping(uint256 jobId => bool hasBudget) public jobHasBudget;

    event JobCreated(
        uint256 indexed jobId, address indexed client, address indexed provider,
        address evaluator, uint256 expiredAt, address hook
    );
    event ProviderSet(uint256 indexed jobId, address indexed provider);
    event BudgetSet(uint256 indexed jobId, uint256 amount);
    event JobFunded(uint256 indexed jobId, address indexed client, uint256 amount);
    event JobSubmitted(uint256 indexed jobId, address indexed provider, bytes32 deliverable);
    event JobCompleted(uint256 indexed jobId, address indexed evaluator, bytes32 reason);
    event JobRejected(uint256 indexed jobId, address indexed rejector, bytes32 reason);
    event JobExpired(uint256 indexed jobId);
    event PaymentReleased(uint256 indexed jobId, address indexed provider, uint256 amount);
    event EvaluatorFeePaid(uint256 indexed jobId, address indexed evaluator, uint256 amount);
    event Refunded(uint256 indexed jobId, address indexed client, uint256 amount);
    event HookWhitelistUpdated(address indexed hook, bool status);

    error InvalidJob();
    error WrongStatus();
    error Unauthorized();
    error ZeroAddress();
    error ExpiryTooShort();
    error ZeroBudget();
    error ProviderNotSet();
    error FeesTooHigh();
    error HookNotWhitelisted();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address paymentToken_, address treasury_) public initializer {
        if (paymentToken_ == address(0) || treasury_ == address(0))
            revert ZeroAddress();

        __AccessControl_init();

        paymentToken = IERC20(paymentToken_);
        platformTreasury = treasury_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        whitelistedHooks[address(0)] = true;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ──────────────────── Admin ────────────────────

    function setPlatformFee(uint256 feeBP_, address treasury_) external onlyRole(ADMIN_ROLE) {
        if (treasury_ == address(0)) revert ZeroAddress();
        if (feeBP_ + evaluatorFeeBP > 10000) revert FeesTooHigh();
        platformFeeBP = feeBP_;
        platformTreasury = treasury_;
    }

    function setEvaluatorFee(uint256 feeBP_) external onlyRole(ADMIN_ROLE) {
        if (feeBP_ + platformFeeBP > 10000) revert FeesTooHigh();
        evaluatorFeeBP = feeBP_;
    }

    function setHookWhitelist(address hook, bool status) external onlyRole(ADMIN_ROLE) {
        if (hook == address(0)) revert ZeroAddress();
        whitelistedHooks[hook] = status;
        emit HookWhitelistUpdated(hook, status);
    }

    // ──────────────────── Hook Helpers ────────────────────

    function _beforeHook(address hook, uint256 jobId, bytes4 selector, bytes memory data) internal {
        if (hook != address(0)) {
            IACPHook(hook).beforeAction(jobId, selector, data);
        }
    }

    function _afterHook(address hook, uint256 jobId, bytes4 selector, bytes memory data) internal {
        if (hook != address(0)) {
            IACPHook(hook).afterAction(jobId, selector, data);
        }
    }

    // ──────────────────── Job Lifecycle ────────────────────

    function createJob(
        address provider, address evaluator, uint256 expiredAt,
        string calldata description, address hook
    ) external nonReentrant returns (uint256) {
        if (evaluator == address(0)) revert ZeroAddress();
        if (expiredAt <= block.timestamp + 5 minutes) revert ExpiryTooShort();
        if (!whitelistedHooks[hook]) revert HookNotWhitelisted();
        if (hook != address(0)) {
            if (!ERC165Checker.supportsInterface(hook, type(IACPHook).interfaceId))
                revert InvalidJob();
        }

        uint256 jobId = ++jobCounter;
        jobs[jobId] = Job({
            id: jobId,
            client: msg.sender,
            provider: provider,
            evaluator: evaluator,
            description: description,
            budget: 0,
            expiredAt: expiredAt,
            status: JobStatus.Open,
            hook: hook
        });

        emit JobCreated(jobId, msg.sender, provider, evaluator, expiredAt, hook);
        _afterHook(hook, jobId, msg.sig, abi.encode(msg.sender, provider, evaluator));

        return jobId;
    }

    function setProvider(uint256 jobId, address provider_) external {
        Job storage job = jobs[jobId];
        if (job.id == 0) revert InvalidJob();
        if (job.status != JobStatus.Open) revert WrongStatus();
        if (msg.sender != job.client) revert Unauthorized();
        if (job.provider != address(0)) revert WrongStatus();
        if (provider_ == address(0)) revert ZeroAddress();
        job.provider = provider_;
        emit ProviderSet(jobId, provider_);
    }

    function setBudget(uint256 jobId, uint256 amount, bytes calldata optParams) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.id == 0) revert InvalidJob();
        if (job.status != JobStatus.Open) revert WrongStatus();
        if (msg.sender != job.provider) revert Unauthorized();

        bytes memory data = abi.encode(msg.sender, amount, optParams);
        _beforeHook(job.hook, jobId, msg.sig, data);

        job.budget = amount;
        emit BudgetSet(jobId, amount);
        jobHasBudget[jobId] = true;

        _afterHook(job.hook, jobId, msg.sig, data);
    }

    function fund(uint256 jobId, bytes calldata optParams) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.id == 0) revert InvalidJob();
        if (job.status != JobStatus.Open) revert WrongStatus();
        if (msg.sender != job.client) revert Unauthorized();
        if (job.provider == address(0)) revert ProviderNotSet();
        if (block.timestamp >= job.expiredAt) revert WrongStatus();

        bytes memory data = abi.encode(msg.sender, optParams);
        _beforeHook(job.hook, jobId, msg.sig, data);

        job.status = JobStatus.Funded;
        if (job.budget > 0) {
            paymentToken.safeTransferFrom(job.client, address(this), job.budget);
        }
        emit JobFunded(jobId, job.client, job.budget);

        _afterHook(job.hook, jobId, msg.sig, data);
    }

    function submit(uint256 jobId, bytes32 deliverable, bytes calldata optParams) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.id == 0) revert InvalidJob();
        if (
            job.status != JobStatus.Funded &&
            (job.status != JobStatus.Open || job.budget > 0)
        ) revert WrongStatus();
        if (msg.sender != job.provider) revert Unauthorized();

        bytes memory data = abi.encode(msg.sender, deliverable, optParams);
        _beforeHook(job.hook, jobId, msg.sig, data);

        job.status = JobStatus.Submitted;
        emit JobSubmitted(jobId, job.provider, deliverable);

        _afterHook(job.hook, jobId, msg.sig, data);
    }

    function complete(uint256 jobId, bytes32 reason, bytes calldata optParams) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.id == 0) revert InvalidJob();
        if (job.status != JobStatus.Submitted) revert WrongStatus();
        if (msg.sender != job.evaluator) revert Unauthorized();

        bytes memory data = abi.encode(msg.sender, reason, optParams);
        _beforeHook(job.hook, jobId, msg.sig, data);

        job.status = JobStatus.Completed;

        uint256 amount = job.budget;
        uint256 platformFee = (amount * platformFeeBP) / 10000;
        uint256 evalFee = (amount * evaluatorFeeBP) / 10000;
        uint256 net = amount - platformFee - evalFee;

        if (platformFee > 0) {
            paymentToken.safeTransfer(platformTreasury, platformFee);
        }
        if (evalFee > 0) {
            paymentToken.safeTransfer(job.evaluator, evalFee);
            emit EvaluatorFeePaid(jobId, job.evaluator, evalFee);
        }
        if (net > 0) {
            paymentToken.safeTransfer(job.provider, net);
        }

        emit JobCompleted(jobId, job.evaluator, reason);
        emit PaymentReleased(jobId, job.provider, net);

        _afterHook(job.hook, jobId, msg.sig, data);
    }

    function reject(uint256 jobId, bytes32 reason, bytes calldata optParams) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.id == 0) revert InvalidJob();

        if (job.status == JobStatus.Open) {
            if (msg.sender != job.client) revert Unauthorized();
        } else if (job.status == JobStatus.Funded || job.status == JobStatus.Submitted) {
            if (msg.sender != job.evaluator) revert Unauthorized();
        } else {
            revert WrongStatus();
        }

        bytes memory data = abi.encode(msg.sender, reason, optParams);
        _beforeHook(job.hook, jobId, msg.sig, data);

        JobStatus prev = job.status;
        job.status = JobStatus.Rejected;

        if ((prev == JobStatus.Funded || prev == JobStatus.Submitted) && job.budget > 0) {
            paymentToken.safeTransfer(job.client, job.budget);
            emit Refunded(jobId, job.client, job.budget);
        }

        emit JobRejected(jobId, msg.sender, reason);

        _afterHook(job.hook, jobId, msg.sig, data);
    }

    function claimRefund(uint256 jobId) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.id == 0) revert InvalidJob();
        if (job.status != JobStatus.Funded && job.status != JobStatus.Submitted)
            revert WrongStatus();
        if (block.timestamp < job.expiredAt) revert WrongStatus();

        job.status = JobStatus.Expired;

        if (job.budget > 0) {
            paymentToken.safeTransfer(job.client, job.budget);
            emit Refunded(jobId, job.client, job.budget);
        }

        emit JobExpired(jobId);
    }

    // ──────────────────── View ────────────────────

    function getJob(uint256 jobId) external view returns (Job memory) {
        return jobs[jobId];
    }
}
```

## Security Considerations

- Evaluator is trusted for completion and rejection once the job is Submitted; a malicious evaluator can complete or reject arbitrarily. Use reputation (e.g. [ERC-8004](./eip-8004.md)) or staking for high-value jobs.
- Once Funded, only the evaluator can reject, and only the provider can submit; the client cannot unilaterally withdraw, which protects the provider after they start work.
- No dispute resolution or arbitration; reject/expire is final.
- Single payment token per contract reduces attack surface; per-job tokens are an extension.
- **Reentrancy:** Functions that transfer tokens SHALL be protected (e.g. reentrancy guard).
- **Tokens:** Use SafeERC-20 or equivalent for [ERC-20](./eip-20.md).
- **Evaluator:** MUST be set at creation; if "client completes", pass `evaluator = client`.
- **Hook gas limits** (for hooked implementations): Implementations SHOULD impose a gas limit on hook calls (e.g. `call{gas: HOOK_GAS_LIMIT}(...)`) to bound execution cost and prevent hooks from consuming unbounded gas. The specific limit is left to the implementation as gas costs vary across chains.
- Hook contracts are client-supplied and trusted by the client; implementations MUST NOT allow hooks to modify core escrow state directly. `claimRefund` is deliberately not hookable so that refunds after expiry cannot be blocked by a malicious hook.
- Jobs that use **advanced hooks** (e.g. two‑phase escrow / fund‑transfer hooks that custody additional tokens) are expected to have **more revert paths and tighter coupling** to external logic than plain, non‑hooked Agentic Commerce jobs. Such hooks SHOULD be reserved for agents and users who understand and accept this trade‑off; for most simple jobs, a non‑hooked or policy‑only hook is RECOMMENDED.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
