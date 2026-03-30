---
eip: xxxx
title: Smart Batching
description: A smart account batch encoding where each parameter is resolved at execution time from on-chain state, with inline constraints that enable dynamic transactions and predicate-gated cross-chain orchestration.
author: Mislav Javor (@oxshaman), Filip Dujmušić (@fichiokaku), Filipp Makarov (@filmakarov), Venkatesh Rajendran (@vr16x)
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-02-11
---

## Abstract

An Ethereum transaction is a single function call on a single contract. ERC-4337 and EIP-5792 (`wallet_sendCalls`) extended this with batch execution — multiple calls under one signature — but every parameter in these batches is static: frozen at signing time, blind to on-chain state at execution. If a swap returns fewer tokens than estimated, gas costs shift, or a bridge delivers with unexpected slippage — the batch reverts. The only workaround is deploying custom smart contracts for each multi-step flow, which introduces new attack surface and demands auditing, testing, and redeployment for every change — a poor security practice and an expensive, time-consuming process.

This ERC introduces **smart batching**: a batch encoding where each parameter declares *how to obtain its value at execution time* and *what conditions that value must satisfy*. Parameters can be literals, live `staticcall` results, or balance queries — each independently resolved on-chain and validated against inline constraints before being assembled into the call. Dustless full-balance transfers, dynamic token splitting, MEV-aware execution guards, and cross-protocol composition become trivial — no Solidity required.

The same mechanism produces cross-chain orchestration for free. A batch entry with no call target still resolves parameters and checks constraints, becoming a pure boolean gate on chain state — a *predicate entry*. Relayers simulate batches and submit when on-chain conditions are met. Multi-chain flows execute as a single signed program, each step gated by verifiable on-chain predicates.

Together, these primitives form a **verifiable scripting layer for the EVM**: developers author multi-step, multi-chain programs in TypeScript, compiled to a standard on-chain encoding, signed once, and executed entirely by the EVM. No contract deployment. No audit cycles for new flows.

This ERC standardizes the encoding formats and interfaces for smart batching. It is account-standard-agnostic: the same encoding works as an ERC-7579 module, ERC-6900 plugin, native account method, or ERC-7702 delegation target.

## Motivation

### Why Static Batching Is Insufficient

Real-world DeFi flows produce dynamic, unpredictable outputs:

- A swap yields a variable token amount depending on price impact, slippage, and MEV
- A withdrawal from a lending vault returns a variable share-to-asset conversion
- A bridge delivers tokens after an unpredictable delay with variable fees
- A liquidation or rebalance depends on state that changes block-to-block

Static batching forces two bad choices: hardcode optimistic amounts (risking reverts) or underestimate conservatively (leaving value stranded). Both degrade UX and capital efficiency.

**Static batching vs smart batching:**

```
STATIC BATCHING (current model)
═══════════════════════════════════════════════════════════════════

 Signature time                          Execution time
 ─────────────                           ──────────────
 All values frozen at signing:           Values may be stale:

 ┌──────────────────────────┐            ┌──────────────────────────┐
 │ Step 1: swap(100 USDC)   │──────────► │ swap(100 USDC)           │ ✓ OK
 ├──────────────────────────┤            ├──────────────────────────┤
 │ Step 2: supply(0.05 WETH)  │──────────► │ supply(0.05 WETH)          │ ✗ REVERT
 │  (guessed swap output)   │            │  (actual output was 0.0495)  │
 └──────────────────────────┘            └──────────────────────────┘

 Problem: amount "0.05" was a guess at signature time.
 If the swap returns <0.05, step 2 reverts — entire batch fails.


SMART BATCHING (this standard)
═══════════════════════════════════════════════════════════════════

 Signature time                          Execution time
 ─────────────                           ──────────────
 Parameters specify HOW to resolve:      Values resolved on-chain:

 ┌──────────────────────────┐            ┌──────────────────────────┐
 │ Step 1: swap(100 USDC)   │──────────► │ swap(100 USDC)           │
 │  output → Storage[slot0] │            │  returns 0.0495 → Storage    │
 ├──────────────────────────┤            ├──────────────────────────┤
 │ Step 2: supply(amount)   │            │ supply(0.0495 WETH)          │ ✓ OK
 │  amount = STATIC_CALL    │──────────► │  read Storage[slot0] = 0.0495
 │          → Storage.read  │            │  constraint: GTE(1) ✓    │
 │  constraint: GTE(1)      │            └──────────────────────────┘
 └──────────────────────────┘

 Each parameter declares its resolution strategy:
  ┌─────────────┐
  │  RAW_BYTES   │──► Literal value (known at signing)
  ├─────────────┤
  │ STATIC_CALL  │──► Read on-chain state (balance, Storage, oracle...)
  ├─────────────┤
  │  BALANCE     │──► Query ERC-20 or native balance
  └─────────────┘

 And each parameter declares where it is routed:
  TARGET ──► call target address
  VALUE  ──► ETH value to forward
  CALL_DATA ──► appended to calldata
```

### Runtime Resolution

Smart batching resolves parameters at execution time. Instead of pre-encoding a static calldata blob, the user signs a batch where each parameter specifies *how to obtain its value* — as a literal, a `staticcall`, or a balance query. The execution logic resolves each parameter and **constructs the calldata from scratch** during the transaction, eliminating the entire class of failures caused by stale data.

The calldata-construction design is deliberate: rather than patching pre-encoded calldata at sentinel offsets, the system builds each call from individually resolved parameters. This avoids offset arithmetic, keeps encoding simple, and lets each parameter independently specify its resolution strategy and constraints.

### Emergent Predicates and Cross-Chain Orchestration

Each resolved value can carry inline constraints — on-chain assertions that must hold or the batch reverts. Within a single transaction, constraints validate dynamically resolved values. But because the execution algorithm resolves and validates *before* making the call, an entry with no call target (`address(0)`) becomes a pure boolean gate on chain state — a **predicate entry**. No separate mechanism required.

Predicate entries enable **execution ordering without explicit sequencing.** Each batch executes only when its predicates are satisfied. Step B observes the *state change* that A produces — not a sequence number. Bridges from multiple sources complete in any order; the predicate waits for the aggregate state.

> **Note on Merkle tree encoding:** The Merkle-tree authorization structure is defined by a **separate ERC**. This ERC defines the smart batch encoding and constraint mechanism that operate *within* each Merkle leaf. The two standards compose: the Merkle tree ERC handles authorization ("is this call allowed?"), while this ERC handles execution ("how is this call constructed and validated?").

```
MULTI-CHAIN ORCHESTRATION VIA MERKLE TREE + PREDICATE ENTRIES
═══════════════════════════════════════════════════════════════════

 User signs ONE Merkle root covering all operations:

                        ┌──────────┐
                        │  Root    │◄── user signature
                        │ 0xab3f.. │
                        └────┬─────┘
                   ┌─────────┴─────────┐
              ┌────┴────┐         ┌────┴────┐
              │ H(A,B)  │         │ H(C,D)  │
              └────┬────┘         └────┬────┘
            ┌──────┴──────┐     ┌──────┴──────┐
         ┌──┴──┐       ┌──┴──┐ ┌──┴──┐    ┌──┴──┐
         │  A  │       │  B  │ │  C  │    │  D  │
         └──┬──┘       └──┬──┘ └──┬──┘    └──┬──┘
            │              │      │           │
            ▼              ▼      ▼           ▼

  ┌─────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
  │ ETHEREUM L1 │ │  OPTIMISM    │ │  ARBITRUM    │ │  BASE        │
  ├─────────────┤ ├──────────────┤ ├──────────────┤ ├──────────────┤
  │ A: Bridge   │ │ B: Composable│ │ C: Composable│ │ D: Composable│
  │ 100 USDC    │ │ batch:       │ │ batch:       │ │ batch:       │
  │ to Optimism │ │  swap → lend │ │  claim → LP  │ │  unwrap→send │
  │             │ │              │ │              │ │              │
  │ Predicate   │ │ Predicate    │ │ Predicate    │ │ Predicate    │
  │ entry:      │ │ entry:       │ │ entry:       │ │ entry:       │
  │ (none—first │ │ BALANCE ≥100 │ │ STATIC_CALL  │ │ STATIC_CALL  │
  │  step)      │ │ (USDC on OP) │ │ nonce > N    │ │ timestamp >T │
  └─────────────┘ │              │ │              │ │              │
                  └──────────────┘ └──────────────┘ └──────────────┘

  Execution flow (asynchronous, constraint-gated):

  Time ──────────────────────────────────────────────────────────►

  t=0: Relayer submits A (no predicate entry — executes immediately)
       Bridge 100 USDC from L1 to Optimism

  t=?: Relayer simulates batch B (eth_call):
       Predicate entry: BALANCE(USDC, account) with GTE(100e6)
       Bridge completes... constraint satisfied ✓
       Relayer submits B: composable batch (swap → lend)

  t=?: Relayer simulates batch C (eth_call):
       Predicate entry: STATIC_CALL(entryPoint.getNonce()) with GTE(N)
       Prior tx confirms... constraint satisfied ✓
       Relayer submits C: composable batch (claim → LP)

  t=?: Relayer simulates batch D (eth_call):
       Predicate entry: STATIC_CALL(block.timestamp helper) with GTE(T)
       Time passes... constraint satisfied ✓
       Relayer submits D: composable batch (unwrap → send)

  ─────────────────────────────────────────────────────────────

  Key property: constraints observe STATE, not mechanism.
  The bridge in step A could be any provider — native bridge,
  Across, ERC-7683, LayerZero — the constraint doesn't care.
  It just waits for the balance to appear.
```

Because predicates observe *state* — not mechanism — orchestration is agnostic to the interoperability layer. Whether tokens arrive via a native rollup bridge, an intent-based system (ERC-7683), or a message-passing protocol (ERC-7786), the predicate only observes the resulting state change (e.g., balance ≥ threshold). The predicate model is **credibly neutral** with respect to the interoperability layer: any bridge, messaging protocol, or relayer network works if it produces the expected state change.

### From Transactions to Programs

Consider a common DeFi workflow: swap tokens, supply to a lending market, stake the receipt. Building this as a one-click experience today means deploying a custom smart contract — with testing, auditing, and redeployment for every change across every chain. Smart batching reduces this to a client-side script:

```typescript
const batch = smartBatch([
  swap({ from: WETH, to: USDC, amount: fullBalance() }),
  predicate({ balance: gte(USDC, account, 2500e6) }),
  supply({ protocol: "aave", token: USDC, amount: fullBalance() }),
  stake({ token: aUSDC, amount: fullBalance() }),
]);
```

The SDK compiles this into `ComposableExecution` entries with fetchers, constraints, and storage instructions. The user signs once. Relayers execute on-chain. In multi-chain environments, the same model extends naturally — a cross-chain yield flow is a single signed program with predicate entries gating each step, authorized by one signature over a Merkle root.

This is the paradigm shift: **from transactions to programs**. Smart batching gives developers a programmable, verifiable execution environment — with runtime variables, on-chain assertions, state passing, and cross-chain control flow — that runs entirely on the EVM.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- **Composable batch** (smart batch): An ordered array of `ComposableExecution` entries where each entry's call target, value, and calldata are constructed from individually resolved parameters with inline constraints on resolved values, and return data MAY be captured for use by subsequent entries.
- **Input parameter**: A single value contributing to a call's target, value, or calldata. Each input parameter specifies how to obtain its value (fetcher type) and where to route it (param type).
- **Fetcher type**: The strategy for resolving an input parameter's value at execution time — literal bytes, an arbitrary `staticcall`, or a balance query.
- **Storage contract**: A dedicated external contract that provides namespaced key-value storage for captured return values. Values are written by output parameters and read back by subsequent input parameters via `staticcall`.
- **Constraint**: An inline predicate — a pure boolean condition attached to a specific input parameter within a composable batch entry. If the constraint fails, the batch MUST revert.
- **Predicate entry**: A `ComposableExecution` entry with no `TARGET` input parameter (target defaults to `address(0)`) whose sole purpose is to resolve on-chain state via input parameter fetchers and validate constraints. No call is executed; the entry acts as a boolean gate on the rest of the batch.

### Overview

This standard defines three layers:

1. **Encoding schemes** — The wire format for composable batches, runtime value sources, and constraints. This is the core of the standard. Any two conforming implementations MUST produce and consume identical encodings.
2. **Interfaces** — The Solidity interface (`IComposableExecution`) that any contract can implement. This is account-standard-agnostic.
3. **Execution semantics** — The normative algorithm that all implementations MUST follow when processing a composable batch.

How these are surfaced to a smart account is an implementation choice, not part of this standard:

- An **ERC-7579** implementation wraps the interface as an executor module.
- An **ERC-6900** implementation wraps it as an execution function / plugin.
- A **native account** inherits the interface directly.
- An **ERC-7702** delegated EOA can delegate to an implementation contract.

All of these consume the same encoding and follow the same execution semantics.

```
┌─────────────────────────────────────────────────┐
│  Application / SDK Layer                        │
│  Encodes ComposableExecution[] with fetcher     │
│  types, param types, and constraints            │
└──────────────────┬──────────────────────────────┘
                   │ standardized encoding
                   ▼
┌─────────────────────────────────────────────────┐
│  Account-Standard Adapter                       │
│  ERC-7579 module │ ERC-6900 plugin │ native     │
│  (thin wrapper — delegates to core logic)       │
└──────────────────┬──────────────────────────────┘
                   │ for each step:
                   ▼
┌─────────────────────────────────────────────────┐
│  Core Execution Logic (shared)                  │
│  1. processInputs() — resolve & build calldata  │
│  2. Execute the call                            │
│  3. processOutputs() — capture to Storage       │
└─────────────────────────────────────────────────┘
```

---

### Composable Batch Encoding

#### Execution Entry

Each step in a composable batch is encoded as a `ComposableExecution` struct:

```solidity
struct ComposableExecution {
    bytes4 functionSig;            // Function selector for the target call
    InputParam[] inputParams;      // Parameters — each resolves and routes a value
    OutputParam[] outputParams;    // Return value capture instructions
}
```

A `ComposableExecution` does not contain a pre-encoded `target`, `value`, or `callData`. Instead, the call target, ETH value, and calldata are **constructed at execution time** from the resolved input parameters. The `functionSig` provides the 4-byte function selector; the rest of the calldata is built by concatenating each resolved `CALL_DATA` input parameter in order.

Implementations MUST process the batch as an ordered array of `ComposableExecution` entries. Entries MUST be executed sequentially — parallel or out-of-order execution is not permitted, since later entries MAY depend on captured outputs from earlier ones.

#### Input Parameters

Each input parameter specifies two orthogonal concerns: **where the value goes** (`paramType`) and **how the value is obtained** (`fetcherType`):

```solidity
struct InputParam {
    InputParamType paramType;           // Where this value is routed
    InputParamFetcherType fetcherType;  // How this value is obtained
    bytes paramData;                    // Fetcher-specific data
    Constraint[] constraints;           // Conditions the resolved value MUST satisfy
}
```

##### Input Parameter Type — Value Routing

```solidity
enum InputParamType {
    TARGET,     // The resolved value is used as the call target address
    VALUE,      // The resolved value is used as the ETH value to forward
    CALL_DATA   // The resolved value is appended to the calldata being built
}
```

- `TARGET`: The resolved bytes are decoded as an `address` and used as the call target. At most one input parameter per entry MAY have this type. If no `TARGET` parameter is provided, the target defaults to `address(0)`.
- `VALUE`: The resolved bytes are decoded as a `uint256` and used as the ETH value. At most one input parameter per entry MAY have this type. If no `VALUE` parameter is provided, the value defaults to `0`.
- `CALL_DATA`: The resolved bytes are appended (in order) to the calldata being constructed after the function selector. Multiple `CALL_DATA` parameters are concatenated sequentially.

##### Input Parameter Fetcher Type — Value Resolution

```solidity
enum InputParamFetcherType {
    RAW_BYTES,      // Literal value — use paramData directly
    STATIC_CALL,    // Resolve via an arbitrary staticcall
    BALANCE         // Resolve via a token or native balance query
}
```

**`RAW_BYTES`** — The `paramData` is used as-is as the resolved value. This is for parameters whose values are known at encoding time (static amounts, known addresses, pre-computed hashes).

**`STATIC_CALL`** — Performs an arbitrary `staticcall` and uses the return data as the resolved value.

```solidity
// paramData encoding:
// abi.encode(address contractAddr, bytes callData)
```

The implementation MUST execute `staticcall` to `contractAddr` with the provided `callData`. The return data is used as the resolved value. If the `staticcall` reverts, the implementation MUST revert.

This is the general-purpose fetcher. It handles any on-chain state read: ERC-20 allowances, oracle prices, storage reads, and — critically — reading previously captured values back from the Storage contract (see Output Parameters below).

**`BALANCE`** — Queries the balance of an address. Handles both ERC-20 tokens and native ETH via a sentinel address convention.

```solidity
// paramData encoding:
// abi.encodePacked(address token, address account)  // exactly 40 bytes
```

If `token == address(0)`, the implementation MUST use `account.balance` (native ETH balance). Otherwise, the implementation MUST execute `IERC20(token).balanceOf(account)` via `staticcall`. The result is ABI-encoded as `uint256`.

The `paramData` MUST be exactly 40 bytes (`abi.encodePacked` of two addresses). Implementations MUST revert if the length does not match.

The `BALANCE` fetcher type MUST NOT be used with `InputParamType.TARGET` (a balance cannot be a call target address).

After resolution, all constraints attached to the input parameter MUST be validated against the resolved value before it is routed to its destination.

#### Output Parameters — Return Value Capture

After a call completes, the system MAY capture values from the return data and write them to an external **Storage contract** for use by later entries:

```solidity
struct OutputParam {
    OutputParamFetcherType fetcherType;  // Source of the data to capture
    bytes paramData;                     // Fetcher-specific capture instructions
}
```

##### Output Parameter Fetcher Type

```solidity
enum OutputParamFetcherType {
    EXEC_RESULT,    // Capture from the return data of the just-executed call
    STATIC_CALL     // Capture from a separate staticcall (post-execution state read)
}
```

**`EXEC_RESULT`** — Captures values directly from the return data of the call that just executed.

```solidity
// paramData encoding (packed):
// abi.encode(uint256 returnValueCount, address storageContract, bytes32 storageSlot)
```

- `returnValueCount`: The number of consecutive 32-byte words to capture from the return data, starting at offset 0.
- `storageContract`: The address of the Storage contract to write captured values to.
- `storageSlot`: The base storage slot. Each captured word `i` (where `i` is a `uint256` index starting at 0) is written to `keccak256(abi.encodePacked(storageSlot, uint256(i)))`. The index MUST be encoded as `uint256` for consistent slot derivation across implementations.

**`STATIC_CALL`** — Makes a separate `staticcall` after execution and captures from its return data. This is useful for reading state that changed as a result of the call (e.g., a new balance after a swap).

```solidity
// paramData encoding:
// abi.encode(uint256 returnValueCount, address sourceContract, bytes sourceCallData,
//            address storageContract, bytes32 storageSlot)
```

The implementation MUST execute `staticcall` to `sourceContract` with `sourceCallData`, then capture `returnValueCount` consecutive 32-byte words from the return data and write them to the Storage contract at the derived slots. If the `staticcall` reverts, the implementation MUST revert.

---

### Storage Contract

Captured return values are persisted in a dedicated **Storage contract** — a separate on-chain contract that provides namespaced key-value storage. This is NOT inline storage within the execution module or account; it is an external contract that any entry in the batch can write to and any subsequent entry can read from (via a `STATIC_CALL` fetcher).

#### Interface

```solidity
contract Storage {
    function writeStorage(bytes32 slot, bytes32 value, address account) external;
    function readStorage(bytes32 namespace, bytes32 slot) external view returns (bytes32);
    function getNamespace(address account, address caller) public pure returns (bytes32);
    function getNamespacedSlot(bytes32 namespace, bytes32 slot) public pure returns (bytes32);
    function isSlotInitialized(bytes32 namespace, bytes32 slot) external view returns (bool);
}
```

**Namespace derivation:** Each `(account, caller)` pair maps to a unique namespace:

```solidity
namespace = keccak256(abi.encodePacked(account, caller))
```

**Slot derivation:** Each logical slot is further namespaced:

```solidity
namespacedSlot = keccak256(abi.encodePacked(namespace, slot))
```

The `writeStorage` function derives the namespace from `(account, msg.sender)`, so the caller identity is implicit. The `readStorage` function takes an explicit namespace, allowing any contract to read from any namespace.

**Initialized tracking:** The Storage contract tracks which slots have been written. Reading an uninitialized slot MUST revert (`SlotNotInitialized`). This prevents stale data from prior executions from leaking into the current batch.

**Ephemeral storage variant:** Because captured values only need to persist within a single transaction, the Storage contract MAY be implemented using EIP-1153 transient storage (`TSTORE`/`TLOAD`) instead of persistent storage (`SSTORE`/`SLOAD`). This has two benefits: (1) transient storage is significantly cheaper — no cold/warm SSTORE costs, no refund accounting — reducing gas overhead for composable batches that capture and pass many values, and (2) transient storage automatically clears at the end of the transaction, eliminating the need for initialized-slot tracking and removing any risk of stale data leaking between transactions. The external interface (`writeStorage`/`readStorage`) remains identical; only the internal storage mechanism changes. Implementations SHOULD prefer the transient storage variant on chains where EIP-1153 is available.

#### How Captured Values Flow Between Steps

1. Step N executes, producing return data.
2. An `EXEC_RESULT` output parameter captures words from the return data and writes them to the Storage contract at `keccak256(abi.encodePacked(storageSlot, uint256(i)))` for each word index `i`.
3. Step N+1 has an input parameter with `fetcherType = STATIC_CALL` that calls `Storage.readStorage(namespace, slot)` to read back the captured value.
4. The resolved value is routed to the appropriate destination (`TARGET`, `VALUE`, or `CALL_DATA`).

This design means captured value passing is not a special built-in mechanism — it composes through the same `STATIC_CALL` fetcher used for any on-chain state read.

#### Preferred Pattern: Stateless Reads Over Captured Storage

While the Storage contract enables passing return values between steps, the **preferred pattern** is to avoid storing and retrieving values entirely. Instead, subsequent steps SHOULD read the result of a prior step's side effects directly via getter functions on the affected contracts.

For example, after a swap, the account's token balance changes. Rather than capturing the swap's return value into Storage and reading it back, the next step can simply use a `BALANCE` fetcher (or a `STATIC_CALL` to `balanceOf`) to read the account's current balance of the received token. The balance already reflects the swap's output — there is nothing to store.

```
PREFERRED — stateless read via getter:
  Step 1: swap(100 USDC → WETH)
  Step 2: supply(amount)
           amount = BALANCE(WETH, account)   ← reads current balance directly

ALTERNATIVE — capture and retrieve via Storage:
  Step 1: swap(100 USDC → WETH)
           output → Storage[slot0]            ← extra SSTORE
  Step 2: supply(amount)
           amount = STATIC_CALL(Storage.read) ← extra SLOAD + cross-contract call
```

The stateless-read pattern is more gas-efficient (no Storage writes or reads), simpler to encode (no storage slot coordination), and more robust (no risk of stale or uninitialized slots). It works whenever the prior step produces an observable state change that a getter can reflect — which covers the vast majority of DeFi operations (swaps, deposits, withdrawals, approvals).

The Storage-based capture pattern remains necessary when:
- The prior step's return value is the only way to obtain the data (no getter exists for the resulting state).
- Multiple values from a single return must be disaggregated (e.g., a function returning `(uint256 amountA, uint256 amountB)`).
- The value needed is not a balance or allowance but an intermediate computation only available in the return data.

SDK implementers SHOULD default to stateless getter reads and only fall back to Storage-based capture when no getter can express the needed value.

---

### Inline Constraints

Constraints are predicates attached to individual input parameters within a composable batch. They validate the resolved value before it is routed:

```solidity
struct Constraint {
    ConstraintType constraintType;
    bytes referenceData;
}

enum ConstraintType {
    EQ,     // value == referenceData (as bytes32)
    GTE,    // value >= referenceData (as bytes32)
    LTE,    // value <= referenceData (as bytes32)
    IN      // lowerBound <= value <= upperBound
}
```

- `EQ`: The resolved value (as `bytes32`) MUST equal `bytes32(referenceData)`.
- `GTE`: The resolved value (as `bytes32`) MUST be greater than or equal to `bytes32(referenceData)`.
- `LTE`: The resolved value (as `bytes32`) MUST be less than or equal to `bytes32(referenceData)`.
- `IN`: The `referenceData` MUST be `abi.encode(bytes32 lowerBound, bytes32 upperBound)`. The resolved value MUST satisfy `lowerBound <= value <= upperBound`.

Constraints operate on `bytes32` comparisons, which naturally handle `uint256`, `address`, and other 32-byte types via their left-padded representations.

Implementations MUST evaluate all constraints on each input parameter against its resolved value. If any constraint fails, the implementation MUST revert the entire batch.

#### Predicate Entries — General-Purpose Predicates via Constraints

A **predicate entry** is a `ComposableExecution` entry that performs no call — it exists solely to check on-chain conditions. Because the execution algorithm skips the call when `target == address(0)` (the default when no `TARGET` input parameter is provided), but still resolves all input parameters and validates their constraints, any entry without a `TARGET` parameter acts as a pure boolean gate.

A predicate entry:

- MUST have no `TARGET` input parameter (target defaults to `address(0)`, call is skipped).
- MUST have one or more `CALL_DATA` input parameters using `STATIC_CALL` or `BALANCE` fetcher types, each carrying `Constraint[]` that define the conditions.
- SHOULD have empty `outputParams` (no values to capture from a skipped call).
- MAY use `bytes4(0)` as `functionSig` (the selector is irrelevant since no call is made).

Multiple input parameters on a single predicate entry are implicitly AND-composed — all constraints on all parameters must pass for the entry to succeed. Multiple predicate entries in the same batch provide sequential AND gates.

**Example — balance predicate entry:**

```solidity
ComposableExecution({
    functionSig: bytes4(0),
    inputParams: [InputParam({
        paramType: InputParamType.CALL_DATA,
        fetcherType: InputParamFetcherType.BALANCE,
        paramData: abi.encodePacked(USDC_ADDRESS, ACCOUNT_ADDRESS),
        constraints: [Constraint({
            constraintType: ConstraintType.GTE,
            referenceData: abi.encode(100e6)
        })]
    })],
    outputParams: []
})
```

This entry resolves the account's USDC balance and asserts it is at least 100 USDC. If the constraint fails, the entire batch reverts. No call is executed.

**Example — timestamp predicate entry (via STATIC_CALL):**

```solidity
ComposableExecution({
    functionSig: bytes4(0),
    inputParams: [InputParam({
        paramType: InputParamType.CALL_DATA,
        fetcherType: InputParamFetcherType.STATIC_CALL,
        paramData: abi.encode(TIMESTAMP_HELPER, abi.encodeCall(ITimestamp.getTimestamp, ())),
        constraints: [Constraint({
            constraintType: ConstraintType.GTE,
            referenceData: abi.encode(TARGET_TIMESTAMP)
        })]
    })],
    outputParams: []
})
```

Any on-chain state readable via `staticcall` can serve as a predicate condition — nonces, oracle prices, storage slots, timestamps — all through the same constraint mechanism.

#### Constraints in Orchestration Context

In a multi-chain orchestration context, constraints serve a dual purpose:

1. **Validation** — ensuring injected values meet safety criteria (e.g., balance is non-zero, amount is above a minimum).
2. **Execution gating** — predicate entries at the start of a batch gate the entire batch on on-chain conditions. Relayers simulate the batch via `eth_call`; if any predicate entry's constraints fail, the simulation reverts and the relayer waits. When simulation succeeds, the relayer submits the transaction. This naturally gates cross-chain flows — for example, a `GTE` constraint on a bridged token balance causes the relayer to wait until the bridge completes before proceeding.

Because predicate entries use the same `ComposableExecution` encoding, `InputParam` fetcher types, and `Constraint` validation as any other batch entry, no additional contracts or interfaces are required. The entire predicate mechanism is a usage pattern of the existing composable execution primitives.

---

### Composable Execution Algorithm

The execution algorithm for a composable batch is as follows. This is normative — implementations MUST follow this sequence:

```
function executeComposable(ComposableExecution[] entries):
    for i = 0 to entries.length - 1:
        entry = entries[i]
        target = address(0)
        value = 0
        calldata = entry.functionSig    // start with 4-byte selector

        // Step 1: Process input parameters — resolve and route each value
        for each inputParam in entry.inputParams:

            // Step 1a: Resolve the value via the fetcher
            if inputParam.fetcherType == RAW_BYTES:
                resolvedValue = inputParam.paramData
            else if inputParam.fetcherType == STATIC_CALL:
                (contractAddr, callData) = decode(inputParam.paramData)
                resolvedValue = staticcall(contractAddr, callData)
            else if inputParam.fetcherType == BALANCE:
                (token, account) = decodePacked(inputParam.paramData)
                if token == address(0):
                    resolvedValue = abi.encode(account.balance)
                else:
                    resolvedValue = abi.encode(IERC20(token).balanceOf(account))

            // Step 1b: Validate constraints
            for each constraint in inputParam.constraints:
                if not evaluateConstraint(constraint, resolvedValue):
                    REVERT

            // Step 1c: Route to destination
            if inputParam.paramType == TARGET:
                target = address(resolvedValue)
            else if inputParam.paramType == VALUE:
                value = uint256(resolvedValue)
            else if inputParam.paramType == CALL_DATA:
                calldata = concat(calldata, resolvedValue)

        // Step 2: Execute the call
        if target != address(0):
            (success, returnData) = target.call{value: value}(calldata)
            if not success:
                REVERT with returnData
        else:
            returnData = empty

        // Step 3: Process output parameters — capture to Storage
        for each outputParam in entry.outputParams:
            if outputParam.fetcherType == EXEC_RESULT:
                writeToStorage(returnData, outputParam.paramData)
            else if outputParam.fetcherType == STATIC_CALL:
                externalData = staticcall(sourceContract, sourceCallData)
                writeToStorage(externalData, outputParam.paramData)
```

The `writeToStorage` step parses `returnValueCount` consecutive 32-byte words from the data and writes each to the Storage contract at `keccak256(abi.encodePacked(storageSlot, uint256(i)))` (where `i` is the zero-based word index as `uint256`), namespaced by `(account, caller)`.

#### Error Handling

- If any `staticcall` for value resolution (input or output) fails, the implementation MUST revert the entire batch.
- If any constraint evaluates to false, the implementation MUST revert the entire batch.
- If any call in the batch reverts, the implementation MUST revert the entire batch (atomic execution).
- If an entry specifies `target == address(0)` (no `TARGET` input param provided), the call MUST be skipped but output parameters MUST still be processed. This allows entries that only perform state reads and storage writes without executing a call.
- `TARGET` and `VALUE` param types MUST each appear at most once per entry. Duplicates MUST cause a revert.
- The `BALANCE` fetcher type MUST NOT be used with `InputParamType.TARGET`.

---

### Storage Model for Captured Values

Captured values are persisted in a dedicated, external **Storage contract** rather than in inline storage within the execution module or account. This design provides:

1. **Per-account isolation** — the Storage contract derives a unique namespace from `(account, caller)`, so values captured by one account's batch are not readable by another account unless the namespace is explicitly provided.
2. **Initialized tracking** — the Storage contract tracks which slots have been written. Reading an uninitialized slot reverts, preventing stale data from a prior transaction from being mistaken for a current captured value.
3. **Decoupled storage** — the Storage contract is independent of the execution adapter. The same Storage contract instance can be shared across ERC-7579 modules, ERC-6900 plugins, and native account integrations.

#### Namespace Derivation

The namespace for a given execution context is:

```solidity
namespace = keccak256(abi.encodePacked(account, caller))
```

When the execution module calls `writeStorage(slot, value, account)`, the Storage contract computes the namespace using `(account, msg.sender)`. This means:

- Different accounts naturally get different namespaces.
- The same account calling through different adapters (or via `call` vs `delegatecall`) gets different namespaces, because `msg.sender` differs.

#### Call vs Delegatecall Context

When the composable execution adapter is invoked via `delegatecall`, `msg.sender` in the Storage contract's perspective is the *account's caller* (e.g., the EntryPoint), and `address(this)` within the adapter is the account itself. When invoked via `call`, `msg.sender` is the account, and `address(this)` is the adapter.

Because the namespace includes `msg.sender`, these two contexts produce different namespaces. It is RECOMMENDED that a smart account consistently uses either `call` or `delegatecall` for its composable execution adapter, not both. Values written via one context are not readable via the other.

This concern does not apply to native account integrations, where the composable execution logic runs directly in the account's own context.

#### Transient Storage Optimization

Since captured values only need to persist within a single transaction, implementations MAY use EIP-1153 transient storage (`TSTORE`/`TLOAD`) within the Storage contract for captured slots. This avoids the gas cost of `SSTORE`/`SLOAD` and automatically clears at transaction end.

---

### Core Interface

This standard defines a single, account-standard-agnostic interface that all conforming implementations MUST expose:

```solidity
interface IComposableExecution {
    /// @notice Executes a composable batch.
    /// @param executions The ordered array of composable execution entries,
    ///        encoded per the Composable Batch Encoding section of this standard.
    function executeComposable(ComposableExecution[] calldata executions) external payable;
}
```

Implementations MUST accept and correctly forward `msg.value` through the execution flow to entries that specify non-zero ETH values. Implementations MUST follow the Composable Execution Algorithm defined in this standard.

The `IComposableExecution` interface uses a fixed function selector (`executeComposable(ComposableExecution[])`) so that SDKs, relayers, and tooling can identify and interact with any conforming implementation regardless of how it is installed on the account.

---

### Adapter Guidelines

The core interface and encoding are designed to be wrapped by any modular account standard. This section provides non-normative guidance for adapter implementors.

#### ERC-7579 Adapter

An ERC-7579 adapter wraps `IComposableExecution` as an executor module. The adapter:

- Installs via the standard ERC-7579 module lifecycle (`onInstall`, `onUninstall`).
- MUST verify that `msg.sender` is an account that has installed this module.
- MAY be registered as an executor module, a fallback handler module, or both, depending on the account's architecture.
- Delegates all encoding, injection, and capture logic to a shared library implementing the standard algorithm.

#### ERC-6900 Adapter

An ERC-6900 adapter wraps `IComposableExecution` as an execution function within the ERC-6900 plugin architecture. The adapter:

- Registers `executeComposable` as an execution function via the standard ERC-6900 manifest.
- Hooks into the ERC-6900 permission model for authorization (pre-execution hooks, validation functions).
- The composable batch encoding, runtime value resolution, and execution algorithm are identical — only the installation and permission surfaces differ.

#### Native Account Integration

Smart accounts that want composable execution as a first-class feature MAY implement `IComposableExecution` directly, without any module wrapper:

```solidity
contract MySmartAccount is IComposableExecution, ... {
    function executeComposable(ComposableExecution[] calldata executions) external payable {
        ComposableExecutionLib.execute(executions);
    }
}
```

This eliminates cross-contract call overhead. The account inherits the standard interface and delegates to a shared library, so SDKs and tooling interact with it identically to the module-based path.

#### ERC-7702 Delegated EOAs

EOAs using ERC-7702 delegation can delegate to an implementation contract that exposes `IComposableExecution`. The delegated code runs in the EOA's context, providing composable execution without a smart account deployment.

#### Shared Library Pattern

Regardless of adapter type, implementations SHOULD factor all injection, capture, and constraint logic into a shared library. This ensures:

- Identical behavior across all integration surfaces.
- A single audit target for the core algorithm.
- Fixes and improvements propagate to all adapters automatically.

---

### Canonical Encoding Format

The encoding format is the normative core of this standard. All conforming implementations — regardless of account standard — MUST produce and consume this encoding.

The composable batch is ABI-encoded as:

```solidity
abi.encode(ComposableExecution[] executions)
```

Each `ComposableExecution` is ABI-encoded per standard Solidity struct encoding rules. Nested structs (`InputParam`, `OutputParam`, `Constraint`) and enums (`InputParamType`, `InputParamFetcherType`, `OutputParamFetcherType`, `ConstraintType`) follow the same ABI encoding conventions.

There is no pre-encoded calldata in the `ComposableExecution` struct — the `functionSig` and the resolved `CALL_DATA` input parameters are concatenated at execution time to form the calldata. This means the encoding is fully self-describing: each parameter carries its own resolution strategy and routing information.

#### Why Canonical Encoding Matters

A canonical encoding ensures that:

- **SDKs are portable.** An SDK that encodes a composable batch for an ERC-7579 account produces the exact same bytes as one targeting an ERC-6900 account. There is no per-standard encoding variant.
- **Tooling is universal.** Block explorers, transaction simulators, and debuggers decode one format. They do not need to know which account standard the target uses.
- **Relayers are interoperable.** An orchestration relayer submits the same encoded batch to any conforming account. The adapter layer handles account-standard-specific routing; the payload is identical.

---

## Rationale

### Calldata Construction vs Placeholder Patching

Two viable approaches exist for runtime-resolved calldata:

1. **Placeholder patching** — pre-encode the full calldata with sentinel bytes at known offsets, then replace those bytes with resolved values. This requires offset arithmetic and knowledge of the ABI encoding layout.
2. **Calldata construction** — specify each parameter individually with its resolution strategy, then build the calldata from scratch by concatenating the function selector with each resolved parameter.

This standard uses calldata construction (approach 2). It is simpler: each `InputParam` is self-contained (fetcher type + param data + constraints), there are no offsets to compute, and the encoding is independent of the target function's ABI layout. The SDK specifies parameters in order; the on-chain code concatenates them.

### Encoding-First, Not Module-First

This standard defines encoding schemes and interfaces rather than prescribing a specific module standard. The smart account ecosystem has multiple competing modular architectures (ERC-7579, ERC-6900, native implementations, ERC-7702 delegation). Standardizing at the encoding level means:

- **One wire format** — SDKs encode a composable batch once; any conforming account can consume it.
- **One interface** — `IComposableExecution` is the same function signature everywhere. Tooling (block explorers, simulation engines, debuggers) needs to understand one interface, not N module-specific variants.
- **Adapters are thin** — the ERC-7579 adapter, ERC-6900 adapter, and native integration are thin wrappers over the same encoding and algorithm. The wrapper handles installation and permissions; the core logic is shared.

If the standard were defined as "an ERC-7579 module," ERC-6900 accounts would need a translation layer or a parallel standard. By defining the encoding and interface first, both ecosystems implement the same standard natively.

### Shared Library Architecture

All composable execution logic SHOULD live in a shared library, with adapters being thin wrappers. This keeps the logic DRY — fixes and improvements propagate to all integration surfaces automatically. It also reduces audit surface, since the core algorithm only exists in one place.

### Static Types for Calldata Parameters

The calldata construction model concatenates each resolved `CALL_DATA` parameter in order. Each parameter is expected to be an ABI-encoded 32-byte word (a static Solidity type: `uint256`, `address`, `bytes32`, `bool`, etc.). Dynamic types (`bytes`, `string`, dynamic arrays) can be passed via `RAW_BYTES` fetcher (literal values known at encoding time) but cannot be resolved at runtime via `STATIC_CALL` or `BALANCE`, since those fetchers return raw bytes that are concatenated directly.

### Constraints as the Unified Predicate Mechanism

Rather than introducing a separate `IPredicate` interface and standalone predicate contracts, this standard uses the existing constraint mechanism on input parameters as the sole predicate primitive. This unified approach has several advantages:

- **No additional contracts.** Predicate logic is already implemented in `ComposableExecutionLib._validateConstraints`. No separate deployment, no separate audit surface, no separate interface.
- **One encoding format.** Predicates are expressed using the same `ComposableExecution` encoding as every other batch entry. SDKs, relayers, and block explorers parse one format.
- **Composability through the fetcher system.** The `STATIC_CALL` fetcher can call any view function on any contract — balance queries, nonce checks, oracle reads, storage slot reads, timestamp helpers — making constraints arbitrarily expressive without enumerating predicate types.
- **Simulation-based gating.** Relayers gate orchestration flows by simulating the batch via `eth_call`. If a predicate entry's constraints fail, the simulation reverts. This is functionally equivalent to a boolean `evaluate()` call, but requires no additional on-chain infrastructure.

The predicate entry pattern (a `ComposableExecution` with `target == address(0)`) collapses the distinction between intra-transaction validation and inter-transaction gating into one mechanism:

- **Intra-transaction:** constraints on parameters of entries that execute calls — "the value I'm about to inject meets my safety criteria."
- **Inter-transaction:** constraints on predicate entries at the start of a batch — "the chain state resulting from a prior transaction has materialized." Relayers simulate the batch and wait until the constraints pass.

### STATIC_CALL as the Universal Fetcher

The `STATIC_CALL` fetcher type is intentionally general-purpose. Rather than defining a separate fetcher for every on-chain state read (allowances, oracle prices, nonces, etc.), the standard provides one fetcher that can call any contract with any calldata. The `BALANCE` fetcher exists as a convenience optimization for the most common case (token/native balance queries), but any state read expressible as a `staticcall` is supported without extending the standard.

This also means captured value passing is not a special mechanism — reading a value captured by a prior step is just a `STATIC_CALL` to the Storage contract's `readStorage` function.

## Backwards Compatibility

This proposal is fully backwards compatible with the existing smart account ecosystem. Because the standard is defined at the encoding and interface level, it does not impose requirements on any specific account architecture:

- **ERC-4337 Smart Accounts**: Smart batching is additive. Existing `UserOperation` flows are unchanged. A conforming adapter is installed alongside existing modules and does not interfere with standard `executeBatch` operations.
- **ERC-7579 Accounts**: The `IComposableExecution` interface is wrapped as a standard ERC-7579 executor module. It installs, configures, and uninstalls through the standard ERC-7579 module lifecycle. It works with any ERC-7579 account without modifications to the account itself.
- **ERC-6900 Accounts**: The `IComposableExecution` interface is wrapped as an ERC-6900 execution function. The composable batch encoding and execution algorithm are identical to the ERC-7579 adapter — only the installation manifest and permission hooks differ.
- **EIP-5792 (`wallet_sendCalls`)**: Smart batching MAY be exposed as an extension to EIP-5792's `wallet_sendCalls` interface, adding parameter resolution capabilities alongside the existing static call array. The `capabilities` field in EIP-5792 provides a natural extension point for advertising smart batching support.
- **ERC-7702**: Delegated EOAs can delegate to an implementation contract that directly exposes `IComposableExecution`, gaining composable execution without a smart account deployment.

No existing smart account requires migration. The encoding format is self-contained and the `IComposableExecution` interface is a single function — adapters for any account standard are minimal.

### Forward Compatibility with EIP-8141 Frame Transactions

Smart Batching is transport-agnostic. Today it executes via ERC-4337 UserOps or EIP-7702 delegation. When EIP-8141 frame transactions ship, the same `ComposableExecution[]` encoding executes within `SENDER` frames — gaining protocol-native inclusion, censorship resistance, and gas abstraction without changes to the encoding or execution semantics. Frame-level gas isolation additionally enables non-atomic multi-batch flows where individual smart batches can fail independently.

### Interoperability Layer Neutrality (ERC-7683, ERC-7786)

Smart Batching predicates are agnostic to the cross-chain mechanism. Whether tokens arrive via a native rollup bridge, an intent-based system (ERC-7683), or a message-passing protocol (ERC-7786), the predicate only observes the resulting state change (e.g., balance ≥ threshold). This is deliberate: the predicate model is credibly neutral with respect to the interoperability layer. No changes to the encoding, constraint evaluation, or execution semantics are needed to accommodate new or alternative bridging and messaging protocols.

## Reference Implementation

A reference implementation accompanies this proposal, structured to demonstrate the encoding-first design:

**Core (account-standard-agnostic):**

1. **`IComposableExecution.sol`** — The standard interface (`executeComposable` and the module-specific `executeComposableCall` / `executeComposableDelegateCall` variants).
2. **`ComposabilityDataTypes.sol`** — All structs and enums (`ComposableExecution`, `InputParam`, `OutputParam`, `Constraint`, `InputParamType`, `InputParamFetcherType`, `OutputParamFetcherType`, `ConstraintType`).
3. **`ComposableExecutionLib.sol`** — The shared library implementing `processInputs()` and `processOutputs()` with the full resolution algorithm, all fetcher types, and constraint evaluation. This is the heart of the standard — any adapter delegates to this library. Constraint validation within `processInputs` provides the inline predicate mechanism.
4. **`Storage.sol`** — The external Storage contract providing namespaced key-value storage with per-account, per-caller isolation and initialized-slot tracking.

**Adapters (demonstrating portability):**

5. **`ComposableExecutionModule.sol`** — An ERC-7579 executor and fallback module adapter wrapping the library.
6. **`ComposableExecutionBase.sol`** — An abstract base contract for native account integration.

Both adapters delegate to the same `ComposableExecutionLib`, demonstrating that the encoding and execution semantics are identical regardless of the account standard.

> **Note on reference implementation dependencies:** The current reference implementation uses the ERC-7579 `Execution` struct (imported from `IERC7579Account`) as an internal convenience type within `ComposableExecutionLib` and the base contract. It also contains implementation-specific constants (signature type identifiers) that are not part of the standard encoding. These are implementation artifacts, not normative requirements — conforming implementations MAY use any internal representation for the `(target, value, callData)` tuple. A future revision of the reference contracts will replace these with standard-local types to remove the ERC-7579 import dependency and implementation-specific constants.

The reference implementation has been audited, with all findings remediated (see Security Considerations).

## Security Considerations

### Storage Isolation Between Accounts

When a composable execution adapter is a separate contract invoked via `call` (not `delegatecall`), multiple accounts share the adapter contract's storage. The storage slot derivation MUST include the account address to prevent cross-account data leakage. A missing or incorrect account address in the derivation would allow one account's captured values to be read or overwritten by another account's batch.

### Call vs Delegatecall Storage Context

This is the most security-critical implementation detail for adapter-based deployments. When invoked via `delegatecall`, the adapter's code executes in the calling account's storage context. When invoked via `call`, it executes in its own storage context. If the storage slot derivation does not account for this distinction, captured values written via one context may be misinterpreted or corrupted when read via the other.

Implementations MUST detect the execution context and derive storage slots accordingly. The recommended approach is to include both the `account` address and the `caller` address (`msg.sender`) in the slot derivation. Under `delegatecall`, `msg.sender` is the account itself; under `call`, `msg.sender` is the account but `address(this)` is the adapter. This asymmetry MUST be handled.

The reference implementation addresses this with a context-detection mechanism that was the subject of a critical audit finding (storage corruption when `delegatecall` was not properly distinguished), resolved prior to release.

This concern does not apply to native account integrations where the composable execution logic runs in the account's own context.

### Native Value Forwarding

Implementations that forward ETH (`msg.value`) through the composable execution flow MUST ensure that:

- The total ETH forwarded across all entries does not exceed the ETH provided to the batch call.
- ETH value injection (via runtime value sources) correctly updates the forwarded amount.
- No ETH is locked in the adapter contract after execution.

Incorrect `msg.value` handling in composable execution has been identified as a security-relevant concern in prior implementations.

### Runtime Value Manipulation

Runtime values (balances, `staticcall` results) are read at execution time and may be subject to manipulation within the same transaction (e.g., via flash loans or sandwich attacks). Constraints partially mitigate this by enforcing bounds on resolved values, but they do not eliminate the risk.

Users and SDK implementers SHOULD:
- Set meaningful constraints on resolved values (e.g., `GTE` with a minimum expected amount).
- Be aware that `balanceOf` and similar calls reflect the account's state at that point in the transaction, which may include flash-loaned tokens.
- Use `GTE` constraints with a non-zero reference value to prevent zero-value resolutions that could cause downstream reverts or economic loss.

### Constraint Evaluation Integrity

Constraints evaluate on-chain state via the input parameter fetcher system (`STATIC_CALL`, `BALANCE`) and are subject to the same trust model as the underlying chain:

- Constraint values reflect state at the time of the `staticcall` or balance query. State may change between simulation and transaction inclusion in a block — a predicate entry that passes during `eth_call` simulation may fail when the transaction is actually executed if state changes in the interim.
- Cross-chain predicate entries (constraints checking state produced by a bridge or cross-chain message) inherit the trust assumptions of the queried chain. The constraint mechanism does not introduce additional trust assumptions.
- All constraint evaluation is read-only (fetchers use `staticcall` or `balance` queries), ensuring no side effects during predicate checking.

### Relayer Trust Model

In orchestration flows, relayers simulate composable batches and submit them when predicate entries' constraints pass. The security model does not require trusting relayers:

- Relayers cannot execute unauthorized instructions — each instruction is verified against a user-signed authorization (e.g., a Merkle root) on-chain.
- Relayers cannot forge constraint results — constraints are evaluated on-chain at execution time within the composable batch, not off-chain. Even if a relayer submits a batch prematurely, the predicate entry's constraints will fail on-chain and the batch will revert.
- A malicious relayer can only withhold execution (liveness failure), not steal funds or execute unauthorized operations. Users MAY mitigate liveness risk by authorizing multiple independent relayers.

### Reentrancy

Each call in the composable batch is an external call to an arbitrary target. Implementations MUST be resistant to reentrancy — a malicious target contract could attempt to re-enter the composable execution function to manipulate captured slots or execution state. Standard reentrancy guards (e.g., a mutex) SHOULD be used.

### Gas Overhead

The composable execution layer adds gas overhead for:

- Cross-contract calls to the Storage contract for captured return value writes and reads
- External `staticcall`s for runtime value resolution (e.g., `balanceOf` calls, Storage reads)
- Constraint evaluation
- Calldata construction (parameter concatenation)

This overhead is generally modest relative to the gas cost of the underlying DeFi operations and is substantially less than the cost of deploying and maintaining custom smart contracts for each multi-step flow.

## Copyright

Copyright and related rights waived via CC0
