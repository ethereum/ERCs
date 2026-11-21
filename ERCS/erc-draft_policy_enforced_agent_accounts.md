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

This ERC defines how anyone can check, from the chain alone, whether a smart account (typically one operated by an autonomous agent) can only transact with the approval of an external **policy signer**; which policy that signer currently enforces and whether a looser one is waiting to take effect; why a transaction was refused, using a shared list of reason codes; and whether a signed **decision receipt** is genuine. It specifies a read interface discoverable through [ERC-165](./eip-165.md), served by the account itself or by a singleton registry for existing accounts, a set of events, a hash commitment to an off-chain policy document, an append-only list of reason codes, and an [EIP-712](./eip-712.md) receipt format. It does not specify how a policy is evaluated or enforced.

## Motivation

Agents increasingly hold accounts that move real funds. A common protection is an external policy signer: the account (for example a 2-of-3 multisig) cannot move funds unless an enforcer co-signs, and the enforcer co-signs only what the agent's policy allows. Apps, wallets, lenders and marketplaces that interact with such an agent have no standard way to tell:

1. that the account is protected at all, and by whom;
2. which limits apply now, and whether a weaker policy has been scheduled (a common attack is to loosen limits quietly before draining an account);
3. why an action was refused, in terms that do not depend on the enforcer's vendor;
4. whether a "this transaction was approved under policy X" claim is genuine.

Existing work covers neighboring problems. [ERC-7579](./eip-7579.md) and [ERC-7780](./eip-7780.md) define modules and policy modules that enforce inside an account; [ERC-7710](./eip-7710.md) defines delegation with caveat enforcers; [ERC-8004](./eip-8004.md) covers agent identity and reputation; [ERC-8226](./eip-8226.md) defines a registry of mandates for regulated assets; [ERC-8196](./eip-8196.md) defines a wallet that executes only with proof of policy compliance. None of them exposes an external policy signer, a commitment to its off-chain policy, a pending loosening with its effective time, an enforcer-independent reason list, or verifiable decision receipts. This ERC is a read-and-evidence layer that works on top of any of those enforcement mechanisms.

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
    }

    struct PolicyCommitment {
        bytes32 policyHash;     // keccak256 of the policy document's RFC 8785 canonical JSON
        uint64 version;         // strictly increasing per account
        uint64 effectiveAt;     // block timestamp from which the policy decides
        string policyURI;       // where the document can be fetched; MAY be empty
        string schemaURI;       // the document's format
    }

    event SignersDeclared(address indexed account, address policySigner, address publisher, address receiptSigner);
    event PolicyActivated(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI);
    event PolicyPending(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI);
    event PolicyCancelled(address indexed account, bytes32 indexed policyHash, uint64 version, string reason);
    event EmergencyStop(address indexed account, string reason);
    event EmergencyStopLifted(address indexed account);
    event MandateSet(address indexed account, string mandateURI, bytes32 configHash);

    function policySigner(address account) external view returns (Signers memory);
    function signersAt(address account, uint64 timestamp) external view returns (Signers memory);
    function policyOf(address account) external view returns (PolicyCommitment memory);
    function pendingPolicyOf(address account) external view returns (bool exists, PolicyCommitment memory);
    function mandateOf(address account) external view returns (string memory mandateURI, bytes32 configHash);
    function isStopped(address account) external view returns (bool);
}
```

The ERC-165 interface identifier is `0xcc16d336`.

### Discovery

A reader MUST first call `supportsInterface(0xcc16d336)` on the account. If it returns true, the account serves the interface itself, and every function is called with the account's own address. Otherwise the reader MUST use a registry implementing the interface and the reader's trust in that registry's address. The reference registry is deployed with the deterministic deployment proxy `0x4e59b44847b379578588920cA78FbF26c0B4956C`, salt `keccak256("policy-enforced-accounts registry v1")`, so that it has the same address on every chain where it is deployed.

### Registry write rules

A registry:

- MUST let an account set its signers only from the account itself (`msg.sender == account`), and MUST keep the history needed to answer `signersAt`.
- MUST accept commitments, stop flags and mandate references for an account only from that account's current `publisher`, and only while its `policySigner` is not zero.
- MUST NOT let any caller change another account's data.
- MUST reject an activation whose version is lower than the current one, or equal with a different hash.
- MUST only accept a pending change whose `effectiveAt` is in the future and whose version is higher than the current one; MUST emit `PolicyCancelled` when a pending change is replaced, superseded by a newer activation, or canceled; and MUST NOT allow canceling a pending change after its `effectiveAt`.
- MUST return a pending change from `policyOf` once its `effectiveAt` has passed, even if the publisher has not yet confirmed it with an activation. `pendingPolicyOf` MUST then return `exists = false`.
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
  name = "PolicyDecisionReceipt", version = "1", verifyingContract = the registry (or the account, if it serves the interface)

Decision(address account,bytes32 intentHash,uint8 decision,bytes32 reasonCode,bytes32 detailCode,bytes32 policyHash,uint64 policyVersion,uint64 issuedAt,uint64 expiresAt,bytes32 decisionId)
  decision: 0 = ALLOW, 1 = DENY, 2 = REVIEW

intentHash = keccak256(abi.encode(
  keccak256("Intent(uint256 chainId,address account,address target,uint256 value,bytes32 dataHash)"),
  chainId, account, target, value, keccak256(data)))
```

A verifier:

- MUST use a registry (or account) address it trusts, and MUST reject a receipt whose `verifyingContract` differs;
- MUST check `issuedAt <= expiresAt` and that the receipt has not expired, except when auditing a past decision;
- MUST check that the signer is the account's `receiptSigner`, by `ecrecover` for an EOA or [ERC-1271](./eip-1271.md) `isValidSignature` for a contract;
- SHOULD reject a receipt from a signer that has since been rotated out, unless auditing a past decision, in which case it MUST use `signersAt(account, issuedAt)`;
- MUST check `intentHash` against the transaction it is judging, when there is one.

A receipt is evidence of what the enforcer decided, not an authorization to execute.

## Rationale

- **Read-only, enforcement-agnostic.** Enforcement already has several designs (co-signers, validation modules, guards, token gates). A shared read layer lets readers treat them alike without forcing one enforcement design.
- **A registry for existing accounts.** Most deployed agent accounts are standard multisigs that cannot add functions. A registry keyed by account, written only by the account (signers) and its publisher (commitments), serves them without upgrades. The account's own `declare` call is what binds a signer to it.
- **Hash commitments, not on-chain policies.** Policies can be large and private. Committing a hash keeps chain costs constant, keeps private policies private, and still lets anyone holding the document prove which one applied.
- **Pending changes are public with their time.** Loosening limits is the step before most account drains. Publishing `effectiveAt` gives watchers time to react, and the registry applies the change by time alone, so readers stay correct even if the publisher is slow.
- **Separate publisher and receipt keys.** The co-signer key that moves funds never needs to sign anything else. A publisher or receipt key that leaks cannot move funds.
- **Standard plus detail codes.** Readers act on the standard code; enforcers keep their precise codes in `detailCode`.

## Backwards Compatibility

No backward compatibility issues found. The interface is new and read-only for consumers. Accounts opt in by calling the registry; nothing changes for accounts that do not.

## Test Cases

`../assets/eip-draft_policy_enforced_agent_accounts/vectors.json` contains policy documents with their canonical JSON and `policyHash`, intents with their `intentHash`, and receipts with their EIP-712 digest and signature from a published test-only key. The vectors are checked by an independent TypeScript implementation and by Solidity (`PolicyVectors.t.sol`), and include the RFC 8785 section 3.2.2 example.

## Reference Implementation

In `../assets/eip-draft_policy_enforced_agent_accounts/`:

- `IPolicyEnforcedAccount.sol`: the interface;
- `PolicyEnforcedRegistry.sol`: the registry, with no owner and no upgrade path, deployed on mainnet chain 4663 at `0x20D6B38B47F7cb765A2318a1f318ed54a6f87e92` with verified source;
- `PolicyDecisionReceipt.sol`: pure helpers to verify a receipt on chain;
- `PolicyEnforcedRegistry.t.sol`, `PolicyVectors.t.sol`: tests;
- `client/`: a dependency-light TypeScript reader and receipt verifier (also published as the JavaScript package `policy-enforced-accounts`), and `independent-read.mjs`, a script that reads an account's signer, policy and pending state, fetches and checks the policy, and verifies a receipt using only the chain.

## Security Considerations

- **Fail closed.** If an enforcer cannot read its policy, its state or a required dependency, it SHOULD refuse (`POLICY_UNAVAILABLE`, `STATE_UNAVAILABLE`, `DEPENDENCY_UNAVAILABLE`), never allow by default. Readers SHOULD treat an unreadable registry as "unknown", not as "not enforced" or "enforced".
- **What this standard does not guarantee.** A commitment proves what the publisher stated, not that the policy signer follows it. Receipts and audits are evidence that can expose a signer that does not. The standard does not say whether a policy is safe, and `policySigner` being set does not prove the account's configuration actually requires that signer. Readers SHOULD also verify the account's configuration (for example its owners, threshold, modules and guard) for the account type they support.
- **Loosening delays.** Readers SHOULD alert on `PolicyPending` events and SHOULD compare a pending policy with the active one. A zero or very short delay removes this protection.
- **Key compromise.** A leaked publisher key can post false commitments, and a leaked receipt key can sign false receipts; neither can move funds. The account recovers by calling `declare` with new keys. Verifiers SHOULD reject receipts from rotated-out keys except in audits.
- **Replay.** Receipts are bound to the chain, the registry, the account, the intent and a `decisionId`, and expire.
- **Cross-chain.** Each chain has its own commitments. A receipt for one chain is invalid on another because the domain includes `chainId`.
- **Lagging commitments.** A publisher may confirm a change late. The registry applies pending changes by time, and readers SHOULD compare `effectiveAt` with the current block time.
- **Untrusted locations.** `policyURI` is chosen by the publisher. Fetchers SHOULD allow only HTTPS, refuse local and private hosts, bound size and time, and always check the hash.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
