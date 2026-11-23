---
eip: TBD
title: Policy-Enforced Agent Accounts
description: Discover an account's external policy signer, its committed policy, shared reason codes and signed decision receipts.
author: Palisec (@palisec-dev)
discussions-to: https://ethereum-magicians.org/t/draft-erc-policy-enforced-agent-accounts/30467
status: Draft
type: Standards Track
category: ERC
created: 2026-11-21
requires: 165, 712, 1271
---

## Abstract

This ERC defines how anyone can check, from the chain alone, whether a smart account (typically one operated by an autonomous agent) can only transact with the approval of an external **policy signer**; which policy that signer currently enforces and whether a different one is waiting to take effect; why a transaction was refused, using a shared list of reason codes; and whether a signed **decision receipt** is genuine and may be acted on. It specifies a read interface discoverable through [ERC-165](./eip-165.md), served by the account itself or by a singleton registry for existing accounts, a set of events, time rules for changes, a hash commitment to an off-chain policy document, an append-only list of reason codes, and an [EIP-712](./eip-712.md) receipt format. It does not specify how a policy is evaluated or enforced.

## Motivation

Agents increasingly hold accounts that move real funds. A common protection is an external policy signer: the account (for example a 2-of-3 multisig) cannot move funds unless an enforcer co-signs, and the enforcer co-signs only what the agent's policy allows. Apps, wallets, lenders and marketplaces that interact with such an agent have no standard way to tell:

1. that the account is protected at all, and by whom;
2. which limits apply now, and whether a weaker policy has been scheduled (a common attack is to loosen limits quietly before draining an account);
3. why an action was refused, in terms that do not depend on the enforcer's vendor;
4. whether a "this transaction was approved under policy X" claim is genuine, and still valid now.

Existing work covers neighboring problems. [ERC-7579](./eip-7579.md) and [ERC-7780](./eip-7780.md) define modules and policy modules that enforce inside an account; [ERC-7710](./eip-7710.md) defines delegation with caveat enforcers; [ERC-8004](./eip-8004.md) covers agent identity and reputation; [ERC-8226](./eip-8226.md) defines a registry of mandates for regulated assets; [ERC-8196](./eip-8196.md) defines a wallet that executes only with proof of policy compliance. None of them exposes an external policy signer, a commitment to its off-chain policy, a pending change with its effective time, an enforcer-independent reason list, or verifiable decision receipts. This ERC is a read-and-evidence layer that works on top of any of those enforcement mechanisms.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

```solidity
interface IPolicyEnforcedAccount {
    struct Signers {
        address policySigner;   // the external co-signer that enforces the policy; zero = not enforced
        address publisher;      // the only address that may post commitments for the account
        address receiptSigner;  // signs decision receipts (EOA, or an ERC-1271 contract)
        uint64 since;           // block timestamp from which this set applies
        uint32 minDelay;        // seconds every publisher change and every later signer change waits
        uint8 signerType;       // how the policy signer is wired in: 1 co-signer in the signature path,
                                // 2 validator module, 3 guard or hook, 4 other; 0 only when not enforced
    }

    struct PolicyCommitment {
        bytes32 policyHash;     // keccak256 of the policy document's RFC 8785 canonical JSON
        uint64 version;         // strictly increasing per account
        uint64 effectiveAt;     // block timestamp from which the policy decides
        string policyURI;       // where the document can be fetched; MAY be empty
        string schemaURI;       // the document's format
    }

    event SignersDeclared(address indexed account, address policySigner, address publisher, address receiptSigner, uint32 minDelay, uint8 signerType);
    event SignersPending(address indexed account, address policySigner, address publisher, address receiptSigner, uint32 minDelay, uint8 signerType, uint64 effectiveAt);
    event SignersCancelled(address indexed account, address policySigner, address publisher, address receiptSigner, uint64 effectiveAt);
    event PolicyActivated(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI);
    event PolicyPending(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI);
    event PolicyCancelled(address indexed account, bytes32 indexed policyHash, uint64 version, string reason);
    event EmergencyStop(address indexed account, string reason);
    event EmergencyStopLifted(address indexed account);
    event MandateSet(address indexed account, string mandateURI, bytes32 configHash);

    function policySigner(address account) external view returns (Signers memory);
    function signersAt(address account, uint64 timestamp) external view returns (Signers memory);
    function pendingSignersOf(address account) external view returns (bool exists, Signers memory);
    function policyOf(address account) external view returns (PolicyCommitment memory);
    function pendingPolicyOf(address account) external view returns (bool exists, PolicyCommitment memory);
    function mandateOf(address account) external view returns (string memory mandateURI, bytes32 configHash);
    function isStopped(address account) external view returns (bool);
}
```

The ERC-165 interface identifier is `0x7e0f19f9`.

All reads follow block time: `policySigner` and `signersAt` return a pending signer set once its `since` has passed, and `policyOf` returns a pending policy once its `effectiveAt` has passed.

### Discovery

A reader MUST first call `supportsInterface(0x7e0f19f9)` on the account. If it returns true, the account serves the interface itself, and every function is called with the account's own address. Otherwise the reader MUST use a registry implementing the interface and the reader's trust in that registry's address. The reference registry is deployed with the deterministic deployment proxy `0x4e59b44847b379578588920cA78FbF26c0B4956C`, salt `keccak256("policy-enforced-accounts registry v2")`, so that it has the same address on every chain where it is deployed.

### Registry write rules

A registry:

- MUST let an account set its signers only from the account itself (`msg.sender == account`), and MUST keep the history needed to answer `signersAt`.
- MUST apply an account's first signer set at once, and a set declared while `policySigner` is zero at once. Any other change of the signers, including a lower `minDelay`, MUST apply only `minDelay` seconds later (the `minDelay` in effect when it is requested), MUST emit `SignersPending`, and MUST be cancelable by the account until then (`SignersCancelled`). A newer request MUST replace a pending one, emitting `SignersCancelled`. Clearing the signers to all zeros MUST apply at once: it only removes the claim of enforcement.
- MUST accept commitments, stop flags and mandate references for an account only from the account's `publisher` in effect, and only while its `policySigner` is not zero; the account itself MAY also activate a policy, cancel a pending one and set the stop.
- MUST accept from the publisher a new policy only as a pending change whose `effectiveAt` is in the future and at least `minDelay` after the current block time, and whose version is higher than the current one. From the publisher, an activation MUST only confirm a pending change whose `effectiveAt` has passed, and MUST keep its `effectiveAt`.
- MAY accept from the account itself an activation of a higher version that decides at once.
- MUST reject an activation whose version is lower than the current one, or equal with a different hash.
- MUST emit `PolicyCancelled` whenever a pending change is removed before it takes effect: replaced, superseded by an activation, or canceled. It MUST NOT allow canceling a pending change after its `effectiveAt`.
- MUST return a pending change from `policyOf` once its `effectiveAt` has passed, even if nobody has confirmed it, and MUST NOT lose it when a newer change is posted. `pendingPolicyOf` MUST then return `exists = false`.
- MUST let the publisher or the account engage the emergency stop at once.
- SHOULD bound `minDelay` (the reference registry: 30 days), so that an account cannot lock its own signers away.
- SHOULD have no owner, no upgrade path and hold no funds.

Accounts that implement the interface themselves MUST follow the same rules for their own data.

### Policy document and hash

`policyHash` MUST be `keccak256` of the UTF-8 bytes of the policy document serialized as RFC 8785 canonical JSON. `schemaURI` identifies the document's format. A conforming document SHOULD express at least the following common core, under these names: `account` (`chain_id`, `address`), `version`, a per-transaction value cap, a rolling budget and its window, a contract allowlist with function selectors, a deny list, a human-approval threshold, the loosening delay, and `failure_mode` (`"closed"`). Enforcers MAY use richer formats; `schemaURI` tells readers which.

If `policyURI` is not empty, it MUST serve the exact document over HTTPS, and a reader MUST check that the fetched document hashes to `policyHash` before relying on it. An empty `policyURI` means the document is private: whoever holds it can still prove which policy applied.

### Reason codes

A reason code is an ASCII identifier, right-padded with zero bytes to `bytes32`. `bytes32(0)` (`NONE`) means allowed. The list is append-only: an identifier MUST NOT be removed, reused or given a different meaning.

| Code | Meaning |
|---|---|
| `TARGET_NOT_ALLOWED` | The target address is not allowed by the policy. |
| `METHOD_NOT_ALLOWED` | The function selector is not allowed on this target. |
| `DENY_RULE` | An explicit deny rule matched. |
| `OVER_TX_CAP` | The transaction exceeds the per-transaction cap. |
| `OVER_BUDGET` | The transaction exceeds the rolling or cumulative budget. |
| `OVER_LIMIT` | A value limit is exceeded; the enforcer does not distinguish which. |
| `RATE_LIMITED` | Too many requests in the policy's window. |
| `COOLDOWN_OR_LOOP` | The same intent or calldata was repeated within the waiting period. |
| `REPLAY` | The request or authorization was already used, or has expired. |
| `PAUSED` | The agent or account is paused, or the emergency stop is engaged. |
| `HUMAN_APPROVAL_REQUIRED` | A human must approve this exact operation first. |
| `ASSET_UNSAFE` | Simulation shows an unsafe asset outcome. |
| `APPROVAL_RISK` | An unlimited or oversized token approval to a spender that is not allowed. |
| `SIMULATION_UNAVAILABLE` | A required simulation could not run. |
| `FEE_UNAVAILABLE` | The fee could not be estimated or is invalid. |
| `POLICY_UNAVAILABLE` | No valid active policy. |
| `STATE_UNAVAILABLE` | The enforcer's authoritative state could not be read. |
| `DEPENDENCY_UNAVAILABLE` | An external dependency the policy requires could not be read. |
| `NOT_RECOVERABLE` | The policy requires a recovery setup the account does not meet. |
| `WRONG_CHAIN` | The chain or its infrastructure is not available for this request. |
| `ATTESTATION_FAILED` | The signer's attestation could not be verified. |
| `UNAUTHORIZED` | The requester is not authenticated or not allowed to ask. |
| `INVALID_REQUEST` | The request is malformed. |
| `OTHER` | Another reason; see the detail code. |

Where meanings overlap, identifiers follow the names used by [ERC-8226](./eip-8226.md) (for example `OVER_TX_CAP`). Enforcer-specific codes MUST be carried separately, as a `detailCode` of the form `<namespace>:<code>` (for example `palisec:PS_BUDGET_001`), so that the standard code stays enforcer-independent.

### Decision receipts

A receipt is an EIP-712 signature by the account's `receiptSigner` over:

```
EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)
  name = "PolicyDecisionReceipt", version = "2", verifyingContract = the registry (or the account, if it serves the interface)

Decision(address account,bytes32 intentHash,uint8 decision,bytes32 reasonCode,bytes32 detailCode,bytes32 policyHash,uint64 policyVersion,uint64 issuedAt,uint64 expiresAt,bytes32 decisionId)
  decision: 0 = ALLOW, 1 = DENY, 2 = REVIEW

intentHash = keccak256(abi.encode(
  keccak256("Intent(uint256 chainId,address account,address target,uint256 value,bytes32 dataHash,uint8 operation)"),
  chainId, account, target, value, keccak256(data), operation))
  operation: 0 = call, 1 = delegatecall; for ERC-7579 accounts, the call type byte of the execution mode
```

Any verifier, including one auditing a past decision:

- MUST use a registry (or account) address it trusts, and MUST reject a receipt whose `verifyingContract` differs;
- MUST check `issuedAt <= expiresAt` and that the receipt has not expired, except when auditing a past decision;
- MUST check that the signer is the account's `receiptSigner`, by `ecrecover` for an EOA or [ERC-1271](./eip-1271.md) `isValidSignature` for a contract;
- SHOULD reject a receipt from a signer that has since been rotated out, unless auditing a past decision, in which case it MUST use `signersAt(account, issuedAt)`;
- MUST check `intentHash` against the transaction it is judging, when there is one.

A verifier that acts on an `ALLOW` (as a gate for its own action, not as an audit) MUST also, at the time it acts:

- check that `policyHash` and `policyVersion` equal the account's current `policyOf`;
- check that `isStopped(account)` is false;
- record `decisionId` and refuse a second use of the same `decisionId`, with a single atomic step (for example an insert that fails if the identifier exists).

A receipt is evidence of what the enforcer decided, not an authorization to execute.

## Rationale

- **Read-only, enforcement-agnostic.** Enforcement already has several designs (co-signers, validation modules, guards, token gates). A shared read layer lets readers treat them alike without forcing one enforcement design. `signerType` tells a reader which configuration to check.
- **A registry for existing accounts.** Most deployed agent accounts are standard multisigs that cannot add functions. A registry keyed by account, written only by the account (signers) and its publisher (commitments), serves them without upgrades. The account's own `declare` call is what binds a signer to it.
- **Time rules instead of tightening and loosening.** A registry stores hashes and cannot tell whether a new policy is stricter. A rule based on time has no such gap: whatever the publisher posts waits `minDelay`, in public, with its effective time. An enforcer can still apply a tightening off chain at once, because stricter is always safe; the registry shows it after the delay, and until then receipts carry the newer version, which a use-time verifier refuses (it fails closed). The account itself may activate at once, because its owners could change its signers anyway.
- **Signer changes wait.** A new publisher could post any policy, so replacing the signers is at least as strong as loosening the policy, and waits the same delay. Clearing is the exception: it only withdraws the claim of enforcement, which can mislead nobody.
- **The account can stop itself.** The stop only restricts. Letting the account engage it gives a fast answer to a leaked publisher or receipt key while a rotation waits its delay.
- **Hash commitments, not on-chain policies.** Policies can be large and private. Committing a hash keeps chain costs constant, keeps private policies private, and still lets anyone holding the document prove which one applied.
- **The operation is part of the intent.** A call and a delegatecall to the same target with the same data have very different effects. Binding the operation keeps one from standing for the other.
- **Separate publisher and receipt keys.** The co-signer key that moves funds never needs to sign anything else. A publisher or receipt key that leaks cannot move funds.
- **Standard plus detail codes.** Readers act on the standard code; enforcers keep their precise codes in `detailCode`.

## Backwards Compatibility

The interface is new and read-only for consumers. Accounts opt in by calling the registry; nothing changes for accounts that do not.

An earlier draft of this ERC (interface `0xcc16d336`, receipt domain version `"1"`, intent without `operation`) had a reference registry deployed at `0x20D6B38B47F7cb765A2318a1f318ed54a6f87e92` on chain 4663. It is unchanged and readable, and receipts issued under it can still be audited with domain version `"1"`. They MUST NOT be acted on as a gate, because their intent does not bind the operation.

## Test Cases

`../assets/eip-draft_policy_enforced_agent_accounts/vectors.json` contains policy documents with their canonical JSON and `policyHash`, intents with their `intentHash` (including the same call as a call and as a delegatecall), and receipts with their EIP-712 digest and signature from a published test-only key. The vectors are checked by an independent TypeScript implementation and by Solidity (`PolicyVectors.t.sol`), and include the RFC 8785 section 3.2.2 example. `PolicyEnforcedRegistry.t.sol` tests each time rule, next to the earlier draft's registry for comparison.

## Reference Implementation

In `../assets/eip-draft_policy_enforced_agent_accounts/`:

- `IPolicyEnforcedAccount.sol`: the interface;
- `PolicyEnforcedRegistry.sol`: the registry, with no owner and no upgrade path, deployed on mainnet chain 4663 at `0xCa3bAE26d29a3A2cED7B87Fa996ca4C44367448d` with verified source;
- `PolicyDecisionReceipt.sol`: pure helpers to verify a receipt on chain;
- `PolicyEnforcedRegistry.t.sol`, `PolicyVectors.t.sol`: tests;
- `v1/`: the earlier draft's contracts, for the comparison tests;
- `client/`: a dependency-light TypeScript reader and receipt verifier (also published as the JavaScript package `policy-enforced-accounts`), and `independent-read.mjs`, a script that reads an account's signers, delay, policy and pending state, fetches and checks the policy, and verifies a receipt using only the chain.

## Security Considerations

- **Fail closed.** If an enforcer cannot read its policy, its state or a required dependency, it SHOULD refuse (`POLICY_UNAVAILABLE`, `STATE_UNAVAILABLE`, `DEPENDENCY_UNAVAILABLE`), never allow by default. Readers SHOULD treat an unreadable registry as "unknown", not as "not enforced" or "enforced".
- **Scope of a commitment.** A commitment covers only the actions that need the policy signer. Standing authority does not: token allowances and permits, operator approvals (for example [ERC-721](./eip-721.md) and [ERC-1155](./eip-1155.md) `setApprovalForAll`), modules and executors, guards and hooks, fallback handlers, and an [EIP-7702](./eip-7702.md) delegation target can all move funds without it. Readers MUST check standing authority separately before relying on a commitment. For a Safe: its owners, threshold, enabled modules, guard and fallback handler. For an ERC-7579 account: its installed validators, executors, hooks and fallbacks. For an EIP-7702 account: its delegation target. For any account: the token allowances and operator approvals it has granted.
- **What this standard does not guarantee.** A commitment proves what the publisher stated, not that the policy signer follows it. Receipts and audits are evidence that can expose a signer that does not. The standard does not say whether a policy is safe, and `policySigner` being set does not prove the account's configuration actually requires that signer.
- **Delays.** Readers SHOULD alert on `PolicyPending` and `SignersPending` events, and SHOULD compare a pending policy with the active one. A `minDelay` of zero is allowed but removes this protection; readers SHOULD flag it.
- **Key compromise.** A leaked publisher key can post false commitments, and a leaked receipt key can sign false receipts; neither can move funds. False commitments wait `minDelay` in public. The account can engage the emergency stop at once and replace the keys with `declare`, which waits `minDelay`. Verifiers SHOULD reject receipts from rotated-out keys except in audits.
- **Replay.** Receipts are bound to the chain, the registry, the account, the intent (including the operation) and a `decisionId`, and expire. A verifier acting on a receipt also checks the current policy and stop, and accepts each `decisionId` once.
- **Cross-chain.** Each chain has its own commitments. A receipt for one chain is invalid on another because the domain includes `chainId`.
- **Lagging commitments.** A publisher may confirm a change late. The registry applies pending changes by time, and readers SHOULD compare `effectiveAt` with the current block time.
- **Untrusted locations.** `policyURI` is chosen by the publisher. Fetchers SHOULD allow only HTTPS, refuse local and private hosts, bound size and time, and always check the hash.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
