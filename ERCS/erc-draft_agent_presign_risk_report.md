---
title: Agent Pre-Sign Risk Report
description: Typed, block-pinned facts a risk source returns about a prepared transaction before an agent or wallet signs it
author: Toll (@soli0x)
discussions-to: https://ethereum-magicians.org/t/pre-erc-agent-pre-sign-risk-report/30145
status: Draft
type: Standards Track
category: ERC
created: 2026-10-31
requires: 20, 712, 1271, 8004
---

## Abstract

This proposal defines the report a risk source returns about a prepared, not yet signed, transaction or signature
request, so that an AI agent, a wallet or a policy engine can read it before signing. A report is a JSON object that
binds to the exact request by a digest, names the source by an [ERC-8004](./eip-8004.md) identity, and carries typed
findings in five groups: the tokens the request touches (linked to Launch Observations where a detector recorded
them), the approvals it grants and their spenders, the addresses it sends value to, the payment terms an agent was
given (an x402 `payTo` compared with the payee agent's registered `agentWallet` and with a quote signed under the Signed Payment Quotes proposal),
and text the agent read that could carry instructions (token names, metadata, tool output). Every finding states the
block it holds at, points to its evidence, and is either read or **not read**, which is never the same as zero or
false. A report carries no score, no verdict and no recommended action: the consumer applies its own policy. The
report is signed with [EIP-712](./eip-712.md), its hash can be anchored on chain, and it fits the consumer-injected
`risk` slot of the Prepared Transaction Envelope proposal.

## Motivation

Agents now prepare and sign transactions without a person reading each one. The losses that follow are well known and
mostly not exotic: an unlimited approval to a spender that is a week-old contract, a transfer to an address that
shares its first and last characters with one the signer used before, a payment to a `payTo` that is not the wallet
the paid agent registered, and an instruction hidden in a token's name that the agent reads as a command. Each is
visible before signing, to anyone who reads the chain and the request.

Two pieces of the path already exist. the Prepared Transaction Envelope proposal defines how a prepared transaction travels from the party that prepared
it to the party that signs it, and reserves a `risk` field that the consumer, not the producer, fills in. the Signed Payment Quotes proposal
defines a quote a service provider signs for a payment. Neither defines what a risk source says about a request. The
`risk` field holds a verdict (`ALLOW`, `WARN` or `BLOCK`), an optional score from 0 to 100, free-form warnings, and a
list of scanner verdicts. Three problems follow:

1. **No facts.** A consumer that receives `WARN` from a scanner cannot see what was read, so it cannot apply its own
   thresholds, compare two scanners, or explain the result to its user. An agent cannot tell "the spender is a contract
   deployed 40 blocks ago" from "the scanner did not recognize the spender".
2. **No binding and no block.** A verdict that does not name the request it was computed for can be replayed onto
   another request, and one that does not name its block cannot be reproduced or shown wrong.
3. **Absence reads as clean.** A scanner that could not read the spender's history and says nothing looks the same as
   one that read it and found nothing.

The payment case is the newest and the least checked. In our census of the ERC-8004 identity registry on Robinhood
Chain at block 100,007,973 (2026-10-28), 5,642 of 20,046 registered agents claimed to take x402 payments, 827 served
real payment terms, and 4 of those 827 named their registered `agentWallet` as `payTo`. A paying agent that holds the
payee's `agentId` can check this in one read; nothing tells it to, or gives it a place to record the answer.

This proposal standardizes the report: what a source read, about what, at which block, with what evidence, and what it
could not read. It is the pre-signing counterpart of Launch Observations, which records facts about a token launch
before an agent buys; a report links to those observations rather than redefining them.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT
RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Terms

- A **request** is the prepared transaction, batch or signature request that a signer has not yet signed, together
  with the context the consumer supplies about it.
- A **risk source** (source) is a service that reads a request and returns a report. It is identified by an ERC-8004
  identity.
- A **consumer** is the party that asks a source for a report and acts on it: an agent, a wallet, a signer or a policy
  engine.
- The **signer** is the account that would sign the request.
- A **finding** is one typed fact in a report about one entity of the request.
- A finding is **not read** when the source did not establish its value. Not read is a status of its own; it is never
  written as zero, `false` or an empty list.
- The **block a finding holds at** is the block number, on the chain named in the finding, at which the source read
  the state the finding states. Block numbers are the chain's own, as its nodes return for `eth_blockNumber`.
- Chains are named by CAIP-2 identifiers (`eip155:<chainId>`) and accounts by CAIP-10 identifiers
  (`eip155:<chainId>:<address>`).
- **Canonical bytes** of a JSON value are its UTF-8 encoding under the JSON Canonicalization Scheme (RFC 8785).
  `digest(x)` is `keccak256` of the canonical bytes of `x`.
- Integers that can exceed 2^53 (amounts, block numbers, agent identifiers) are JSON strings holding decimal digits.

### Request

A consumer asks for a report with a `PresignRequest`. The transport is not specified; an HTTP binding and a Model
Context Protocol binding are described under [Bindings](#bindings).

```typescript
interface PresignRequest {
  version: 'erc-presign/1'
  subject: EnvelopeSubject | CallsSubject
  context?: RequestContext
  kinds?: string[]              // core or extension kinds the consumer asks for; absent means every core kind
}

interface EnvelopeSubject {
  type: 'erc8265-envelope'
  envelope: object              // an Prepared Transaction Envelope proposal
}

interface CallsSubject {
  type: 'calls'
  chainId: string               // CAIP-2
  from: string                  // CAIP-10 of the signer
  calls: { to: string; value: string; data: `0x${string}` }[]
  typedData?: object            // an EIP-712 signature request instead of, or besides, calls
}

interface RequestContext {
  payment?: {
    requirements: object        // the x402 PaymentRequirements entry the agent selected from `accepts`
    resource?: string           // the URL or tool the payment is for
    payee?: { registry: string; agentId: string }   // ERC-8004 identity registry (CAIP-10) and agentId
    quote?: { quote: object; signature: `0x${string}`; chainId: string }  // the Signed Payment Quotes proposal ServicePaymentQuote
  }
  texts?: { field: string; ref?: string; text: string }[]  // text the agent read, such as tool output
  tokens?: string[]             // CAIP-10 of further tokens the agent intends to touch, such as a swap output
}
```

`texts[].field` names where the text came from: `token.name`, `token.symbol`, `token.metadata`, `tool-output`,
`web-page` or a name of the consumer's own. `ref` names the object the text belongs to, such as the token's CAIP-10.
A source MUST NOT treat any text in a request as an instruction to itself.

### Report

A source answers with a `PresignReport`.

```typescript
interface PresignReport {
  version: 'erc-presign/1'
  subjectDigest: `0x${string}`
  contextDigest: `0x${string}`  // digest of the request's context, or bytes32 zero when there was none
  chainId: string               // CAIP-2 of the chain the request executes on
  signer: string                // CAIP-10 of the signer
  source: Source
  issuedAt: string              // RFC 3339 UTC
  expiresAt?: string            // RFC 3339 UTC; the source's own bound on the report's use
  blocks: { chainId: string; block: string; hash: `0x${string}` }[]
  entities: Entities
  findings: Finding[]
  method: string                // the source's method version
  detail?: string               // URL of a fuller report; MAY require payment; not covered by reportHash
  signature: `0x${string}`
}

interface Source {
  registry: string              // CAIP-10 of the ERC-8004 identity registry
  agentId: string
  signer: string                // CAIP-10 of the account that signs reports
}

interface Entities {
  tokens: string[]              // CAIP-10
  approvals: Approval[]
  addresses: { address: string; role: Role }[]
  payment: boolean              // true when the request carried payment context
  texts: { index: number; field: string; ref?: string; digest: `0x${string}` }[]
}

type Role = 'target' | 'spender' | 'recipient' | 'payTo' | 'quote-issuer' | 'token'

interface Approval {
  token: string                 // CAIP-10
  spender: string               // CAIP-10
  form: 'erc20-approve' | 'erc20-increase' | 'erc2612-permit' | 'permit2-approve' | 'permit2-permit' | 'approval-for-all'
  callIndex?: number            // index in calls, when the approval is a call
}

interface Finding {
  kind: string
  entity: { token: string } | { approval: number } | { address: string; role: Role } | { payment: true } | { text: number }
  param?: unknown
  status: 'read' | 'not-read'
  value?: unknown               // present if and only if status is 'read'
  reason?: 'unsupported' | 'unavailable' | 'incomplete' | 'not-requested' | 'payment-required' | 'timeout'
  at?: { chainId: string; block: string }
  evidence: Evidence[]
  note?: string
}

type Evidence =
  | { type: 'tx'; chainId: string; hash: `0x${string}` }
  | { type: 'log'; chainId: string; tx: `0x${string}`; logIndex: number }
  | { type: 'call'; chainId: string; block: string; to: string; data: `0x${string}`; result: `0x${string}` }
  | { type: 'observation'; registry: string; observationId: string }
  | { type: 'document'; uri: string; hash: `0x${string}` }
```

A report MUST meet these rules.

- `subjectDigest` MUST be computed as under [Binding](#binding), and `contextDigest` MUST be `digest(context)` of the
  request, or 32 zero bytes when the request had no context.
- `blocks` MUST list, for each chain any finding holds at, the block and the block hash the source read. Every `at` in
  a finding MUST name a chain and block listed in `blocks`.
- `entities` MUST list what the source took the request to touch, as defined under [Entities](#entities). Entities are
  referred to by position: `{ approval: i }` is `entities.approvals[i]` and `{ text: i }` is the text with `index` `i`.
- For every entity it lists, a source MUST include each core finding kind that applies to the entity, with status
  `read` or `not-read`, unless the request's `kinds` excluded it. A consumer MUST treat a core kind missing for a
  listed entity as not read.
- A finding with status `read` MUST carry `value` and MUST NOT carry `reason`. A finding with status `not-read` MUST NOT
  carry `value` and MUST carry `reason`.
- A finding read from chain state MUST carry `at`. A finding computed only from the bytes of the request, such as a
  text finding on tool output, MUST NOT carry `at`.
- A report MUST NOT contain a score, a verdict, a severity, a recommended action, or any field whose purpose is to say
  whether the request should be signed. `note` is a one-line description of how the finding was read.
- `findings` MUST NOT hold two findings with the same `kind`, `entity` and `param`.
- A report MUST NOT reproduce text from the request or from the chain except where a finding's `value` is defined to
  carry it.

### Binding

The subject digest names the exact request the report was computed for.

- For an `erc8265-envelope` subject, `subjectDigest` is `digest(e)`, where `e` is the envelope with its `risk` and
  `producer.signature` fields removed. These are the bytes the Prepared Transaction Envelope proposal defines as the pre-image of a producer signature
  with `coverage` `envelope`, so the report and the producer's signature cover the same content.
- For a `calls` subject, `subjectDigest` is `digest({ chainId, from, calls, typedData })` with the fields as given in
  the request, `typedData` omitted when absent.

The consumer MUST compute both digests itself from the request it is about to sign and MUST NOT take them from the
report. A report whose digests differ from the consumer's MUST be treated as about another request. When the request
is prepared again, for example with fresh calldata, its digest changes and the consumer needs a new report.

### Entities

A source derives entities from the calls, the typed data and the context. It MUST NOT derive them from presentational
fields of a Prepared Transaction Envelope, such as `description` or `metadata`, which that proposal defines as unfit for policy.

- **Tokens**: every contract that is the `to` of a call the source decodes as an [ERC-20](./eip-20.md) or ERC-721 call,
  every token named in an approval, every token in `context.tokens`, and the `asset` of the payment context. A source
  that simulates the request SHOULD also list each contract that emits an ERC-20 `Transfer` or `Approval` event in the
  simulation.
- **Approvals**: each call to `approve(address,uint256)`, `increaseAllowance(address,uint256)` or
  `setApprovalForAll(address,bool)` with `true`; each Permit2 `approve(address,address,uint160,uint48)`; and each
  EIP-712 request whose primary type is an ERC-2612 `Permit` or a Permit2 `PermitSingle` or `PermitBatch` (one approval
  per detail of a batch).
- **Addresses**: the `to` of each call (`target`), the spender of each approval (`spender`), the receiver of native
  value or of each decoded ERC-20 `transfer` or `transferFrom` (`recipient`), the payment's `payTo` (`payTo`), the
  quote's `issuer` (`quote-issuer`), and each listed token (`token`). An address with several roles is listed once per
  role.
- **Texts**: every entry of `context.texts`, and, for each token listed, its `name()` and `symbol()` as returned at the
  block the source read, with `field` `token.name` or `token.symbol` and `ref` the token. `digest` is `keccak256` of the
  text's UTF-8 bytes.

A consumer SHOULD compare `entities` with its own decoding of the request and treat an entity the report does not
list as not read.

### Core findings

Kinds are strings. The `erc.presign.` prefix is reserved for kinds defined in an ERC. A source MAY report other kinds
under a prefix it controls, such as a domain it owns. A consumer MUST treat a kind it does not recognize as
informational.

#### Tokens

| Kind | `param` | `value` when read |
| --- | --- | --- |
| `erc.presign.token.observation` | `{ registry, kind, param }`: CAIP-10 of a Launch Observations registry, a finding kind (`bytes32` hex) and its `param` (decimal string) | `{ value, detector, observationId, observedBlock, recordedAt }`, all decimal strings except `detector` (CAIP-10) |
| `erc.presign.token.issuer-listing` | `{ issuer, list }`: the issuer's name and the URI of the list it publishes (for example a list of tokenized stocks) | `"listed"` (the token's address is on the list), `"issuer-unlisted"` (the token is the issuer's own contract by an on-chain mark the source names in the evidence, such as its proxy's beacon or its factory, but is not on the list), `"copy"` (it is not the issuer's contract but uses the name or symbol of one that is; the evidence names the listed token it copies), or `"none"` (none of these: not on the list, not the issuer's contract, and using no listed token's name or symbol) |
| `erc.presign.token.oracle-deviation` | `{ feed }`: CAIP-10 of a price feed for the token | `{ pool, price, oraclePrice, oracleAge, deviationBps }`: the pool the request trades in, the price it implies, the feed's latest answer and its age in seconds at the block, and the signed difference in basis points |

A source reads it with the registry's `latestFinding(chainId, token, detector, kind, param)`, or with
`latestFindingFrom` over the detectors it trusts, and copies what that returns. When the returned `value` is the
registry's not read value, `type(uint256).max`, or there is no observation, the finding is not read with reason
`unavailable`. The detector's lean is not copied; a consumer that wants it reads the observation. `at` is the block at
which the source made the read on the registry's chain, and the evidence MUST include an `observation` entry. A source
MAY include one such finding per Launch Observations kind it reads.

An issuer-listing finding reads the issuer's list at the time of the check and records the list's hash in the
evidence; a list that could not be fetched makes the finding not read, never `"listed"`. An oracle-deviation finding
uses the feed's answer as the feed defines it (for a tokenized stock, the price of one token, which may already include
a share multiplier) and is not read when the feed's answer is older than the source's own bound, which the evidence
states.

Facts about the token's address, such as whether it has code and when it first appeared, are address findings with
role `token`.

#### Approvals

| Kind | `param` | `value` when read |
| --- | --- | --- |
| `erc.presign.approval.amount` | none | The amount granted as a decimal string, or `"all"` for an approval for all |
| `erc.presign.approval.unlimited` | none | `true` if the amount is the maximum of its type (2^256 - 1 for ERC-20 and ERC-2612, 2^160 - 1 for Permit2) or the approval is an approval for all; otherwise `false` |
| `erc.presign.approval.share-of-supply` | none | The amount in basis points of the token's `totalSupply()` at the block, capped at 10000 |
| `erc.presign.approval.expiry` | none | The Unix time at which the allowance itself expires (the Permit2 `expiration`), or `"none"` for an allowance that does not expire |
| `erc.presign.approval.current-allowance` | none | The allowance the spender already holds from the signer at the block, as a decimal string |

`approval.expiry` is the expiry of the allowance, not the deadline of the signature that grants it. `share-of-supply`
does not apply to an approval for all.

#### Addresses

| Kind | `param` | `value` when read |
| --- | --- | --- |
| `erc.presign.address.code` | none | `"none"`, `"contract"`, or `"delegated"` for an account whose code is an [EIP-7702](./eip-7702.md) delegation designator; for `"delegated"` the evidence MUST include the `eth_getCode` result |
| `erc.presign.address.delegate-single-caller` | none | For a `"delegated"` address: `true` when every function of the delegate that can move value is callable by one fixed address (a constant, or one storage slot) and by no other caller, else `false` |
| `erc.presign.address.delegate-unbounded-outflow` | none | For a `"delegated"` address: `true` when the delegate can send the account's whole balance of native value or a token to a recipient the caller chooses in one call, with no per-call limit, allowlist or delay, else `false` |
| `erc.presign.address.delegate-authorizations` | `{ blocks }`, the number of blocks looked back | For a `"delegated"` address: `{ count, sameSigner, senderIsOnlyCaller }`: the number of [EIP-7702](./eip-7702.md) authorizations for the same delegate seen in the `blocks` blocks before the report's block, how many of them were carried by transactions from one sender, and whether that sender is the delegate's only allowed caller (`null` when `delegate-single-caller` is not read) |
| `erc.presign.address.first-seen-block` | none | The first block in which the address sent a transaction, received native value or a token transfer, or had code deployed, as a decimal string |
| `erc.presign.address.source-verified` | verifier name, such as `sourcify` | `"exact"`, `"partial"` or `"none"`; applies to addresses with code |
| `erc.presign.address.prior-transfers` | none | The number of transactions and token transfers from the signer to the address before the block, as a decimal string |
| `erc.presign.address.lookalike` | `{ prefix, suffix }`, hex digits compared | The addresses the signer sent to or received from before the block that share the first `prefix` and last `suffix` hex digits with this address, compared without case, and differ from it; `[]` when the source read the history and found none |
| `erc.presign.address.on-list` | `{ uri, hash }` of a published list | `true` or `false` |

The three `delegate-` kinds apply only to an address whose `code` is `"delegated"`, and describe the delegate at the
report's block: `"delegated"` alone reads the same for a delegate with limits and for one that lets a single key empty
the account. `delegate-single-caller` and `delegate-unbounded-outflow` need verified source or bytecode analysis; a
source that did not complete it MUST report them not read (reason `unsupported` or `incomplete`), never `false`. The
evidence for a read value SHOULD include the calls the source simulated and their results.

For `first-seen-block`, a source whose scan of the address's history stopped before reaching its first appearance
MUST report not read with reason `incomplete`. For `lookalike` and `prior-transfers`, a source that read only part of
the signer's history MUST report not read with reason `incomplete`.

A list for `on-list`, such as a list of addresses that took funds through approvals, MUST be published at `uri` with
`keccak256` of its bytes equal to `hash`, and MUST state its inclusion criteria and, for each entry, the evidence it was
listed on. `on-list` states membership in a named list at the report's time; it is a fact about the list, not about the
address.

#### Payment

Payment findings apply when the request carried `context.payment`. Each states whether two named values are equal.

| Kind | `param` | `value` when read |
| --- | --- | --- |
| `erc.presign.payment.match` | the pair compared, from the list below | `{ equal, left, right }`: a boolean and the two values compared, as read |

The pairs are:

- `payTo=agentWallet`: the requirements' `payTo` and `getAgentWallet(agentId)` of the payee on its ERC-8004 registry,
  read at the block in `at`, which is a block of the registry's chain. A zero `agentWallet`, as ERC-8004 leaves it after
  a transfer, is read as zero and compared as such.
- `payTo=quote.recipient`, `asset=quote.asset`, `amount=quote.amount`, `network=quote.chainId`: the requirements'
  field against the Signed Payment Quotes proposal quote's field, addresses compared without case and the network as CAIP-2.
- `quote.signature`: whether the quote's signature verifies for its `issuer` as the Signed Payment Quotes proposal specifies, by `ecrecover` for an
  issuer without code and by [ERC-1271](./eip-1271.md) otherwise, at the block in `at`. `left` is the issuer and `right`
  the recovered or validating account.
- `quote.issuer=agentWallet`: the quote's `issuer` against the payee's `agentWallet`.
- `quote.valid-at-issue`: whether `issuedAt` falls within the quote's `validAfter` and `validUntil`.
- `authorization.to=payTo`: the recipient of the payment the request would sign or send (the `to` of an EIP-3009
  `TransferWithAuthorization` in the typed data, or of the ERC-20 `transfer` in the calls) against the requirements'
  `payTo`.
- `authorization.value=amount`: the value of that payment against the requirements' `amount`.

| Kind | `param` | `value` when read |
| --- | --- | --- |
| `erc.presign.payment.payee-binding` | none | One outcome of the x402 Payee Verification proposal (a separate draft): `verified-wallet`, `verified-delegation`, `mismatch`, `invalid-delegation`, `endpoint-unlisted`, `owner-only`, `no-agent-wallet` or `no-identity`; its `not-read` outcome is this proposal's not read |

A source that implements that proposal SHOULD report its outcome as this finding, beside the `payTo=agentWallet` pair,
so a consumer reads one outcome instead of rebuilding it from pairs.

A pair that cannot be formed because the request lacks one side, such as a quote, is omitted rather than reported as
not read. A pair whose two sides exist but could not be read, such as an unreachable registry, is not read.

#### Texts

| Kind | `param` | `value` when read |
| --- | --- | --- |
| `erc.presign.text.control-chars` | none | The number of code points in the text with Unicode General Category `Cf`, `Co` or `Cc`, other than tab, line feed and carriage return |
| `erc.presign.text.mixed-script` | none | `true` if the text holds letters of more than one Unicode script, not counting `Common` and `Inherited`; otherwise `false` |
| `erc.presign.text.addresses` | none | Every 20-byte hex address and CAIP-10 account found in the text, in order |
| `erc.presign.text.pattern-match` | `{ uri, hash }` of a published pattern set | The identifiers of the patterns in the set that match the text, in order; `[]` when none match |

A pattern set for `pattern-match` MUST be published at `uri` with `keccak256` of its bytes equal to `hash`, and MUST
define each pattern precisely enough that a third party can rerun it on the same text and get the same result.
Patterns that detect instructions addressed to an agent, such as requests to approve, transfer, ignore earlier
instructions or call a tool, belong here. A match states that a published pattern matched; it is not a judgment that
the text is an attack.

For texts the source read from the chain (token name and symbol), `at` names the block of the read. For texts the
consumer supplied, there is no `at`, and the evidence is the text's `digest` in `entities`.

### Signature and source identity

`reportHash` is `digest(r)`, where `r` is the report without its `signature` and `detail` fields. `signature` MUST be an EIP-712
signature by `source.signer` over:

```
EIP712Domain(string name,string version,uint256 chainId)
  name    = "Agent Pre-Sign Risk Report"
  version = "1"
  chainId = the chain id of source.registry

PresignReport(bytes32 subjectDigest,bytes32 contextDigest,bytes32 reportHash)
```

A consumer verifies a report by:

1. recomputing `subjectDigest` and `contextDigest` from its own request, and `reportHash` from the report;
2. verifying `signature` for `source.signer`, by `ecrecover` for an account without code and by ERC-1271
   `isValidSignature` otherwise; and
3. reading, on `source.registry`, that `source.signer` is `getAgentWallet(agentId)` or `ownerOf(agentId)`, or that it
   is listed in `signers` of the `presign-risk-report` service in the registration file `tokenURI(agentId)` names, read
   at the time of verification.

A source SHOULD sign with a key other than its `agentWallet` and list that key in `signers`: a report service runs on
an online server, and the `agentWallet` often receives the agent's payments. Removing a key from `signers` revokes it
for every later verification.

A report that fails any step MUST be treated as unsigned. A consumer MUST treat an unsigned report as absent.

A source SHOULD list a service named `presign-risk-report` in its ERC-8004 registration file, with the URL of its
endpoint and, when it signs with a key other than its `agentWallet` or owner, a `signers` array of CAIP-10 accounts:

```json
{ "name": "presign-risk-report", "endpoint": "https://example.com/api/presign", "version": "erc-presign/1",
  "signers": ["eip155:4663:0x02593abff31f4e8ec1d5c2f297a347c51ef06e5c"] }
``` A consumer that acted on a source's report MAY give feedback to the source's `agentId` in the ERC-8004
reputation registry with `tag1` `presign-risk-report`, `tag2` the finding kind it relied on, and a `feedbackURI` that
names the `reportHash`.

### Use in a Prepared Transaction Envelope

This section defines how a report travels in the `risk` field of a Prepared Transaction Envelope. the Prepared Transaction Envelope proposal defines that field as:

```typescript
interface RiskAssessment {
  action: 'ALLOW' | 'WARN' | 'BLOCK'
  score?: number
  warnings: RiskWarning[]            // { code: string; severity: 'low' | 'medium' | 'high' | 'critical'; message: string }
  scanners?: ScannerVerdict[]        // { provider: string; verdict: 'ALLOW' | 'WARN' | 'BLOCK'; url?: string }
}
```

and excludes `risk` from the producer signature's pre-image, so a consumer can write it after reception. This proposal
adds one member:

```typescript
interface RiskAssessment {
  // ... as the Prepared Transaction Envelope proposal defines
  reports?: PresignReport[]
}
```

- A consumer that obtained reports for the envelope MAY place them in `risk.reports`, unchanged.
- `action`, `score`, `warnings` and `scanners` remain the consumer's own. A consumer that derives `action` from reports
  does so by its own policy. It MAY project a finding into `warnings`, with `code` set to the finding's `kind` and a
  `severity` it chooses, and MUST NOT present that severity as the source's.
- A consumer MUST NOT list a source in `scanners` with a verdict the source did not give. A source under this proposal
  gives none.
- A report found in `risk.reports` of an envelope a consumer received MUST be verified as under
  [Signature and source identity](#signature-and-source-identity), and SHOULD be used only if its source is one the
  consumer chose. A report attached by the producer carries the producer's choice of source, as the Prepared Transaction Envelope proposal says of a
  producer-supplied `risk`.

Because `subjectDigest` is computed over the envelope without `risk`, writing reports into `risk` does not change the
digest they bind to.

### Consuming a report

This section is informative, except where it uses the key words.

A consumer, whether an agent, a wallet or a policy engine, uses a report in this order:

1. Verify the report and its source, and check that the source is one it trusts, by `agentId`. Counting reports or
   sources is not evidence; many sources may be one party.
2. Check freshness: for each entry of `blocks`, compare `block` with the current block of that chain, and refuse a
   report older than a bound of its own. It SHOULD also check that each `hash` is the canonical hash at that block.
3. Compare `entities` with its own decoding of the request.
4. For each finding its policy needs, refuse to proceed on not read, unless its policy accepts the gap.
5. Apply its own thresholds to the values: for example, refuse an approval whose `unlimited` is `true` to a spender
   whose `first-seen-block` is less than a day old, or refuse a payment whose `payTo=agentWallet` pair is not equal.

A consumer MUST NOT treat a missing report, a missing finding, or a not read finding as a clean result.

An agent that runs on a language model MUST pass report content to the model as data, not as instructions. Strings in
a report, including `note`, list contents and text findings, can carry text an attacker wrote.

### Bindings

This section is informative.

- **HTTP.** `POST` a `PresignRequest` as `application/json` to the endpoint in the source's registration file; the
  response is a `PresignReport`. A source that charges MAY answer `402 Payment Required` with x402 payment
  requirements; payment changes who may obtain a report, not its content. A consumer that pays a source SHOULD check
  that payment as it checks any other.
- **Model Context Protocol.** A source exposes a tool named `presign_risk_report` whose input is a `PresignRequest`
  and whose result is a `PresignReport` as JSON.

### On-chain anchoring

Anchoring is OPTIONAL. It lets a source show that a report existed before the transaction it describes was included,
and lets anyone count a source's reports against what happened later.

```solidity
interface IPresignReportAnchor {
    event ReportAnchored(address indexed source, bytes32 indexed subjectDigest, bytes32 indexed reportHash, string reportURI);

    function anchor(bytes32 subjectDigest, bytes32 reportHash, string calldata reportURI) external;
    function anchoredAt(address source, bytes32 reportHash) external view returns (uint64 timestamp, uint64 blockNumber);
}
```

- `anchor` MUST NOT restrict its caller, MUST revert if `subjectDigest` or `reportHash` is zero or `reportURI` is
  longer than 512 bytes, and MUST emit `ReportAnchored` with the caller as `source`.
- The first anchoring of a `reportHash` by a caller MUST record the block timestamp and the chain's own block number
  (on an Arbitrum chain, `ArbSys(address(100)).arbBlockNumber()`); a later anchoring of the same pair MUST NOT change
  them. `anchoredAt` MUST return them, or zeros.
- An anchor contract MUST have no owner and MUST NOT be upgradeable.
- An anchoring counts for a report only if its `source` is the report's `source.signer`. A `reportURI` SHOULD be
  content-addressed.

A report MAY also be anchored by any other means that records `reportHash` with a time, such as an ERC-8004 reputation
feedback that names it.

### Relation to other proposals

This section is informative.

- **the Prepared Transaction Envelope proposal.** A report fills the `risk` slot without changing its meaning: the consumer still writes `action`. The
  digest reuses the Prepared Transaction Envelope proposal's own pre-image for envelope signatures.
- **the Signed Payment Quotes proposal.** A report checks a quote against the payment requirements and the payee's identity; it does not settle,
  consume or replace quotes.
- **Launch Observations.** Token facts come from a Launch Observations registry by reference, with the observation
  identifier, so the facts about a launch are defined in one place and recorded before the outcome is known.
- **[ERC-8126](./eip-8126.md).** ERC-8126 verifies an agent by `agentId` and produces scores from 0 to 100 per
  verification type. A source that is also an ERC-8126 provider MAY compute its Ethereum Token Verification and Wallet
  Verification scores from findings of this proposal, but MUST NOT place them in a report.
- **[ERC-8354](./eip-8354.md).** ERC-8354 proves that a committed private policy allowed an action. A report can be
  an input to such a policy; the verdict stays in ERC-8354.

## Rationale

- **Facts, not verdicts.** A verdict computed by one source for one policy cannot be compared with another's or
  reapplied to a consumer's own policy. A finding states a value at a block, which a third party can recompute. The
  consumer already owns the decision, as the Prepared Transaction Envelope proposal makes it own `risk`; this proposal only gives it inputs. Earlier
  attempts at a single token safety score and at an agent transaction guard interface combined the reading and the
  decision, which made the reading unusable for anyone whose thresholds differed.
- **Not read is a status.** Zero, `false` and `[]` are measured answers. A source that could not reach a node, could
  not finish a history scan, or was not paid must say so, and a consumer must be able to refuse on it.
- **Coverage is declared.** A finding that is not in a report cannot be refused on unless the consumer knows it should
  have been there. `entities` and the rule that every applicable core kind appears make a silent omission detectable.
- **Bound to the request.** Without a digest of the exact request, a report about a harmless transaction could be
  shown next to a harmful one. The digest for envelopes reuses the Prepared Transaction Envelope proposal's signature pre-image so that one canonical
  form serves both proposals; JCS is used because the request is JSON.
- **Block-pinned, per chain.** A payment check reads the payee's registry, which may be on another chain than the
  transaction. Each finding names its chain and block, and `blocks` names their hashes, so a reader can reproduce each
  read and see whether it was made on a reorganized block.
- **Lists and patterns are named.** Whether an address took funds before, or whether a text contains an instruction,
  depends on a list or a pattern someone maintains. Naming the list or pattern set by URI and hash turns a label into
  a reproducible fact about a published document, and lets two consumers disagree about the list rather than about the
  report.
- **Text facts that can be rerun.** Instruction-like text cannot be detected exactly. The core text kinds are those a
  third party can recompute byte for byte (control characters, mixed scripts, embedded addresses), and the rest goes
  through published pattern sets.
- **Off-chain first.** The request is a JSON envelope and most of the reads are history scans, so the report is JSON.
  A contract cannot recompute a JCS digest, and on-chain checks of a token belong in Launch Observations, which a
  guard can read inside the transaction. The anchor records only a hash.
- **ERC-8004 identity, rechecked when read.** A consumer chooses sources by identity and record. Checking the signer
  against `agentWallet` or the owner when verifying means a transferred identity does not keep vouching for reports
  signed by its old wallet.
- **No new score field in `risk`.** the Prepared Transaction Envelope proposal already has `score` and `action` for the consumer. Adding reports as a
  list next to them keeps the consumer's verdict and the sources' facts apart, so a reader can ignore one and keep the
  other.

## Backwards Compatibility

No backward compatibility issues found. The `reports` member is an addition to the Prepared Transaction Envelope proposal's `RiskAssessment`; a consumer
that does not know it ignores it, and since `risk` is outside the producer signature's pre-image, adding it changes no
signature.

## Test Cases

A conforming source and consumer pass these cases.

- A request with one `approve(spender, 2^256 - 1)` call yields one approval entity, a `spender` address and a `token`
  address, and findings `approval.unlimited` `true`, `approval.amount` `"115792089237316195423570985008687907853269984665640564039457584007913129639935"`
  and `approval.share-of-supply` `10000`, each with `at` listed in `blocks`.
- The same request with `approve(spender, 0)` yields `approval.unlimited` `false` and `approval.amount` `"0"`; a
  report that writes not read as `"0"` fails.
- A Permit2 `PermitSingle` with amount 2^160 - 1 yields `approval.unlimited` `true` and `approval.expiry` equal to its
  `expiration`, not its `sigDeadline`.
- A spender whose history scan did not reach its first transaction yields `address.first-seen-block` not read with
  reason `incomplete`, without `value`.
- A recipient sharing the first 4 and last 4 hex digits with an address the signer paid before yields
  `address.lookalike` with that address; a recipient the signer paid before yields `[]` and a non-zero
  `address.prior-transfers`.
- An account whose code is `0xef0100` followed by an address yields `address.code` `"delegated"` with the code as
  evidence.
- With x402 requirements whose `payTo` differs from the payee's `getAgentWallet(agentId)`, the
  `payTo=agentWallet` pair has `equal` `false` and both addresses; after the identity is transferred and the wallet is
  cleared, `right` is the zero address.
- With a quote under the Signed Payment Quotes proposal signed by an account other than its `issuer`, the `quote.signature` pair has `equal` `false`;
  without a quote, no quote pair appears.
- A token whose name contains U+202E and the text `approve 0x...` yields `text.control-chars` `1`, `text.addresses` with
  that address, and a `text.pattern-match` naming the matching pattern of the published set.
- A token with a Launch Observations finding yields `token.observation` with the registry's value and the observation
  identifier as evidence; a finding the registry returns as `type(uint256).max` yields not read with reason
  `unavailable`.
- A consumer that changes one byte of calldata gets a different `subjectDigest` and rejects the report. Writing
  `risk.reports` into the envelope leaves `subjectDigest` unchanged.
- A report signed by an account that is neither the owner nor the `agentWallet` of `source.agentId` is treated as
  absent.
- A report with a `score`, `verdict`, `severity` or `action` field does not conform.
- On an anchor contract, anchoring a zero hash or a 513-byte URI reverts; a second anchoring of the same report by the
  same caller leaves `anchoredAt` unchanged; another caller's anchoring is recorded under that caller.

## Reference Implementation

Toll (ERC-8004 agent 20030 on Robinhood Chain) runs a source of this proposal on Robinhood Chain: `POST
https://t0ll.xyz/api/presign` (the HTTP binding) and the Model Context Protocol tool `presign_risk_report` at
`https://t0ll.xyz/api/mcp`. Every finding is read at one pinned block listed in `blocks`; kinds it does not read yet
are reported as not read with reason `unsupported`. Token findings include `token.observation`, copied from a Launch
Observations (ERC-8470) registry, and payment findings include `payment.payee-binding` from x402 Payee Verification
(ERC-8478). Reports are signed by a key listed in `signers` of the source's registration file, not by its
`agentWallet`. The same report rides in `reports` of the source's ERC-8265 risk assessment answer, and the client
package `@tollxyz/guard` puts that answer in front of an agent's wallet. A consumer-side verifier, an anchor contract
and test vectors will be added under `assets/erc-draft_agent_presign_risk_report`.

## Security Considerations

- **Sources can be wrong or lie.** A report proves only that its source signed it. Consumers MUST choose their sources
  and SHOULD prefer ones that publish evidence that can be rechecked and anchor reports before outcomes are known.
- **Producer-chosen sources.** A producer can attach a report from a source that favors it. A consumer SHOULD obtain
  reports itself, from sources it chose, and treat attached ones as the Prepared Transaction Envelope proposal treats a producer-supplied `risk`.
- **Replay.** A report for one request cannot be used for another, because the consumer recomputes the digest. A
  report for the same request is valid for as long as the consumer's freshness bound allows; consumers SHOULD bound it
  tightly for approvals and payments, whose facts can change within blocks.
- **Absence.** No report, a missing finding and a not read finding say nothing about the request. They MUST NOT be
  presented as clear.
- **Injection through the report.** Token names, list entries and pattern matches carry attacker-written text into the
  agent's context. Reports reproduce text only where a finding's value requires it, and consumers MUST handle report
  strings as data.
- **Privacy and front-running.** Sending a prepared request to a source discloses the signer's intent before it is
  signed. A consumer SHOULD use sources it trusts with that disclosure, and a source SHOULD NOT retain or share
  requests beyond what anchoring requires.
- **Time of check and time of use.** Findings hold at their block. A spender's code, an allowance or a payee's
  `agentWallet` can change before inclusion. Consumers SHOULD check again where their policy depends on a value that
  can change, and SHOULD prefer short validity windows on the request itself.
- **Reorganizations.** A finding read at a block later reorganized out may not hold. `blocks` carries hashes so
  consumers can detect this; sources SHOULD read finalized or recent canonical blocks and state which in `method`.
- **Lists.** A list can be wrong or used to harm a named address. `on-list` names the list and its hash so that the
  list's publisher answers for it, and lists MUST carry per-entry evidence.
- **Paying for a report.** Where a source charges through x402, the consumer's payment to the source is itself a
  payment that can be redirected; a consumer SHOULD check the source's `payTo` against the source's `agentWallet`.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
