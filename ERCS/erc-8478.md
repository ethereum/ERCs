---
title: x402 Payee Verification for ERC-8004 Agents
description: How a paying agent proves an x402 payTo belongs to the ERC-8004 agent it means to pay, before it signs the payment
author: Toll (@soli0x)
discussions-to: https://ethereum-magicians.org/t/pre-erc-x402-payee-verification-for-erc-8004-agents/30137
status: Draft
type: Standards Track
category: ERC
created: 2026-10-30
requires: 712, 1271, 3009, 8004
---

## Abstract

An agent that pays another agent over the x402 HTTP payment flow receives a `payTo` address in the server's
`402 Payment Required` answer and signs a payment to it. Nothing today ties that address to the paid agent's
[ERC-8004](./eip-8004.md) identity: whoever controls the HTTP answer chooses where the money goes. This proposal
defines (1) how an x402 payment requirement names the ERC-8004 identity it is paid to, (2) a **payee binding**: the
`payTo` is the identity's registered `agentWallet`, or the `agentWallet` signed an [EIP-712](./eip-712.md)
**payee delegation** naming that `payTo`, and (3) a verification procedure a payer, wallet, facilitator or third-party
checker runs before the payment is signed, with a fixed set of outcomes. The outcome is a fact about the binding, read
at a stated block; it is never a score, and **not read** is never the same as **verified** or **mismatch**.

## Motivation

x402 lets a client pay for an HTTP resource with a signed stablecoin transfer (for example an
[ERC-3009](./eip-3009.md) `transferWithAuthorization`). The server's 402 answer lists what it accepts: a network, an
asset, an amount and a `payTo`. The client signs a transfer to that `payTo`. For a person clicking "pay" in a browser
that is the same trust as any checkout page. For an agent that pays other agents without a person reading each
payment, it is a gap:

- **The HTTP answer is the only source of `payTo`.** A compromised server, a hijacked domain, a reverse proxy, a
  malicious middleware, or an injected instruction in a tool result can change it. The payment still settles, the
  resource may even be delivered, and the money is gone.
- **ERC-8004 already has the right anchor and nobody checks it.** An ERC-8004 identity can register an
  `agentWallet`, set by a signature of that wallet, so the address is proven to be under the agent's control. It is the
  natural place to receive payments, yet no rule says a payer should compare it with `payTo`.
- **Measured on one chain, the binding almost never holds today.** On Robinhood Chain (chain id 4663) the ERC-8004
  identity registry held 20,046 agents on 2026-10-28. 5,575 of them answered with an x402 payment requirement; in only
  5 of those was `payTo` the agent's registered `agentWallet`. Almost all of the mismatches come from one operator
  that runs many agents and receives into one treasury, which is a legitimate setup: it is exactly the case a
  **delegation** must cover, so that a payer can tell a treasury the agent authorised from an address nobody did.

A payer cannot fix this alone, because it cannot tell a legitimate treasury from a substituted address. The seller
cannot fix it alone, because a payer has no rule to check against. This proposal gives both sides the same rule.

Prior work: ERC-8004 defines the identity and `agentWallet` but not how payments bind to it. The Signed Payment Quotes
proposal (a separate draft) defines a quote a provider signs for a payment, which proves who quoted a price but not
that the quoted `payTo` is the agent's. The Prepared Transaction Envelope proposal (a separate draft) has a
consumer-filled `risk` field where the outcome of this check fits as one warning among others.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT
RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Terms

- **Seller**: the ERC-8004 agent that serves an x402 resource and is paid for it.
- **Payer**: the party that signs the payment (an agent, its wallet, or a person).
- **Checker**: whoever runs the verification in this proposal: the payer itself, its wallet, the facilitator, or a
  third-party service the payer asks.
- **Identity registry**: an ERC-8004 identity registry, named by chain id and address.
- **Agent wallet**: the address `getAgentWallet(agentId)` returns in the identity registry.
- **Payment requirement**: one entry of the 402 answer's `accepts` list, with at least `network`, `asset`, an amount
  and `payTo`.

### 1. Naming the seller's identity

A seller that supports this proposal MUST name its ERC-8004 identity in every payment requirement, inside the entry's
`extra` object, under the key `erc8004`:

```json
{
  "scheme": "exact",
  "network": "eip155:4663",
  "asset": "0x…",
  "amount": "50000",
  "payTo": "0x…",
  "resource": "https://example.com/api/thing",
  "extra": {
    "erc8004": {
      "registry": "eip155:4663:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
      "agentId": "20030",
      "delegation": null
    }
  }
}
```

- `registry` is a CAIP-10 account id: the chain and address of the identity registry. It MAY be on a different chain
  than `network`.
- `agentId` is the token id as a decimal string.
- `delegation` is either `null` or a payee delegation (section 3), REQUIRED when `payTo` is not the agent wallet.

A payer MAY also learn the identity some other way (it chose the seller from a directory by `agentId`, or the
seller's registration file lists the resource). A requirement that names no identity and a payer that knows none is
outcome `no-identity`.

### 2. The payee binding

A payment requirement is **bound** to the identity `(registry, agentId)` at block `B` of the registry's chain when all
of the following hold:

1. **Endpoint**: the resource's origin (scheme, host and port of `resource`, or of the URL the payer requested when
   the entry has no `resource`) is listed among the endpoints of the agent's registration file, the document at the
   identity's `tokenURI` as read at `B`. An origin matches when an endpoint URL in the file has the same scheme, host
   and port. Host comparison is case-insensitive and on the ASCII (punycode) form.
2. **Payee**: one of
   - (a) `payTo` equals the agent wallet at `B`, compared as addresses (case-insensitive hex), and `network` is the
     registry's chain, or the agent wallet has no contract code on the registry's chain (an externally owned account
     controls the same address on every EVM chain); or
   - (b) the requirement carries a payee delegation (section 3) that is valid at `B` for this `payTo`, `network`,
     `asset` and origin.

The endpoint condition stops a server that is not the agent from claiming the agent's identity. The payee condition
stops anyone who is not the agent from choosing where the agent's payments go.

### 3. Payee delegation

A seller whose payments go to an address other than its agent wallet (a treasury, a splitter, a payment processor, a
wallet on another network) authorises it with an EIP-712 signature by the agent wallet:

```solidity
struct PayeeDelegation {
    uint256 chainId;        // chain of the identity registry
    address registry;       // the identity registry
    uint256 agentId;
    address agentWallet;    // the agent wallet that signs, as registered when signing
    string  network;        // CAIP-2 network of the payment, e.g. "eip155:8453"
    string  payTo;          // the payee as the payment requirement writes it (0x hex or another network's form)
    string  asset;          // the asset as the payment requirement writes it; "*" = any asset on that network
    string  origin;         // "https://host[:port]"; "*" = every endpoint origin in the registration file
    uint64  validAfter;     // unix seconds
    uint64  validUntil;     // unix seconds; MUST be greater than validAfter
    bytes32 nonce;
}
```

EIP-712 domain: `name` = `"x402 Payee Delegation"`, `version` = `"1"`, `chainId` and `verifyingContract` = the
identity registry's chain id and address.

In the payment requirement, `extra.erc8004.delegation` is `{ "message": <PayeeDelegation as JSON, integers as decimal
strings>, "signature": "0x…" }`.

A delegation is **valid at block `B`** when:

- the message's `chainId`, `registry` and `agentId` name the identity the requirement names;
- `agentWallet` equals the agent wallet at `B` (so rotating the agent wallet revokes every delegation it signed);
- `validAfter <= t < validUntil`, where `t` is the checker's current time, and `validUntil - validAfter` is at most
  31,536,000 seconds (365 days);
- `network`, `payTo` and `asset` equal the requirement's (`payTo` and `asset` compared case-insensitively when both are
  0x hex), or `asset` is `"*"`;
- `origin` equals the resource's origin, or is `"*"`;
- the signature recovers to `agentWallet`, or, when `agentWallet` has contract code on the registry's chain,
  [ERC-1271](./eip-1271.md) `isValidSignature` on `agentWallet` at `B` returns the magic value.

A seller SHOULD keep delegations short-lived and SHOULD NOT use `"*"` for `asset` or `origin` when it can name them.
There is no on-chain revocation list: rotating the agent wallet is the revocation. A seller that needs to revoke one
delegation without rotating waits for `validUntil`, which is why short validity is RECOMMENDED.

### 4. Verification and outcomes

A checker verifies one payment requirement against one identity, reads the registry and the registration file at one
block `B` of the registry's chain (RECOMMENDED: the latest block the checker considers safe), and returns exactly one
outcome:

| Outcome | Meaning |
|---|---|
| `verified-wallet` | Bound by 2(a): `payTo` is the agent wallet. |
| `verified-delegation` | Bound by 2(b): a valid delegation names this `payTo`. |
| `mismatch` | The identity was read, the endpoint matches, and `payTo` is neither the agent wallet nor covered by a valid delegation. |
| `invalid-delegation` | A delegation is present but fails a rule in section 3 (the checker SHOULD say which). |
| `endpoint-unlisted` | The identity was read, but the resource's origin is not in its registration file. |
| `no-agent-wallet` | The identity has no agent wallet registered, and no valid delegation can exist. |
| `no-identity` | No identity was named or known for this requirement. |
| `not-read` | The checker could not read the registry, the registration file, or the code at the agent wallet. It MUST NOT be reported as any other outcome. |

The answer MUST also carry the identity checked, the chain id and number of `B`, the agent wallet read, the `payTo`,
and, for `not-read`, which read failed.

A payer that supports this proposal:

- SHOULD sign a payment only on `verified-wallet` or `verified-delegation`;
- MUST NOT treat `not-read` as verified;
- MUST, if its own policy pays on another outcome, record which outcome it paid on.

A facilitator MAY run the check and MAY refuse to settle a payment whose requirement is `mismatch`, but a payer MUST
NOT rely on a facilitator's check alone when the facilitator was named by the same 402 answer it is checking.

### 5. Signed payment

When the payer has already signed the payment, the checker SHOULD also compare it with the requirement: the signed
recipient (for ERC-3009, the authorization's `to`) MUST equal `payTo`, and the signed value MUST NOT exceed the amount
asked. A difference is reported beside the outcome as `payment-differs`. This catches a requirement that was checked
and a payment that was built from a different one.

### 6. Discovery

A seller SHOULD list, in its ERC-8004 registration file, under its x402 service, the payees it may use and the
delegations that authorise them, so that a directory or checker can verify the seller before any payment is asked:

```json
{
  "services": [
    {
      "name": "x402",
      "endpoint": "https://example.com/api/thing",
      "payees": [
        { "network": "eip155:4663", "payTo": "0x…" },
        { "network": "eip155:8453", "payTo": "0x…", "delegation": { "message": { }, "signature": "0x…" } }
      ]
    }
  ]
}
```

The 402 answer remains authoritative for a payment; a checker that finds the 402's `payTo` absent from `payees` SHOULD
report it beside the outcome as `payee-not-declared`.

## Rationale

- **Why the agent wallet and not the identity owner.** ERC-8004 lets the owner of an identity set an agent wallet only
  with a signature of that wallet, so the agent wallet is the one address proven to be the agent's on chain. The owner
  may be a cold key, a multisig or a marketplace contract that never receives payments.
- **Why a signed delegation and not an on-chain list.** Many sellers receive into a shared treasury or on several
  networks. An off-chain EIP-712 delegation costs nothing to issue, works for payees on networks the registry is not
  on, and is checked with one signature recovery. Rotating the agent wallet revokes all of them at once.
- **Why the endpoint condition.** Without it, any server can name a well-known agent's identity, set `payTo` to that
  agent's wallet and pass the payee check while serving nothing; worse, a payer would credit that agent with the
  delivery. Binding the resource's origin to the registration file closes this.
- **Why fixed outcomes and no score.** A payer applies its own policy; a checker's job is to say what holds. Keeping
  `not-read` separate stops a failed read from turning into a pass or a fail.
- **Why `extra`.** x402 payment requirements already carry an `extra` object for scheme-specific data; using it keeps
  existing clients working unchanged.

## Backwards Compatibility

Sellers that do not add `extra.erc8004` keep working; payers that do not check are unaffected. A payer that checks
gets `no-identity` for such sellers and decides by its own policy. Existing registration files without `payees` stay
valid.

## Reference Implementation

Toll (ERC-8004 agent 20030 on Robinhood Chain) runs this check as part of its pre-sign check: a caller sends the 402's
payment requirement, optionally the `agentId` and the signed payment, and receives the payee outcome with the block
read. Its agent census reads every registered agent's registration file and 402 daily, and publishes per-agent results.
The reference code will be linked here once the reference contract-free checker is extracted into a standalone
library.

## Security Considerations

- **The registry chain is the trust root.** A checker MUST read the identity registry from a node it trusts; a lying
  RPC can return any agent wallet.
- **Registration file hosting.** The registration file is fetched over HTTP or IPFS. An attacker who controls the
  file's host can list its own origin as an endpoint, but cannot change the agent wallet or forge a delegation, so it
  can at most redirect where a resource is served, not where payment goes.
- **Externally owned accounts across chains.** Rule 2(a) accepts the agent wallet on another EVM network only when it
  has no contract code on the registry's chain. A contract wallet at the same address on another chain may be
  controlled by someone else, so such payees need a delegation.
- **Key compromise.** If the agent wallet key is compromised, the attacker can sign delegations to its own address.
  The remedy is the ERC-8004 owner setting a new agent wallet, which voids every earlier delegation.
- **Lookalike addresses.** Comparison is on the full address, never on a prefix or suffix. Checkers that echo
  addresses to a person SHOULD show them in full.
- **Untrusted text.** Agent names and descriptions in registration files are written by the seller and MAY carry
  instructions aimed at an agent reading them; checkers and payers MUST treat them as data.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
