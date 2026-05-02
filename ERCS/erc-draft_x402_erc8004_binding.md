---
eip: <to be assigned>
title: x402 Payment Receipt Binding for ERC-8004 Agents
description: Standardized binding between x402 HTTP 402 payment receipts and ERC-8004 agent identity entries for verifiable agentic commerce
author: Hilal Agil (@hilarl) <hilal@tenzro.com>
discussions-to: https://ethereum-magicians.org/t/erc-x402-payment-receipt-binding-for-erc-8004-agents/<placeholder>
status: Draft
type: Standards Track
category: ERC
created: 2026-05-02
requires: 8004
---

## Abstract

This ERC defines a standardized binding between an x402 HTTP `402 Payment
Required` payment receipt and an ERC-8004 agent identity entry. It introduces
the `IPaymentReceiptBinding` interface — a new optional sub-registry contract
that maps a 32-byte canonical receipt hash to a 32-byte ERC-8004 `agentId`,
together with a normative off-chain JSON envelope that any client can verify
against the on-chain mapping. The binding lets a third party determine, given
only an x402 receipt, which on-chain agent paid, and conversely, given an
agent, which receipts that agent has paid. The mapping is intentionally
minimal: only the receipt hash and agent identifier are recorded on chain;
the receipt itself, the payer's wallet, and the payment asset remain off
chain or in the underlying x402 settlement transaction.

## Motivation

x402 ([coinbase/x402](https://github.com/coinbase/x402)) is an HTTP-based
machine payment scheme: a server returns `402 Payment Required` with a
challenge, the client returns a `Payment` header carrying a signed payment
authorization, and the server returns a receipt. x402 is silent on the
question of *agent identity* — the receipt proves a payment happened but
does not bind that payment to any persistent identity record.

ERC-8004 ([trustless agents](https://eips.ethereum.org/EIPS/eip-8004))
provides the inverse: an on-chain `IdentityRegistry`, `ReputationRegistry`,
and `ValidationRegistry` for agents, but it is silent on payments. An
ERC-8004 agent record carries a metadata URI but no notion of "this agent
paid for that resource."

The gap between these two standards is the load-bearing primitive for
*verifiable agentic commerce*:

1. A merchant accepting x402 payments from autonomous AI agents wants to
   record reputation against the *agent*, not against an ephemeral wallet
   address that an agent controller may rotate.
2. A reputation aggregator wants to weight ERC-8004 feedback by whether the
   feedback-giver actually paid for the underlying interaction (Sybil
   resistance).
3. A regulator or auditor wants to trace a payment receipt back to a
   persistent agent identity for AML/KYT purposes without requiring the
   merchant to have indexed every wallet that ever transacted.

Without a standard binding, every implementer invents an ad-hoc mapping —
typically encoded in opaque off-chain databases — defeating ERC-8004's goal
of cross-vendor agent portability.

This ERC standardizes the binding without prescribing a payment scheme,
ledger, or VM. The same on-chain interface works for any x402 receipt
(EVM, EVM-compatible L2s, or any chain that x402 accepts) and any
ERC-8004 deployment (mainnet, testnet, sidechain mirrors).

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in RFC 2119 and RFC 8174.

### 1. Canonical receipt hash

Given an x402 payment receipt — a JSON object as defined in the x402
`exact` scheme specification — the canonical receipt hash is computed as
follows:

```
canonical_bytes = JCS(receipt)             // RFC 8785 JSON Canonicalization
receipt_hash    = keccak256(canonical_bytes)
```

`receipt_hash` is a 32-byte value. JCS (JSON Canonicalization Scheme,
RFC 8785) is REQUIRED so that two implementations compute the same hash
from the same logical receipt regardless of key ordering or whitespace.

### 2. Agent identifier

`agentId` MUST be derived from the payer's W3C DID per ERC-8004:

```
agentId = keccak256(utf8(payer_did))
```

where `payer_did` is a string conforming to RFC 3986 with scheme `did:`
(any DID method). The DID identifies the *agent*, not the wallet that
signed the x402 payment. A controller MAY use any DID method (`did:web`,
`did:key`, `did:tenzro`, `did:pdis`, etc.); the binding specification is
DID-method-agnostic.

### 3. Binding contract interface

A conforming implementation MUST expose an on-chain contract or
precompile satisfying the following Solidity-style interface:

```solidity
interface IPaymentReceiptBinding {
    /// @notice Bind a payment receipt hash to an ERC-8004 agent.
    /// @dev Idempotent for the same (receiptHash, agentId) pair.
    ///      MUST revert if receiptHash is already bound to a different agentId.
    /// @param receiptHash keccak256(JCS(x402_receipt))
    /// @param agentId     keccak256(utf8(payer_did)) per ERC-8004
    /// @param attestationUri optional URI (ipfs://, https://, ar://) of the
    ///                       full off-chain binding attestation envelope
    function bindReceipt(
        bytes32 receiptHash,
        bytes32 agentId,
        string calldata attestationUri
    ) external;

    /// @notice Look up the agent bound to a given receipt hash.
    /// @return agentId zero-bytes32 if no binding exists.
    /// @return attestationUri the URI passed at bind time, or empty string.
    function getAgentByReceipt(bytes32 receiptHash)
        external
        view
        returns (bytes32 agentId, string memory attestationUri);

    /// @notice Enumerate receipts bound to a given agent.
    /// @return receiptHashes paginated list, ordered by bind time.
    function getReceiptsByAgent(
        bytes32 agentId,
        uint256 offset,
        uint256 limit
    ) external view returns (bytes32[] memory receiptHashes);

    /// @notice Emitted on every successful bind.
    event ReceiptBound(
        bytes32 indexed receiptHash,
        bytes32 indexed agentId,
        address indexed binder,
        string attestationUri
    );
}
```

The function selectors are deterministic per Solidity ABI rules:

| Function | Selector |
| :--- | :--- |
| `bindReceipt(bytes32,bytes32,string)` | first 4 bytes of `keccak256("bindReceipt(bytes32,bytes32,string)")` |
| `getAgentByReceipt(bytes32)` | first 4 bytes of `keccak256("getAgentByReceipt(bytes32)")` |
| `getReceiptsByAgent(bytes32,uint256,uint256)` | first 4 bytes of `keccak256("getReceiptsByAgent(bytes32,uint256,uint256)")` |

Implementations MUST compute and pin the selectors at deployment so that
calldata is byte-identical across deployments — the same calldata MUST work
against any conforming `IPaymentReceiptBinding` implementation, mirroring
ERC-8004's selector-stability invariant.

### 4. Authorization

`bindReceipt` MUST be callable only by:

1. The address that signed the x402 payment authorization (the
   `payer_address` recoverable from the receipt's signature, per the
   x402 scheme); or
2. An address pre-authorized by the agent's ERC-8004 entry — specifically,
   the `agentAddress` returned by `IdentityRegistry.getAgent(agentId)`.

This dual-authorization rule lets either the wallet that paid or the
ERC-8004-canonical agent address create the binding. Implementations MUST
revert with a typed error (`Unauthorized()`) for any other caller.

### 5. Off-chain binding attestation envelope

The optional `attestationUri` SHOULD point to a JSON document with the
following normative shape:

```json
{
  "version": "1",
  "receipt_hash": "0x<32-byte hex>",
  "agent_id": "0x<32-byte hex>",
  "payer_did": "did:<method>:<method-specific-id>",
  "x402_receipt": { /* the verbatim x402 receipt object */ },
  "binding_signature": {
    "alg": "EIP-712",
    "domain": {
      "name": "ERC-XXXX PaymentReceiptBinding",
      "version": "1",
      "chainId": <uint256>,
      "verifyingContract": "0x<20-byte hex>"
    },
    "types": {
      "Binding": [
        {"name": "receiptHash", "type": "bytes32"},
        {"name": "agentId", "type": "bytes32"},
        {"name": "payerDid", "type": "string"},
        {"name": "boundAt", "type": "uint64"}
      ]
    },
    "message": {
      "receiptHash": "0x...",
      "agentId": "0x...",
      "payerDid": "did:...",
      "boundAt": 1714627200
    },
    "signature": "0x<65-byte hex>"
  }
}
```

The envelope MUST be canonicalized with RFC 8785 (JCS) before signing.
The signature MUST be EIP-712 over the `Binding` struct, signed by the
key controlling the agent's ERC-8004 `agentAddress`.

### 6. Verification procedure

A client verifying a `(receipt, agent)` claim MUST perform these steps,
in order:

1. Compute `receipt_hash = keccak256(JCS(x402_receipt))`.
2. Compute `agent_id = keccak256(utf8(payer_did))`.
3. Call `getAgentByReceipt(receipt_hash)` on the
   `IPaymentReceiptBinding` contract; assert the returned `agentId`
   equals the locally computed `agent_id`.
4. Call `IdentityRegistry.getAgent(agent_id)` on the ERC-8004
   `IdentityRegistry`; assert the returned record exists and its
   `agentAddress` is non-zero.
5. If `attestationUri` is non-empty, fetch the envelope, recompute the
   EIP-712 digest, and verify the signature against the
   `agentAddress` from step 4.
6. (Optional) Verify the underlying x402 payment by performing the
   receipt verification defined in the x402 scheme that produced the
   receipt — typically an `eth_call` against the settlement contract or
   a re-verification against the facilitator.

If any step fails, the binding claim MUST be rejected.

### 7. Storage layout

Conforming contracts MUST store at minimum:

```
mapping(bytes32 => bytes32) receiptToAgent;          // receipt_hash → agent_id
mapping(bytes32 => bytes32[]) agentToReceipts;       // agent_id → [receipt_hash...]
mapping(bytes32 => string) receiptAttestationUri;    // receipt_hash → URI
```

Pagination over `agentToReceipts` MUST follow the `offset`/`limit`
parameters of `getReceiptsByAgent`.

## Rationale

### Why a new ERC vs. metadata in existing ERC-8004 entries

ERC-8004's `IdentityRegistry` carries a single `metadataUri` per agent.
Stuffing a list of receipt hashes into that URI conflates two distinct
concerns:

- **Identity metadata** changes rarely (DID document, capability list).
- **Payment activity** is append-only and high-volume.

A separate sub-registry keeps both lookups O(1), preserves ERC-8004's
small storage footprint, and avoids forcing every agent to publish a
mutable metadata document. Reputation aggregators routinely want to
enumerate receipts; on-chain pagination is dramatically cheaper than
re-fetching a JSON document per agent.

### Why receipt-hash binding vs. full receipt on chain

x402 receipts contain payer addresses, asset identifiers, and signature
material that may be sensitive (e.g., revealing wallet linkage). Storing
only a 32-byte hash on chain:

- Keeps gas cost flat regardless of receipt size.
- Lets implementers choose where to host the full receipt (IPFS,
  Arweave, an HTTPS server, or omitted entirely if the receipt was
  ephemeral).
- Does not leak the payer's wallet address to anyone holding the agent
  ID. Reverse correlation requires the off-chain receipt and is
  defeatable by classical mixing techniques.

### Compatibility with EIP-712, EIP-3009, EIP-4337

The binding signature in §5 is EIP-712-typed so that smart-contract
wallets, hardware wallets, and walletless agents using EIP-4337 paymasters
can produce signatures using existing tooling. The underlying x402
payment is independent — it can be settled via EIP-3009
(`transferWithAuthorization`), via an EIP-4337 user operation, or via a
plain ERC-20 transfer. The binding does not constrain the settlement
path.

### Multi-VM ledgers

One motivation came from multi-VM ledgers — chains where the same
underlying balance is reachable through more than one VM (EVM, SVM,
DAML/Canton). On such ledgers, an x402 payment MAY settle through a
non-EVM facade while the ERC-8004 entry lives on the EVM facade. The
hash-based binding works because `receipt_hash` is a JCS hash of the
JSON receipt, independent of which VM emitted it. This is one example
of why the binding is intentionally protocol-agnostic; it is not a
requirement for conforming implementations.

### Why DID-method-agnostic

Hard-coding a DID method (e.g., `did:eth`) would couple the spec to a
particular identity ecosystem. ERC-8004 already accepts any DID via the
metadata URI; this ERC preserves that property. Implementations that
want to restrict accepted DID methods (e.g., to `did:web` and `did:key`
only) MAY do so as policy, but conforming `IPaymentReceiptBinding`
contracts MUST NOT reject bindings on the basis of DID method alone.

### Why optional attestation URI

The on-chain binding (`receipt_hash → agent_id`) is sufficient for
ERC-8004 reputation and validation flows that just need to know "did
this agent pay?". The off-chain attestation envelope is only needed
when a verifier requires a portable, signed, audit-grade record (e.g.,
a regulator). Making it optional keeps the on-chain footprint minimal
for the majority of use cases.

## Backwards Compatibility

This ERC is fully additive:

- ERC-8004 `IdentityRegistry`, `ReputationRegistry`, and
  `ValidationRegistry` are unchanged.
- x402 receipts are unchanged.
- Existing agents and receipts can be retroactively bound by any
  authorized caller (§4) without reissuing identities or payments.

No prior standard defined this binding, so there is no on-chain or
off-chain state to migrate.

## Reference Implementation

Two reference implementations are cited:

1. **Native multi-VM implementation in `tenzro/tenzro-network`**.
   Tenzro Ledger exposes ERC-8004 system contracts at native precompile
   addresses `0x101a` (`IdentityRegistry`), `0x101b`
   (`ReputationRegistry`), and `0x101c` (`ValidationRegistry`). The
   selectors and ABI are byte-identical to a Solidity deployment, so
   calldata works against either surface. Source:
   <https://github.com/tenzro/tenzro-network/tree/main/crates/tenzro-identity/src/erc8004.rs>.
   The `IPaymentReceiptBinding` extension surface in that codebase
   shares the same selector-stability invariant.
2. **Companion x402 scheme implementation** at
   <https://github.com/coinbase/x402/pull/135> — the `exact` scheme
   variant that emits receipts in the canonical JSON form this ERC
   hashes.

Conforming implementations on Ethereum mainnet, L2s, or other ERC-8004
deployments are expected to be straightforward Solidity contracts; a
canonical Solidity reference will accompany the final draft.

## Security Considerations

### Receipt hash collisions

`keccak256` collision resistance is sufficient — there is no known
attack faster than brute force at 2^128 work. Implementations MUST use
RFC 8785 JCS canonicalization before hashing; ad-hoc canonicalization
opens up second-preimage attacks via key-order or whitespace mutation
of the receipt.

### Replay across deployments

A `(receipt_hash, agent_id)` pair bound on one chain MUST NOT be
trusted on another chain by default. Verifiers SHOULD include the
chain ID and `verifyingContract` from the EIP-712 domain in their
trust evaluation. Cross-chain reputation aggregators that wish to
unify bindings across chains MUST do so as application logic, not as
a property of `IPaymentReceiptBinding`.

### Authorization downgrade

Allowing both the payer wallet *and* the ERC-8004 `agentAddress` to
bind a receipt (§4) means a compromised ERC-8004 entry could bind
arbitrary receipts to the agent. Mitigations:

- Implementations SHOULD emit a permissioned event log so external
  monitors can detect unusual binding patterns.
- ERC-8004 supports key rotation via the IdentityRegistry; rotating
  the `agentAddress` invalidates further unauthorized bindings but
  does not retroactively unbind prior ones. Implementations MAY
  expose a `revokeBinding(bytes32 receiptHash)` callable by the
  current `agentAddress`; this is OPTIONAL and not part of the
  conformance interface.

### Privacy of the payer wallet

Storing only `receipt_hash` does not directly leak the payer wallet,
but linking the off-chain receipt to its hash is trivial for anyone who
holds both. Agents that want unlinkable payments MUST NOT publish their
receipts.

### DID resolution attacks

Step 4 of the verification procedure (§6) calls
`IdentityRegistry.getAgent`. If the ERC-8004 deployment is on a
different chain than the binding contract, the verifier is responsible
for using a trustworthy RPC for the cross-chain read. The binding
contract itself does not perform cross-chain reads.

### Front-running

A bind transaction reveals the `receipt_hash` and `agent_id` in the
public mempool. If the receipt itself is sensitive, the binder SHOULD
use a private mempool relay or commit-reveal scheme. The default flow
assumes receipt hashes are safe to publish.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE/LICENSE-CC0.md).
