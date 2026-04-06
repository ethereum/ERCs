# ERC-XXXX: NFT-Controlled Account Abstraction - Combined Review Issues

Consolidated from 6 independent reviews. Each issue lists its sources.

**Sources:**
- **T agent** - TS perspective (infrastructure/engineering realism)
- **P agent** - Architectural review (emergent behavior, composability, security surfaces)
- **V agent** - VB Mechanism design review (incentive alignment, credible neutrality, governance)
- **CX-A** - Codex adversarial review
- **CX-S** - Codex standard review
- **CP** - CPerezz.eth (Discord review, 2026-04-03/04)
- **AF** - Additional external feedback (2026-04-06)

---

## Consensus: What Works

All six reviews agree on these strengths:

1. **Direct-owner path as ordinary transaction** - FOCIL/VOPS compatibility is real, scoped honestly, and strategically important. [T, P, V, CP]
2. **Control version invalidation** - Monotonic counter that severs all delegated authority on transfer. Clean and correct. [T, P, V]
3. **Transfer lock with approval-version invalidation** - Stale-approval-becomes-live attack is closed. Defense-in-depth done well. [T, P, V]
4. **Batch-active guard via TSTORE** - Right primitive, right cost allocation (rare transfers, not frequent subcalls). [T, P, V]
5. **Atomic deployment** - No mint-without-code window. [T, P]
6. **Recovery as NFT transfer** - Preserves the core invariant. No split-brain control paths. [T, P]
7. **Honest about limitations** - Explicit non-goals, scoped claims, acknowledged trade-offs. [T, P, V, CP]
8. **Scheme-agile root control** - Pushing alternative signing to the owner-account layer is correct layering. [V, P]
9. **Distinct from ERC-6551 in a meaningful way** - Dedicated controller NFT, one-token/one-account mapping, and transfer-as-control-rotation are a real primitive, not just a constrained 6551 profile. [AF]

---

## HIGH - Spec Bugs and Broken Invariants

### H5. Surviving approvals break the "asset basket transfer" claim
**Sources:** T, P, V, CX-A, CX-S, CP

ERC-20/721/1155 approvals granted by the account survive NFT transfer. No on-chain enumeration exists. A seller can plant sleeper approvals, sell the account, and drain assets post-sale. The "SHOULD batch-revoke" mitigation is not enforceable and creates an information asymmetry favoring sellers.

This is the most-flagged issue across all six reviews.
It also narrows the practical sweet spot: absent stronger transfer hygiene, the design is a better fit for transferable vaults, org subaccounts, and power-user saleable accounts than for a default mainstream consumer wallet.

#### Fix choices by preference
1. Narrow the "atomic basket transfer" claims in the Abstract and Motivation to acknowledge prominently that token-level approvals survive transfer and that buyers bear residual approval risk.
2. ~~Add a standard interface for enumerating known approvals and a distinct "clean transfer" mode that succeeds only after the current controller supplies an approvals inventory commitment or a proof that no tracked approvals remain.~~
3. Require a mandatory approval-inventory mechanism around transfer so outstanding approvals are surfaced before control rotates.
4. ~~Require the account to maintain an on-chain approval registry (appended on `execute`/`executeBatch` calls matching `approve`/`setApprovalForAll` selectors) and expose a `pendingApprovals()` view that marketplaces and buyers can query before accepting a transfer.~~
5. Require a quarantine period around transfer during which the account cannot grant new approvals and existing approvals are frozen until the new controller explicitly re-authorizes them.

### H7. Factory mint path can create self-ownership, cycles, or over-depth trees
**Sources:** AF

The transfer path enforces self-ownership, cycle, and max-depth checks, but the factory can mint a fresh controller token directly to an arbitrary `initialOwner`. That leaves a deploy-time graph hole: the factory can create trivial self-ownership (`initialOwner == deployedAccount`), cycles across yet-to-be-deployed or subsequently deployed accounts, or a depth-5 tree by minting under an existing depth-4 node. If the core invariant is "no self-ownership, no cycles, bounded depth," deployment must enforce the same invariant as transfer rather than relying on post-mint transfers alone.

#### Fix choices by preference
1. Require the factory to enforce the same self-ownership, cycle-detection, and max-depth rules before minting to `initialOwner`, not just on subsequent transfers.
2. Explicitly forbid `initialOwner == deployedAccount` at the factory level as a separate MUST-level check.
3. Factor the ownership-chain validation into one canonical controller-token/library routine used by both transfer and mint paths so the invariant cannot drift.
4. Define deployment to revert whenever minting to `initialOwner` would create a control graph that transfer would reject.
5. Add conformance tests covering deploy-time self-ownership, 2-node cycles created across successive deployments, and minting below an already max-depth parent.

---

## MEDIUM - Underspecified or Ambiguous

### M2. Deployer-setup-handoff invalidates its own validators
**Sources:** CX-A

The spec recommends: deployer mints NFT to self, installs validators, then transfers to recipient. But transfer increments controlVersion, deactivating all validators just installed. The recommended onboarding flow is self-defeating.

#### Fix choices by preference
1. Mint directly to the intended owner and let them install validators themselves, removing the deploy-setup-transfer pattern.
2. Add a post-transfer initialization mechanism so validators can be installed after the recipient receives the token.
3. Add an atomic `deployAccountConfigured(initialOwner, initCalls)` path that mints directly to the recipient and executes a one-time initialization batch under the recipient's control version in the same transaction.
4. Let the factory perform a one-time initialization call before minting the controller token, so setup happens under a pre-transfer bootstrap phase that does not consume the recipient's first control version.
5. Allow forward-looking validator installation with `targetVersion = currentVersion + 1`, so setup can target the recipient's future control era instead of the deployer's.
6. Add a `setupVersion` field that is not incremented on the first transfer after mint, so validators installed during factory setup survive the initial handoff to the recipient.

### M5. Controller token singleton = systemic risk
**Sources:** T, P, V

One canonical controller token per factory. A bug affects every account. No migration path, governance model, or upgrade strategy discussed. Who deploys the factory? Is it permissionless? Can accounts migrate to a different controller token?

#### Fix choices by preference
1. Explicitly state that multiple independent compliant controller-token deployments MAY coexist, so "canonical" is an ecosystem convention rather than a hard singleton assumption.
2. Explicitly address factory governance, canonical deployment model, and bug-recovery path.
3. Standardize an account migration path that can atomically move control to a replacement controller-token contract if the canonical factory or token implementation must be retired.
4. Require immutable controller-token bytecode (no proxy, no `DELEGATECALL`, no admin keys) for the reference deployment to minimize systemic bug surface.
5. Allow the account contract to accept a `migrateController(address newControllerToken)` call gated by a governance timelock or social recovery threshold, so accounts are not permanently coupled to a single controller token deployment.
6. Define a proof-based emergency migration path where a catastrophically broken controller token can be replaced using historical ownership proofs.

### M7. No on-chain discovery of controlled accounts
**Sources:** T, P, V

No way to enumerate all accounts an address controls without off-chain indexing. Hierarchical tree discovery requires event log crawling. Wallet UIs need indexing infrastructure.

#### Fix choices by preference
1. Add an optional paginated `tokensOfOwner` or `accountsOfController` extension so on-chain discovery is possible without making full `Enumerable` support mandatory.
2. Add a factory-side registry tracking `owner => tokenIds[]` so deployments can offer on-chain discovery without forcing full `Enumerable` support onto the controller token.
3. Acknowledge the off-chain indexing dependency explicitly and recommend a companion standard for discovery.
4. Define a canonical subgraph or indexer schema so off-chain discovery has a standard event model and query shape.
5. Emit a dedicated `AccountControlChanged(uint256 indexed tokenId, address indexed previousController, address indexed newController)` event on every transfer so off-chain indexers can build controller-to-accounts mappings from events alone without full state scanning.
6. Require ERC-721 Enumerable on the controller token for on-chain discovery.

### M9. ERC-8211 (Smart Batching) integration: `executeComposable` as a composable execution surface
**Sources:** ERC-8211 draft (ethereum/ERCs#1638, 2026-03-30), additional analysis (2026-04-06)

#### Background

ERC-8211 ("Smart Batching," by Mislav Javor et al.) defines `executeComposable(ComposableExecution[] executions)` — a batch encoding where each parameter declares how to obtain its value at execution time and what constraints that value must satisfy. Instead of freezing all calldata at signing time (as `executeBatch(Call[])` does), each `InputParam` specifies a fetcher (`RAW_BYTES` literal, `STATIC_CALL` to any contract, or `BALANCE` query) and a routing destination (`TARGET`, `VALUE`, or `CALL_DATA`). Resolved values are validated against inline `Constraint[]` (`EQ`, `GTE`, `LTE`, `IN`) before being assembled into the call. Entries with no `TARGET` parameter become pure predicate gates — boolean assertions on chain state that revert the batch if unsatisfied. The standard is account-agnostic: the same encoding works as an ERC-7579 module, ERC-6900 plugin, native account method, or ERC-7702 delegation target.

The ERC is currently Draft status (assigned number 8211 by `lightclient`), has no Ethereum Magicians discussion thread yet, and has no substantive technical review comments on the PR beyond CI issues.

#### Why this matters for ERC-XXXX

ERC-XXXX's `executeBatch(Call[])` is a static batch: every target, value, and calldata byte must be known when the owner signs the transaction. This is correct and minimal but creates real friction for multi-step DeFi flows where intermediate values depend on on-chain state at execution time:

- **Swap-then-use**: owner wants to swap ETH for USDC then deposit into a vault. The exact USDC amount depends on the swap output, which depends on pool state at execution time. With static batching, the owner must either hardcode an estimated amount (risking revert on slippage) or deploy a custom router contract.
- **Dustless transfers**: owner wants to transfer their entire ERC-20 balance. With static batching, the balance must be queried off-chain and hardcoded; if anything changes before inclusion, the transaction either leaves dust or reverts.
- **Cross-chain orchestration**: owner wants to bridge assets from chain A then execute on chain B once the bridge delivery is confirmed. Static batching cannot express "wait until bridged balance arrives, then execute."
- **MEV-aware execution**: owner wants slippage guards that are evaluated on-chain at execution time, not at signing time when pool state may be different.

ERC-8211's `executeComposable` solves all four by resolving parameters from live on-chain state and validating constraints before each call proceeds.

#### Architectural fit analysis

**1. Authorization model — clean fit.** The controlled account checks `msg.sender == ownerOf(tokenId)` regardless of which execution function is called. Adding `executeComposable` to the account interface requires no change to the authorization model: the owner (or a validator via ERC-4337) authorizes the composable batch, and the account verifies ownership before executing. The dynamic parameter resolution happens *inside* the account's execution context after authorization, not before it.

**2. Execution-active guard — requires explicit inclusion.** ERC-XXXX uses a TSTORE reference-counted flag (`isExecutionActive()`) set during `execute` and `executeBatch` to prevent mid-execution control rotation. `executeComposable` MUST set the same transient flag on entry and clear it on exit so that the transfer guard covers composable execution identically. Since ERC-8211 entries execute sequentially with staticcalls for parameter resolution between calls, the flag must remain active for the entire `executeComposable` invocation, not per-entry.

**3. Transfer lock — requires the same `locked(tokenId) == true` check.** `executeComposable` MUST revert if the controller token is in the unlocked (transferable) state, identical to `execute` and `executeBatch`. This maintains the separation between "ready to execute" and "ready to transfer" that closes the sell-and-drain attack (H3).

**4. Control-version binding for signed composable batches.** When a composable batch is submitted through the ERC-4337/validator path rather than by the direct owner, the signed authorization must bind to the current `controlVersionOf(tokenId)`. This is already required for `executeBatch` under the validator path; `executeComposable` inherits the same requirement. ERC-8211's cross-chain Merkle authorization structure (defined in a separate companion ERC) would need to incorporate the control version in its authorization tree.

**5. ERC-1271 / ERC-7739 compatibility.** If composable batches are authorized via off-chain signatures (e.g., for relayed execution), the signature must use the same ERC-7739 defensive rehashing over the account's ERC-5267 domain, with the salt incorporating `controllerToken`, `tokenId`, and `controlVersion`. The `ComposableExecution[]` struct becomes the typed data payload. This is a natural extension of the existing signing architecture.

#### Security implications specific to NFT-controlled accounts

**1. Dynamic targets expand the execution surface.** With static batching, the owner signs exact target addresses. With composable execution, a `TARGET` parameter resolved via `STATIC_CALL` means the actual call target is determined at execution time by reading on-chain state. If the staticcall target is compromised or returns a malicious address, the controlled account calls an attacker contract. Constraints can bound the resolved value (e.g., `EQ` to whitelist a specific address), but the default posture is more permissive than static batching. This is a meaningful trust-model shift for an account whose entire security story is "the NFT owner controls everything."

**2. Sandwich attacks on resolved parameters.** ERC-8211's `STATIC_CALL` and `BALANCE` fetchers read state at execution time. An MEV searcher who observes a pending composable batch can sandwich the transaction to manipulate the state read by the fetchers (e.g., move a pool price before the account's swap, causing the resolved amount to be worse than intended). The constraint system provides defense (`GTE(minOutput)` on swap results), but constraints are only as good as the bounds the owner set. For an NFT-controlled account holding significant value, this attack surface is more consequential than for a typical EOA because the controlled account aggregates assets.

**3. Storage contract isolation.** ERC-8211 uses an external `Storage` contract for passing captured values between batch entries. The storage is namespaced by `keccak256(account, caller)`. For NFT-controlled accounts, the relevant namespace is `keccak256(accountAddress, accountAddress)` (when using delegatecall) or `keccak256(accountAddress, adapterAddress)` (when using call). If the account switches between call and delegatecall contexts across transactions, captured values from prior transactions may be inaccessible or stale. The account SHOULD use a consistent invocation context and SHOULD treat storage values as transaction-scoped (EIP-1153 TSTORE is the preferred backend) rather than persistent.

**4. Predicate entries as execution gates do not affect the authorization model.** An entry with no `TARGET` parameter just asserts a condition and continues or reverts. No call is executed, no state is modified. This is safe: the worst case is a spurious revert, not an unauthorized operation. Predicate entries are particularly useful for NFT-controlled accounts in cross-chain scenarios (e.g., "revert unless the bridged balance has arrived"), and they interact cleanly with the execution-active guard (the flag remains set, no target is called).

**5. Reentrancy through resolved targets.** ERC-8211 entries can call arbitrary targets. A malicious target could reenter the controlled account via `execute`, `executeBatch`, or `executeComposable`. The existing TSTORE reference-counting allows nested execution from the owner (this is intentional), so reentrancy is permitted but the transfer guard blocks mid-execution control rotation. Implementations SHOULD ensure that the Storage contract's slot-initialization tracking is not corrupted by reentrant writes.

**6. Interaction with L9 (EIP-7702).** If the owner EOA has a 7702 delegation, the delegated code can call `executeComposable` with the same authority as `execute`. Dynamic parameter resolution under malicious delegation amplifies the blast radius: the delegated code could construct composable batches that read attacker-controlled state, resolve to attacker targets, and drain the account in a single call. All L9 mitigations apply equally to `executeComposable`.

#### Integration patterns

**Pattern A: Native account method (recommended).** The account contract implements `IComposableExecution` directly alongside `execute` and `executeBatch`. The `executeComposable` function applies the same authorization check (`msg.sender == ownerOf(tokenId)`), the same `locked(tokenId) == true` requirement, the same execution-active transient flag, and delegates to `ComposableExecutionLib` for the resolution/execution/capture loop. This is the thinnest integration: no cross-contract call overhead for the adapter, no storage-namespace ambiguity.

**Pattern B: ERC-7579 executor module.** If the account evolves toward ERC-7579 modular architecture (see M5 migration discussion and Standards Reuse Checklist item 10), `executeComposable` installs as an executor module. The module inherits the account's authorization context. This pattern is heavier but aligns with the modular-account direction if the ERC-XXXX account eventually supports modules beyond validators.

**Pattern C: Delegated via `execute`.** The owner calls `execute(composableAdapter, 0, abi.encodeCall(IComposableExecution.executeComposable, executions))` — the account calls the adapter as an external contract. This works today with no spec changes but loses the account context: the adapter executes calls from its own address (not the controlled account's), which is not useful for DeFi interactions that need to operate on the account's assets. This pattern is only viable if the adapter uses delegatecall internally, which reintroduces the native-method question.

**Pattern D: Composable batch as `executeBatch` payload.** The owner uses `executeBatch` to call a standalone composable-execution contract. The controlled account makes external calls to the contract, which resolves parameters and calls back. This creates a double-hop (account → adapter → target) and requires the adapter to be trusted, since it operates with the account's authorization for the callbacks. Not recommended due to complexity and trust surface.

#### Relationship to existing issues

- **L1 (Cross-contract SLOAD gas):** `executeComposable` adds more staticcalls per batch (parameter resolution). The gas overhead concern is amplified. The TSTORE caching recommendation in L1 becomes more important.
- **L3 (No gas limit on executeBatch):** Applies equally to `executeComposable`, which adds resolution overhead per entry. The block-gas bound is still the only limit.
- **L17 (Proposal decomposition):** Adding `executeComposable` to the core spec increases the surface area. This argues for making it an optional extension or companion ERC rather than a core MUST.
- **H5 (Surviving approvals):** Composable batching makes it easier for a buyer to implement "clean transfer" verification — a predicate entry could assert via staticcall that known approval counts are zero before accepting a transfer. This is a partial complementary mitigation.

#### Fix choices by preference
1. Add `IComposableExecution` as an OPTIONAL extension interface that compliant accounts MAY implement, with normative requirements that implementations MUST apply the same authorization check, `locked(tokenId) == true` guard, and execution-active transient flag as `execute`/`executeBatch`. Reference ERC-8211 by number and defer the encoding/resolution semantics entirely to that standard.
2. Define a "Composable Execution Extension" appendix within ERC-XXXX specifying the exact integration requirements (authorization, transfer-lock check, transient guard, control-version binding for signed batches) without duplicating ERC-8211's resolution algorithm, and add `IComposableExecution` to the ERC-165 interface detection surface.
3. Recommend native account integration (Pattern A) as the RECOMMENDED integration path over module or delegated patterns, because it avoids storage-namespace ambiguity and cross-contract trust surfaces.
4. Require that `executeComposable` entries with dynamically resolved `TARGET` parameters emit an event logging the resolved target address, so off-chain observers can reconstruct what the account actually called (static batches are self-describing from calldata; composable batches are not).
5. Add a security note that dynamically resolved targets shift the trust model from "owner signed exact calldata" to "owner signed a resolution program whose outputs depend on chain state at execution time," and that constraints are the primary defense against resolved-value manipulation.
6. Recommend transaction-scoped storage (EIP-1153 TSTORE) as the preferred backend for the ERC-8211 Storage contract when used with NFT-controlled accounts, to prevent stale cross-transaction data leakage.
7. Add conformance tests covering: (a) `executeComposable` reverts while token is unlocked, (b) execution-active flag blocks transfer during composable execution, (c) control-version binding in signed composable batches, (d) predicate-only entries (no target) succeed without side effects, (e) reentrancy through resolved targets does not corrupt storage capture state.
8. Wait for ERC-8211 to stabilize beyond Draft and gain at least one independent implementation and security audit before adding it as a normative extension, keeping it as a non-normative "Composability Examples" reference in the interim.

---

## LOW / INFORMATIONAL

### L1. Cross-contract SLOAD on every execution
**Sources:** T

Every `execute`/`executeBatch` requires STATICCALL to controller token's `ownerOf`. Cold SLOAD (2100 gas) + external call overhead (~2600 gas cold). Spec forbids internal cache. Needs benchmarking.

#### Fix choices by preference
1. Allow implementations to cache the controller token response within a single transaction using TSTORE, avoiding repeated cold SLOADs for multi-call execution paths while still re-resolving on each new transaction.
2. Add a normative sentence confirming that a compliant account checks `ownerOf` exactly once per `execute` or `executeBatch` entry, not per subcall.
3. Define an optional packed `controllerAndVersionOf(tokenId)` view on the controller token so implementations that need both values can collapse multiple external reads into one call.
4. Recommend EIP-2930 access lists so wallets can prewarm the controller-token storage touched during execution.
5. Store controller token address as immutable (in bytecode). Benchmark on testnet.
6. Specify a hand-optimized inline-assembly controller check in the reference implementation to reduce ABI encoding overhead on the `STATICCALL`.
7. Add a rationale note that this concern is gas-model-specific and may soften under future Verkle-era storage pricing.

### L3. No gas limit on `executeBatch` subcalls
**Sources:** T

No limit on call count. Recursive batches through hierarchy can fan out. Block gas limit is the only bound.

#### Fix choices by preference
1. Define a maximum batch length so pathological fan-out fails deterministically before exhausting block gas.
2. Disallow recursive `executeBatch` calls so fan-out cannot grow combinatorially through nested batching.
3. Extend `Call` with an optional `gasLimit`, letting transaction authors bound individual subcalls explicitly.
4. Define a minimum remaining-gas rule per remaining subcall so gas exhaustion is predictable and bounded.
5. Require `executeBatch` to forward at most `gasleft() / (remaining + 1)` gas to each subcall and document the recursion fan-out bound in the rationale so wallet UIs can warn before constructing pathological batches.
6. Set a RECOMMENDED maximum batch size (e.g., 64 calls) in the spec and require wallets to surface a warning when constructing larger batches, while leaving the hard on-chain limit to the block gas bound.
7. Emit per-subcall gas-usage events for tooling and simulation feedback.

### L5. 4-hop nesting limit is unjustified
**Sources:** P, V

No rationale for 4 vs 3 or 5. Gas stipend of 30k may become insufficient. Failure mode is hard revert. Should degrade gracefully or justify the bound.

#### Fix choices by preference
1. Replace the fixed value with a named configurable constant plus rationale, and require wallets to surface the supported maximum nesting depth before users build deeper trees.
2. Justify the bound with a gas analysis in the rationale (e.g., 4 hops × 30,000 gas = 120,000 gas worst case for cycle detection) and add a graceful-degradation rule where exceeding the depth returns a transfer failure rather than hard-reverting, so parent transfers are not bricked by unexpectedly deep children.
3. Separate cycle detection from hierarchy-depth policy: use one mechanism to detect cycles correctly and another to cap maximum supported nesting for UX or gas reasons.
4. Use a transient visited-set during the ownership-chain walk so cycle detection can be correct at arbitrary depth without relying on a small hardcoded hop count.
5. Let the factory expose configurable `maxNestingDepth` (default 4) and `ownerOfGasStipend` (default 30,000) so deployments can adapt to future gas schedule changes without a spec revision, and require the transfer to revert with a descriptive error code rather than a raw out-of-gas.

### L8. Controller token state growth
**Sources:** T

5-7 storage slots per account, all on one contract. At 10M accounts = 50-70M slots. Same profile as popular ERC-721 contracts but worth noting for archive node operators.

#### Fix choices by preference
1. Use an aggressively packed storage layout so ownership, control version, and lock state fit into the minimum practical number of slots.
2. Lazy-initialize optional metadata storage so display fields consume no state unless a token actually uses them.
3. Move display-only metadata off the main controller-token storage path where possible, so account-critical state remains compact.
4. Document the expected storage growth curve (5–7 slots × N accounts) so archive node operators can plan capacity, and recommend that ecosystem tooling support multiple controller-token contract addresses per chain.
5. Add a rationale note comparing the growth profile to existing large ERC-721 contracts (e.g., ENS with millions of entries on a single contract) and conclude that the per-account overhead is within normal EVM operational parameters.
6. Explicitly allow horizontal partitioning across multiple canonical controller-token deployments or factory shards instead of implying one unbounded singleton for the entire ecosystem.

### L9. EIP-7702 interaction under-explored — upgraded to MEDIUM after deeper research
**Sources:** P, additional research (2026-04-06)

**Severity upgrade rationale:** Real-world EIP-7702 delegation phishing has already drained $12M+ from 15,000+ wallets since Pectra (May 2025). Over 97% of early 7702 delegations pointed to malicious sweeper contracts. The attack surface is not theoretical — it is actively exploited at scale and directly applicable to NFT-controlled accounts.

#### Background

EIP-7702 (Pectra, May 2025) allows any EOA to persistently delegate code execution to a target contract via `SET_CODE_TX_TYPE (0x04)`. The delegation designator `0xef0100 || address` is written to the EOA's code slot and persists across transactions until explicitly changed or revoked. When any external actor CALLs a delegated EOA, the target contract's code executes in the EOA's context (address, storage, balance) — functionally equivalent to DELEGATECALL.

#### Why the authorization model is technically sound but practically dangerous

The `msg.sender == ownerOf(tokenId)` check works correctly: delegated code executing in the EOA's context produces calls where `msg.sender` is the EOA address, which matches `ownerOf(tokenId)`. The authorization path is not broken. However, 7702 introduces five risks that the current Security Considerations section does not address:

**1. Third-party triggering without private key access.** Once delegation is set, *anyone* who CALLs the EOA address triggers the delegated code. The attacker does not need the EOA's private key to execute arbitrary operations on every controlled account. This is a strictly new capability beyond key compromise: with key theft the attacker must actively submit transactions; with 7702 delegation the attacker only needs to trigger a CALL (or wait for an ambient callback, airdrop distribution, or any contract interaction that touches the EOA).

**2. Silent behavior change between blocks with no on-chain signal.** The EOA can set, change, or revoke delegation at any time. `ownerOf(tokenId)` still returns the same address. `controlVersionOf(tokenId)` does not change. No event is emitted on the controller token or controlled account. The controlled account has no mechanism to detect that the owner's code changed. This means an EOA can be benign in block N, malicious in block N+1, and benign again in block N+2 — with zero visibility to the controlled account or its observers.

**3. Persistent backdoors that survive delegation revocation.** In a single transaction, malicious delegated code can:
- Call `execute()` to grant unlimited ERC-20/721/1155 approvals from the controlled account to attacker addresses (stored on external token contracts, not revocable by revoking the delegation).
- Call `execute()` to `installValidator(malicious_validator)` — the validator remains active because the control version does not change when delegation changes.
- Call `setUnlockDelay(tokenId, 1)` to reduce the transfer lock delay to the minimum.
- Write to the EOA's own storage slots, planting state that future delegations may read.

Revoking the 7702 delegation does not undo any of these state changes. The user must independently discover and revoke each approval, remove each validator, and restore the unlock delay.

**4. Correlated multi-account compromise.** If one EOA holds controller NFTs for accounts A, B, and C, a single delegation compromise exposes all three. The existing Security Considerations note about multi-NFT risk ("if the EOA ... is compromised, the attacker gains root control over every account") applies, but 7702 makes this compromise achievable through a single signed authorization tuple — a small data structure that does not look like a dangerous transaction to most users and is already the primary vector for phishing at scale.

**5. Social engineering amplification.** An EIP-7702 authorization tuple `[chain_id, address, nonce]` does not resemble an `execute()` call or a token transfer in wallet UIs. Users can be tricked into signing one without understanding that it grants persistent, third-party-triggerable root control over every account their EOA controls. Wallet UIs that show the controlled account's balance but not the EOA's delegation status give users a false sense of security.

#### What the transfer lock does and does not protect

The transfer lock (`proposeUnlock` → delay → `completeUnlock`) **does protect the controller NFT itself**: malicious delegated code cannot atomically transfer the NFT because `unlockDelay >= 1` creates temporal separation. The separation between execution and transfer states (`execute` reverts while unlocked) means the attacker cannot drain assets AND transfer the NFT in a single flow.

The transfer lock **does not protect assets inside the controlled account**. Delegated code can call `execute()` and `executeBatch()` freely while the token is locked (the normal execution state), draining all ETH and tokens without ever touching the transfer lock.

#### Concrete attack scenario

1. Alice's EOA holds controller NFTs for accounts A, B, C (combined value: 50 ETH + various tokens).
2. Attacker tricks Alice into signing one authorization tuple pointing to a sweeper contract. The tuple looks innocuous in Alice's wallet UI.
3. The delegation is processed. Alice's EOA now has code `0xef0100 || sweeper_address`.
4. Attacker (or any external trigger) CALLs Alice's EOA.
5. Sweeper code executes in Alice's EOA context:
   - Calls `executeBatch()` on account A: transfers all ETH and tokens to attacker.
   - Calls `executeBatch()` on account B: same.
   - Calls `executeBatch()` on account C: same.
   - Optionally installs attacker-controlled validators on all three accounts.
   - Optionally calls `setUnlockDelay(tokenId, 1)` on all three to prepare for later NFT theft.
6. All three accounts are drained. Alice's controlled accounts show zero balance. The controller NFTs remain in Alice's possession (locked), but the assets are gone.

#### Detection capability exists but is not surfaced

`EXTCODESIZE(owner)` returns 23 for a 7702-delegated EOA (vs 0 for a normal EOA). `EXTCODEHASH(owner)` changes when delegation is set. The controlled account *could* detect delegation, but the spec explicitly does not require this check — the owner is treated as a black box, which is correct from a layering perspective but leaves users without defense.

#### Fix choices by preference
1. Add a dedicated `EIP-7702 Delegation Risk` subsection to Security Considerations covering: (a) third-party triggering without key access, (b) silent behavior change with no control-version increment, (c) persistent backdoor installation that survives revocation, (d) correlated multi-account compromise from a single authorization tuple, and (e) social engineering amplification from the innocuous appearance of authorization tuples.
2. Recommend that wallets displaying controlled-account balances also surface the owner EOA's delegation status (`EXTCODESIZE == 23` or `EXTCODEHASH` change) and warn when delegation is active, so users are not blind to owner-side code changes.
3. Add an optional `controllerCodeHash(tokenId)` view on the controller token that caches and exposes the owner's `EXTCODEHASH` at last execution, so off-chain tooling can detect delegation changes without polling.
4. Recommend that high-value accounts use a contract owner (multisig, Safe, or minimal immutable controller) rather than a raw EOA, since contract accounts cannot be 7702-delegated and eliminate the entire attack surface.
5. Add an optional `requireStableOwner(tokenId)` mode where `execute()` reverts if `EXTCODESIZE(ownerOf(tokenId)) == 23`, letting security-conscious users opt into blocking execution from 7702-delegated owners entirely.
6. Require `setUnlockDelay` to enforce a minimum floor (e.g., 1 hour) so that even if malicious delegated code reduces the delay, the user retains a meaningful detection window before the NFT can be transferred.
7. Add a normative note that `controlVersionOf(tokenId)` does not increment when the owner's 7702 delegation changes, and that validators installed by delegated code remain active after delegation revocation — users must call `resetDelegations(tokenId)` manually to invalidate them.
8. Recommend conformance tests covering: (a) execute from 7702-delegated owner succeeds, (b) EXTCODESIZE-based detection of delegation, (c) validator persistence after delegation revocation, (d) transfer lock behavior when delegated code calls proposeUnlock.

### L10. Privacy pool section is premature
**Sources:** P, V

Does not add normative requirements beyond what is already required. Could mislead implementers about privacy properties. Consider moving to non-normative examples.

#### Fix choices by preference
1. Convert the section into a "Privacy Non-Guarantees" threat-model note that explicitly lists the metadata leaks implementers should assume remain public.
2. Move the privacy-pool section to a non-normative appendix and keep it as informational guidance that references the core execution interface.
3. Add a prerequisite that the discussion applies only to implementations that also support optional relayed execution such as ERC-4337 or equivalent validator-mediated flows.
4. Rewrite the section as a non-normative "Example: Privacy-Aware Deployment" using only MAY/SHOULD language and explicitly state that the example depends on optional ERC-4337 or validator-mediated execution, not on the base ERC's direct-owner path.
5. Replace it with a broader "Composability Examples" section covering privacy pools alongside other integrations.
6. Remove the section from the core ERC entirely and publish it as a separate implementation note or application-note entry once a concrete relayed-execution path is standardized.

### L12. Economic sustainability not discussed
**Sources:** V

Factory deployment, audits, tooling, wallet integrations - who pays? No public goods funding mechanism described.

#### Fix choices by preference
1. State explicitly that canonical deployment and maintenance are out of scope for this ERC.
2. Note that ERC-20 and ERC-721 likewise define no funding mechanism; this is normal for standards and not itself a protocol gap.
3. Add a one-line rationale note: "Canonical deployment, audits, and tooling follow the same community-driven model as ERC-4337 and ERC-1167; this ERC does not prescribe a funding mechanism."
4. Add a rationale note that immutable deployment pushes most costs upfront rather than creating ongoing governance or maintenance obligations.
5. Note RPGF, grants, or similar ecosystem funding as plausible support for shared infrastructure around a canonical deployment.
6. Note that wallet and integrator adoption can be justified by their own product economics, not only by protocol-native funding.
7. Describe the expected funding and stewardship model for audits, infrastructure, and wallet support.

### L13. Standard governance unspecified
**Sources:** V

Canonical factory address, account implementation, future amendments - who decides? Gap between "ERC finalized" and "canonical deployment."

#### Fix choices by preference
1. State that multiple independent deployments of compliant controller tokens MAY coexist and that "canonical" is an ecosystem convention, not an ERC-enforced singleton.
2. Explicitly state that the ERC intentionally does not define a governance body and that alternative deployments are encouraged, because designated control would create unnecessary centralization risk.
3. Define a permissionless no-governance deployment story anchored in audited reference bytecode or bytecode hash rather than a governing body.
4. State that the canonical factory address is determined by the first successful CREATE2 deployment of the audited reference implementation, with no governance body required, and that future amendments follow the standard ERC process.
5. Use version-tagged deployments so future major versions can coexist without forcing upgrades.
6. Define an advisory-only recommendation mechanism for wallets that want guidance without granting power over existing accounts.
7. Define an explicit governance process for naming canonical deployments and coordinating future amendments.

### L16. No test vectors or reference implementation
**Sources:** V, T (summary)

Essential for this complexity level. Cycle detection, transfer locks, batch-active guards, and validator scoping all need concrete test cases for interoperability.

#### Fix choices by preference
1. Publish the reference implementation as an `assets/erc-XXXX/` Solidity file with inline NatSpec and a companion Foundry test suite covering the critical paths identified in this review.
2. Add a minimal reference implementation and conformance test suite covering transfer/version invalidation, nested batches, timelocks, cycle checks, and validator activation semantics.
3. Publish language-agnostic JSON test vectors so non-Solidity implementations can validate core behavior.
4. Publish explicit negative or must-revert test vectors for the security-critical failure cases.
5. Define property-based invariants that reference implementations and alternate implementations can fuzz against.
6. Publish a simple differential model in another language, such as Python, for cross-language validation of the state machine.
7. Include gas benchmarks for the key flows as performance documentation and regression tests.

### L17. Proposal length / decomposition
**Sources:** P, V, AF

~800 lines for Draft. Could split into core ERC (token model + execution) and companion ERCs (metadata, recovery, validator scoping, hierarchy). The current draft mixes the core root-control primitive with recovery, privacy-pool flow, metadata/avatar forwarding, regulatory discussion, and future-extension questions; that makes the central standard harder to evaluate than it needs to be.

#### Fix choices by preference
1. Keep a single ERC but add explicit appendix structure with clear boundaries between core (token model + execution), extensions (metadata, recovery, validators), and informational (privacy, FOCIL) so readers can distinguish mandatory from optional material.
2. Layer the document explicitly within the single ERC so implementations can orient themselves by topic or conformance surface.
3. Add a short Specification Summary or TL;DR listing the core normative requirements near the top.
4. Move non-core material such as metadata and privacy examples into appendices until the core settles.
5. Extract the FOCIL/VOPS or broader mempool-positioning discussion to a separate note aimed at protocol-design readers.
6. Publish a companion Design Notes document for motivation, rationale, examples, and comparisons.
7. Split the draft into a core ERC plus companion extensions (metadata, recovery, validator scoping, hierarchy).
8. Add a "Conformance Levels" section defining a minimal core profile (token model + execute + executeBatch) and an extended profile (metadata + validators + recovery), so implementations can claim partial conformance without implementing everything.
9. Add a machine-readable schema or conformance manifest only after the human-facing structure is stable.

### L19. NFT marketplace interaction
**Sources:** V

Controller tokens on OpenSea/marketplaces look like regular NFTs. Buyer may not understand they are purchasing account control. Needs marketplace integration guidance.

#### Fix choices by preference
1. Define an ERC-165 interface ID that marketplaces can detect via `supportsInterface` to automatically apply controller-token warning UX, rather than relying solely on metadata string fields.
2. Use ERC-7572 `contractURI()` to provide collection-level warnings before a buyer even opens an individual token page.
3. Provide a visually distinct default SVG or metadata presentation so controller tokens do not resemble ordinary collectible art.
4. Require prominent metadata warnings and recommend a standardized marketplace-facing signal, such as explicit collection naming and description fields that mark the token as wallet control rather than artwork.
5. Implement ERC-5192 `locked()` semantics so marketplaces can surface the default non-transferable state during lock periods.
6. Recommend a dedicated account-trading marketplace or category for listings that need account-specific status such as balances, approvals, validator status, and lock state.
7. Recommend that the controller token's `name()` and `symbol()` include "Controller" or "Wallet" and that `tokenURI` metadata include a standardized `"type": "controller-token"` JSON field so aggregators can programmatically distinguish controller tokens from collectibles.

---

## Standards Reuse Checklist

Research check for standards the draft should adopt, may adopt, or should ignore relative to current ecosystem support and overlap. The goal here is to avoid inventing ERC-local surfaces when an existing standard already matches the draft's controller-token, signature-validation, deployment, or marketplace-integration needs.

### Adopt

1. ~~`ERC-5192`~~ - adopt the standard `locked()` surface for the controller token. The draft already uses `Locked` and `Unlocked` events and explicitly separates execution from the unlocked transferable state, so this is a direct fit rather than a speculative extension. Making it explicit gives wallets and marketplaces a standard binary lock signal instead of requiring ERC-local introspection and directly helps the L19 marketplace-UX problem.
2. ~~`ERC-4906`~~ - use standard metadata refresh events when controller-token metadata changes due to naming changes, image-assignment changes, or transfer-triggered `tokenURI` changes. Do not duplicate [EIP-5192](./eip-5192) lock-status signaling with `MetadataUpdate` when lock/unlock already conveys the meaningful state transition.
3. `ERC-7572` - use `contractURI()` for collection-level warnings such as "this NFT transfers wallet control". That warning belongs at collection scope as well as token scope, and OpenSea documents support for this surface.
4. ~~`ERC-5267`~~ - use `eip712Domain()` if validator, recovery, or delegated-signature flows are normatively based on `EIP-712`. If the draft standardizes typed signing, domain discoverability should also be standardized.
5. ~~`ERC-7739`~~ - adopt it for the `ERC-1271` typed-signature path if the draft continues to require account-bound, chain-bound, token-bound, and control-version-bound digests. That is exactly the class of replay-resistant smart-account signing scheme the draft is otherwise at risk of specifying ad hoc, and standard reuse is especially valuable here because this is a security-critical path.
6. `ERC-173` - use standard contract ownership discovery if the factory or controller token exposes an admin/owner role and ecosystem tooling should be able to detect it. This is low-cost and avoids inventing a bespoke admin-discovery interface.

### Maybe

1. `ERC-6492` - strong fit for deterministic `CREATE2` deployment and predeploy signatures, and it is already referenced in the draft's reference-implementation guidance. It should likely remain optional unless counterfactual signing before deployment is made part of baseline interoperability rather than an implementation enhancement.
2. [ERC-6093](./eip-6093) - standard ERC-20/721/1155 custom errors are a good fit for the controller token and cost almost nothing in modern Solidity toolchains. The reason this is not a clear "Adopt" is that it improves implementation consistency more than cross-implementation protocol interoperability unless the ERC wants to standardize revert surfaces.
3. `ERC-6454` - generic transferability introspection (`isTransferable`) could complement `ERC-5192`, but `ERC-5192` is the more important standard fit here and there is still no comparably clear major-marketplace support signal for `ERC-6454`.
4. `ERC-5008` - useful only if the controller token wants a standardized marketplace-facing NFT nonce for listing or order invalidation; should complement, not replace, `controlVersion` or `transferApprovalVersion`, which have broader custody-rotation semantics than marketplace order freshness alone.
5. `ERC-5639` - useful as an optional external delegation or authentication layer, but not as a substitute for account-native delegated authority or `controlVersion`-scoped invalidation.
6. `ERC-7401` - there is real overlap with the draft's parent/child wallet hierarchy because the proposal already contemplates accounts holding controlling NFTs of other compliant accounts. Standard nestable-NFT semantics could help with enumeration and discovery, but they may also pull the draft toward a heavier NFT hierarchy model than its custom transfer-lock and account-control semantics need.
7. `ERC-7710` - worth revisiting only if validators evolve from narrow version-scoped signature validation into a broader delegation or capability-grant system. Right now the overlap is suggestive, but the draft's validator model is intentionally much narrower than a general delegation framework.
8. `ERC-7913` - useful if validators or recovery guardians need signer models that do not map cleanly to Ethereum addresses; has real library support despite being Draft.
9. `ERC-7562` - relevant only for implementations that also support `ERC-4337`. It is best treated as an execution-environment constraint on validation logic, not as a core dependency of the NFT-controlled-account standard itself.
10. `ERC-7579` - relevant only if the validator subsystem grows into a broader modular smart-account architecture rather than staying narrowly scoped.
11. `ERC-7201` - useful only if implementations choose upgradeable, clone-based, or module-extensible storage layouts where storage-slot collision risk is real. The current draft prefers immutable or minimally upgradeable logic, so this is an implementation-architecture question, not a core-standard dependency.
12. `ERC-7821` - relevant only if aligning the execution interface with the emerging smart-account batch executor surface is a priority; still early.
13. `ERC-8211` - smart batching with runtime parameter resolution via `executeComposable(ComposableExecution[])`. Strong fit for dynamic DeFi flows (swap-then-use, dustless transfers, cross-chain predicate gating) that static `executeBatch` cannot express without custom router contracts. Account-standard agnostic with native, ERC-7579 module, and ERC-7702 adapter patterns. Currently Draft with no independent implementations or audits. See M9 for detailed integration analysis. Should remain optional/MAY-level and wait for the standard to stabilize before normative adoption.

### Ignore

1. `ERC-6982` - richer lock semantics on paper, but no clear public major-marketplace support signal, and the draft mostly needs a simple binary "transferable right now or not" signal that `ERC-5192` already covers.
2. `ERC-7066` - likewise no clear public major-marketplace support, and its locker model does not match this ERC especially well because the lock here is intrinsic to custody-transfer state rather than delegated to a separate locker abstraction.
3. `ERC-5753` - OpenSea recognizes its lock events, but the standard is stagnant and its unlocker-oriented model is a weaker fit than `ERC-5192` for controller-token transfer timing.
4. `ERC-5521` - referential NFT graph semantics are orthogonal to account control, custody, hierarchy, and marketplace signaling in this ERC; only relevant as an optional provenance layer.
5. `ERC-7432` - NFT roles do not map cleanly to this draft's single-controller custody model. The proposal is about root account control transfer, not assigning partial permissions to token holders or third parties.
6. `ERC-7677` - paymaster web-service discovery is too far from the core problem here. Sponsored execution is optional, `ERC-4337` support is optional, and this draft's main interoperability surface is onchain account control rather than offchain paymaster capability discovery.
7. `ERC-6900` - the current validator install/remove/active surface is too narrow to justify adopting a full modular-smart-account framework. If the draft grows into a general module system, revisit this together with `ERC-7579`; at present it would add conceptual weight without solving a concrete interoperability gap.
8. `ERC-7208` - onchain data-container semantics are overbuilt for the controller-token/account-control problem and do not solve any of the checklist's current interoperability gaps.
9. `ERC-7715` - wallet-permission frameworks sit at the application layer and do not map closely to the account-layer transfer-of-control semantics this draft standardizes.
10. `ERC-1167` - minimal proxies may be a perfectly valid implementation technique, but the draft only requires deterministic `CREATE2` deployment and should not imply clone-based deployment or delegatecall-based architecture as a normative dependency.

---

## Summary Table

| # | Issue | Severity | Sources | Status |
|---|-------|----------|---------|--------|
| H5 | Surviving approvals break basket-transfer claim | High | All 6 | Open - most flagged issue |
| H7 | Factory mint path can violate graph invariants | High | AF | Open |
| M2 | Deployer-setup-handoff invalidates validators | Medium | CX-A | Open |
| M5 | Controller token singleton = systemic risk | Medium | T, P, V | Open |
| M7 | No on-chain discovery of controlled accounts | Medium | T, P, V | Open |
| M9 | ERC-8211 Smart Batching integration | Medium | ERC-8211 draft | Open |
| L1 | Cross-contract SLOAD gas overhead | Low | T | Needs benchmarking |
| L2 | tokenURI forwarding unbounded | Low | T | Open |
| L3 | No gas limit on executeBatch | Low | T | Informational |
| L5 | 4-hop limit unjustified | Low | P, V | Open |
| L8 | Controller token state growth | Low | T | Informational |
| L9 | EIP-7702 interaction — upgraded to Medium | Medium | P, research | Open |
| L10 | Privacy pool section premature | Low | P, V | Open |
| L12 | Economic sustainability | Low | V | Informational |
| L13 | Standard governance | Low | V | Open |
| L16 | No test vectors | Low | V, T | Open |
| L17 | Proposal decomposition | Low | P, V, AF | Informational |
| L19 | NFT marketplace UX | Low | V | Open |
