# ERC-XXXX: NFT-Controlled Account Abstraction - Resolved Issues

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

## HIGH - Spec Bugs and Broken Invariants

### H1. TSTORE revert semantics: batch-active counter can underflow
**Sources:** CP

[x] Fix: Remove "decrement on revert" language and rely on EVM revert semantics for TSTORE rollback; though note this behavior.

### H2. Mid-`execute` control rotation (batch guard does not cover plain execute)
**Sources:** CX-A, CP (related)

[x] Fix: Make the controller token's transfer function check a general "execution-active" transient flag that is set by both `execute` and `executeBatch`, unifying the guard under one mechanism.

### H3. Sell-and-drain attack: no mandatory freeze window around transfer
**Sources:** CP

The original concern was broader than "batch transfer during execution." The problem is that NFT-mediated account sales are exposed to transaction-ordering games unless the standard imposes a real freeze window between "seller can still execute" and "buyer can take control." `TSTORE`-based guards do not solve this because they are per-transaction rather than per-block. `batchGuard` also does not solve it because the seller can drain in a separate transaction before the buyer's transfer executes. Likewise, delaying only the unlock is insufficient if the owner can keep executing right up until control rotates.

[x] Fix: Require that `execute` and `executeBatch` revert while the token is in the unlocked (transferable) state, forcing the owner to re-lock before executing and creating a natural separation between "ready to transfer" and "ready to execute." This fix only closes the ordering path if transferability itself requires a strictly positive `unlockDelay`; if `unlockDelay == 0` remains compliant, the separation collapses into a same-transaction toggle and the mitigation is largely toothless. In other words, the mitigation works only if the ERC makes a nonzero unlock delay effectively mandatory for transferable operation, with the default or initial `unlockDelay` for transferable tokens set to `>= 1`.

### H4. Sponsored/relayed execution is MUST-level but has no compliant path
**Sources:** CX-A, CX-S

[x] Fix: Downgrade from MUST to "this flow works when optional validator or ERC-4337 support is present."

### H6. NFT theft = full account takeover at scale
**Sources:** P, V

[x] Fix: Revert `setApprovalForAll` calls on the controller token entirely, preventing bulk operator approval from becoming a root-access vector.

---

## MEDIUM - Underspecified or Ambiguous

### M1. Validator execution path is unspecified
**Sources:** T, P, V, CX-A, CX-S, CP

[x] Fix: Narrow the language to match the actual interface (signature validation only, plus optional ERC-4337).

### M3. controlVersion vs transferApprovalVersion asymmetry
**Sources:** CP

[x] Fix: Add an explicit `resetDelegations(tokenId)` action that increments `controlVersion` without transferring the NFT, so owners can invalidate validators when they only want to rotate delegated authority.

### M4. Deployment semantics contradiction
**Sources:** CX-S

[x] Fix: Remove the "MAY exist before" language from the definitions and add a separate "Counterfactual Addresses" informational subsection explaining that the address is deterministic and predictable but the NFT and account code only exist after atomic deployment.

### M6. Lock delay creates ambiguous state for `isLocked`
**Sources:** T, AF

The earlier draft had four actual states (locked, unlocking, unlocked, locking) but `isLocked()` returned a binary bool. UX ambiguity during delay periods. The earlier model was also awkward with `ERC-5192`: if transferability changed automatically when time elapsed, there might be no transaction at the exact moment the binary state flipped, so the matching `Locked` / `Unlocked` event could not be emitted at the true transition point.

[x] Fix: Remove `lockDelay`; make `lock()` immediate and make post-transfer relock immediate. Use explicit `proposeUnlock()` -> pending -> `completeUnlock()` so `Unlocked` is emitted on the transaction that actually makes the token transferable, with `UnlockProposed` and `UnlockCancelled` for pending-state visibility. Define `locked()` to remain `true` during pending or ready-but-not-completed unlock and add `unlockReadyAt(tokenId)` plus `unlockDelayOf(tokenId)` for wallet introspection.

### M8. ERC-1271 binding scheme is not canonical enough for interoperability
**Sources:** AF

[x] Fix: Standardize the `ERC-1271` typed-signature path around `EIP-712` + `ERC-5267` domain discovery + `ERC-7739` defensive rehashing, with one canonical account domain that binds account address, chain id, controller token, tokenId, and current control version.

---

## LOW / INFORMATIONAL

### L4. Batch-active guard skip for codeless accounts + SELFDESTRUCT
**Sources:** T

[x] Fix: Require compliant accounts to be non-self-destructible and require the controller token to treat missing code at a previously deployed account as a fault state that blocks transfer until canonical redeployment or explicit recovery.

### L6. EXTCODEHASH check has edge cases for non-existent vs. codeless accounts
**Sources:** AF (2026-04-06)

Per EIP-1052: `EXTCODEHASH` returns `0x0` for non-existent accounts and `keccak256("")` for existing-but-codeless accounts. If the execution-active transfer guard checks only `EXTCODEHASH != keccak256("")`, a never-touched address returns `0x0`, which does not match, so the guard falls through to calling `isExecutionActive()` via `STATICCALL` on a codeless address — returning empty data rather than reverting. The spec's prose "has empty code" was ambiguous about which EVM opcode to use.

[x] Fix: Specify a double `EXTCODEHASH` check as the normative code-presence guard: revert if `EXTCODEHASH` is `keccak256("")` (existing but codeless) OR `0x0` (non-existent per EIP-1052). This covers both edge cases in a single opcode without needing `EXTCODESIZE`.

### L7. CREATE2 address collision / cross-chain nonce divergence
**Sources:** T, P, V

[x] Fix: Make user-salt mode the only cross-chain-stable mode, and explicitly document that nonce-based mode provides no cross-chain address guarantees and is intended only for fresh per-chain addresses.

### L11. ERC-6551 comparison needs more depth
**Sources:** V

[x] Fix: Expand the rationale with a terse `Relationship to ERC-6551` subsection that includes a compact comparison table, states why the draft is not merely a constrained `ERC-6551` profile, and answers the migration question directly.

#### Fix choices by preference
1. Expand the rationale with a comparison table covering invariants, deployment model, transfer semantics, account discovery, migration path, and why this design is not just a constrained `ERC-6551` profile.
2. Address migration head-on with a concrete answer on whether an ERC-6551 account can become an ERC-XXXX account or whether accounts must be re-created.
3. Add a short "When to Use Which" decision guide covering the main scenarios where ERC-6551 or ERC-XXXX is the better fit.
4. Add a "Relationship to ERC-6551" subsection in the rationale listing the three key divergences (dedicated vs arbitrary NFT, fixed vs registry-based derivation, mandatory execution interface) and stating whether a 6551 account can also be compliant under this ERC.
5. Add a formal invariant comparison showing where the two standards' guarantees align and where they conflict.
6. Frame the discussion as intellectual lineage, explaining which lessons from ERC-6551 drove this narrower design.
7. Publish a standalone comparison appendix with side-by-side columns and a clear statement on whether migration from ERC-6551 is possible or whether accounts must be re-created.
8. Build and document an ERC-6551 compatibility adapter as an optional companion artifact rather than a primary spec fix.

### L14. "Asset basket" framing invites regulatory scrutiny
**Sources:** V, SEC Release No. 33-11412 (March 23, 2026)

[x] Fix: Reframe the draft away from "asset basket" language and add a `Regulatory considerations` subsection that states the ERC is intended as account-control infrastructure, not a pooled vehicle; clarifies that economic reality, not labels, governs the analysis; and warns that fractionalization or marketing as a managed product / investment wrapper / curated portfolio could change the legal characterization and may require counsel.

#### Fix choices by preference
1. Reframe the language throughout from "asset basket" toward "account control transfer," "control rotation," "wallet handoff," or "self-custodied account transfer."
2. Add a regulatory-distinction note that the ERC transfers control over a smart-contract account and does not itself create a claim on issuer revenues, pooled assets, managed profits, or a business enterprise.
3. Add a short legal-risk disclaimer noting that marketing or deploying this standard as a managed product, investment wrapper, or curated portfolio could change the analysis and may require counsel.
4. Rebalance the framing to emphasize programmable execution, batching, key rotation, and account portability as the primary use cases, with transferability as a control feature rather than an investment thesis.
5. Add a single sentence to Security Considerations or a short Legal Considerations subsection stating that economic reality, not labels, will govern whether a particular deployment is analyzed as a securities transaction.
6. Avoid language that implies passive return, packaged exposure, or promoter-managed appreciation of the underlying assets held by the account.
7. Allow permanently locked or non-transferable deployments as an opt-in reduction of regulatory surface.

### L15. MUST/SHOULD/MAY mixing
**Sources:** V

[x] Fix: Move non-normative wallet guidance out of the core normative `Specification` and into `Security Considerations`, keeping the protocol requirements in `Specification` and making the normative surface cleaner. The standard ERC template already supplies the RFC 2119 / RFC 8174 interpretation boilerplate, so the issue was keyword placement and scope, not missing definitions.

### L18. Missing reference links
**Sources:** CP

[x] Fix: Add an ERC-local bibliography appendix with full titles, authors, and publication metadata so readers can identify the references without external hyperlinks.

### L20. Cross-chain identity
**Sources:** V

[x] Fix: Define cross-chain control as out of scope: user-salt stabilises deployment address only, not authority/control semantics across chains; note keyless deployment and EIP-7997 deterministic factory predeploy as possible bootstrap paths where supported.

---

## Summary Table

| # | Issue | Severity | Sources | Status |
|---|-------|----------|---------|--------|
| H1 | TSTORE revert underflow in nested batches | High | CP | **Resolved** |
| H2 | Mid-execute control rotation (no guard on plain execute) | High | CX-A, CP | **Resolved** |
| H3 | Sell-and-drain via missing transfer freeze window | High | CP | **Resolved** |
| H4 | Sponsored execution MUST but no compliant path | High | CX-A, CX-S | **Resolved** |
| H6 | NFT theft = account takeover at scale | High | P, V | **Resolved** |
| M1 | Validator execution path unspecified | Medium | All 6 | **Resolved** |
| M3 | controlVersion / transferApprovalVersion asymmetry | Medium | CP | **Resolved** |
| M4 | Deployment semantics contradiction | Medium | CX-S | **Resolved** |
| M6 | Lock delay creates ambiguous isLocked state | Medium | T, AF | **Resolved** |
| M8 | ERC-1271 binding scheme not canonical enough | Medium | AF | **Resolved** |
| L4 | Batch-active guard + SELFDESTRUCT | Low | T | **Resolved** |
| L6 | EXTCODEHASH edge case for non-existent accounts | Low | AF | **Resolved** |
| L7 | CREATE2 collision / cross-chain nonce | Low | T, P, V | **Resolved** |
| L11 | ERC-6551 comparison depth | Low | V | **Resolved** |
| L14 | Regulatory surface | Low | V, SEC 33-11412 | **Resolved** |
| L15 | MUST/SHOULD/MAY mixing | Low | V | **Resolved** |
| L18 | Missing reference links | Low | CP | **Resolved** |
| L20 | Cross-chain identity | Low | V | **Resolved** |
