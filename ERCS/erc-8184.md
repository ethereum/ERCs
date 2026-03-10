---
title: Unidirectional Payment Channels with Signed Vouchers
description: A standard for streaming micropayments via off-chain signed vouchers over unidirectional ERC-20 payment channels, designed for high-frequency service commerce.
author: Artur Markus (@kimbo128)
discussions-to: https://github.com/ethereum/ERCs/pull/1592
status: Draft
type: Standards Track
category: ERC
created: 2026-03-10
requires: 20, 712
---

## Abstract

This specification defines unidirectional payment channels for streaming micropayments using [EIP-712](https://eips.ethereum.org/EIPS/eip-712) typed signed vouchers. A consumer opens a channel by depositing [ERC-20](https://eips.ethereum.org/EIPS/eip-20) tokens into escrow, designating a provider and an expiry timestamp. The consumer then issues incrementally increasing off-chain signed vouchers to the provider in exchange for services. The provider can claim the highest voucher on-chain at any time. Channels settle via provider claim, consumer close after expiry, or cooperative close with mutual signatures.

This standard is designed for high-frequency, low-value service transactions — particularly AI agent-to-provider commerce — where per-transaction on-chain settlement is economically infeasible.

## Motivation

AI agents increasingly consume services programmatically: language model inference, image generation, code execution, web scraping, data retrieval. These interactions share common properties:

1. **High frequency**: An agent may send hundreds of requests per session.
2. **Low value**: Each request costs fractions of a cent to a few cents.
3. **Immediate delivery**: The provider delivers the result synchronously with the request.
4. **No evaluation needed**: The consumer can assess quality instantly (the response is either useful or not).

Existing on-chain payment models are poorly suited for this pattern:

- **Direct transfers** require a transaction per request, making sub-cent payments infeasible due to gas costs.
- **Job escrow models** (e.g. [ERC-8183](https://eips.ethereum.org/EIPS/eip-8183)) require upfront job specification, evaluator attestation, and multiple state transitions. This is appropriate for discrete deliverables but introduces unnecessary overhead for immediate request-response services.
- **Subscription models** lack granularity and require trust in the provider to deliver ongoing value.

Unidirectional payment channels solve this by amortizing on-chain costs across many off-chain interactions. The consumer deposits once, transacts off-chain via signed vouchers, and the provider settles once. Two on-chain transactions cover an unlimited number of service requests.

This standard formalizes the minimal interface for such channels: channel lifecycle, voucher schema, settlement, and cooperative close.

### Relationship to ERC-8183

This standard is **complementary** to ERC-8183 (Agentic Commerce). ERC-8183 defines a Job primitive for discrete tasks with escrow and evaluator attestation — suited for deliverable-based commerce where quality must be verified before payment release.

This standard addresses **streaming service commerce** where:
- Delivery is immediate and synchronous with each request.
- The consumer evaluates quality implicitly by continuing or stopping the interaction.
- The economic model is pay-per-use, not pay-per-deliverable.

Together, the two standards cover the full spectrum of agent commerce:

| Dimension | This Standard | ERC-8183 |
| --- | --- | --- |
| Payment model | Streaming / per-request | Per-job / milestone |
| Settlement | 2 on-chain txs total | 4+ on-chain txs per job |
| Trust model | Consumer controls spend rate | Evaluator-mediated |
| Best for | APIs, chat, inference, scraping | Reports, analysis, fund management |
| Quality assurance | Implicit (stop sending vouchers) | Explicit (evaluator attestation) |

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Interface

Implementations MUST implement the `IPaymentChannel` interface:

```solidity
interface IPaymentChannel {
    function open(address provider, uint256 amount, uint256 duration) external returns (bytes32 channelId);
    function claim(bytes32 channelId, uint256 amount, uint256 nonce, bytes calldata signature) external;
    function close(bytes32 channelId) external;
    function cooperativeClose(bytes32 channelId, uint256 finalAmount, bytes calldata providerSignature) external;
    function getChannel(bytes32 channelId) external view returns (
        address consumer, address provider, uint256 deposit, uint256 claimed, uint256 expiry
    );
    function getBalance(bytes32 channelId) external view returns (uint256);

    event ChannelOpened(bytes32 indexed channelId, address indexed consumer, address indexed provider, uint256 deposit, uint256 expiry);
    event ChannelClaimed(bytes32 indexed channelId, address indexed provider, uint256 amount);
    event ChannelClosed(bytes32 indexed channelId, address indexed consumer, uint256 refund);
}
```

### Channel Data

Each channel SHALL have at least:

| Field | Type | Description |
| --- | --- | --- |
| `consumer` | `address` | The party that opens the channel and signs vouchers. |
| `provider` | `address` | The party that receives payment on claim. |
| `deposit` | `uint256` | Total tokens deposited into escrow. |
| `claimed` | `uint256` | Cumulative amount claimed by the provider so far. |
| `expiry` | `uint256` | Unix timestamp after which the consumer may close the channel. |

Payment SHALL use a single [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token per contract. Implementations MAY support per-channel token selection; the specification only requires one token per contract.

### Channel Identifier

Each channel SHALL be identified by a unique `bytes32` value (`channelId`). The method of derivation is left to the implementation. Implementations SHOULD derive `channelId` deterministically from the channel parameters (e.g. `keccak256(abi.encodePacked(consumer, provider, nonce))`) to prevent collisions and enable off-chain channel identification.

### Channel Lifecycle

A channel progresses through the following states:

```
   Consumer calls open()
          │
          ▼
       ┌──────┐
       │Active│ ── Provider calls claim() ──► Provider receives (amount - claimed)
       └──────┘                                claimed updated, channel stays Active
          │
          │ block.timestamp >= expiry
          ▼
     ┌─────────┐
     │ Expired  │ ── Consumer calls close() ──► Consumer receives (deposit - claimed)
     └─────────┘                                 Channel deleted
          
   At any time while Active:
     Consumer calls cooperativeClose() with provider signature
       ──► Provider receives finalAmount, Consumer receives (deposit - finalAmount)
           Channel deleted
```

A channel is **Active** from creation until it is closed or deleted. There is no separate "funded" state — the channel is funded at creation.

A channel is **Expired** when `block.timestamp >= expiry`. The provider is permitted to call `claim` on an expired channel, provided the channel has not been deleted. The consumer can only call `close` after the channel has expired.

A channel is **Closed** (deleted) after `close()` or `cooperativeClose()` completes. Closed channels SHOULD be deleted from contract storage. There is no on-chain distinction between a channel that was closed and a channel that never existed — both return zero values from `getChannel`.

`cooperativeClose` is permitted regardless of expiry status. It MAY be called both before and after the channel has expired.

### Core Functions

#### `open`

```solidity
function open(address provider, uint256 amount, uint256 duration) external returns (bytes32 channelId);
```

Creates a new payment channel.

- SHALL revert if `provider` is the zero address.
- SHALL revert if `amount` is zero.
- SHALL revert if `duration` is zero.
- SHALL transfer `amount` of the payment token from `msg.sender` to the contract (escrow).
- SHALL set `consumer = msg.sender`, `provider = provider`, `deposit = amount`, `claimed = 0`, `expiry = block.timestamp + duration`.
- SHALL return a unique `channelId`.
- SHALL emit `ChannelOpened`.

The caller MUST have approved the contract to spend at least `amount` of the payment token before calling `open`. Implementations MAY support [EIP-2612](https://eips.ethereum.org/EIPS/eip-2612) `permit` to allow gasless approval via signature.

#### `claim`

```solidity
function claim(bytes32 channelId, uint256 amount, uint256 nonce, bytes calldata signature) external;
```

Provider claims payment using the consumer's signed voucher.

- SHALL revert if the channel does not exist.
- SHALL revert if `msg.sender` is not the channel's `provider`.
- SHALL revert if `amount <= channel.claimed` (no new funds to claim).
- SHALL revert if `amount > channel.deposit`.
- SHALL recover the signer from the [EIP-712](https://eips.ethereum.org/EIPS/eip-712) typed data signature (see Voucher Schema below) and revert if the recovered address is not the channel's `consumer`.
- SHALL transfer `(amount - channel.claimed)` of the payment token to the provider (minus optional platform fee).
- SHALL update `channel.claimed = amount`.
- SHALL emit `ChannelClaimed`.
- If a platform fee is configured, SHALL transfer the fee amount to the treasury and emit `FeePaid`.

The `nonce` parameter is included in the signed message for replay protection but is not required to be validated on-chain. Off-chain, providers SHOULD reject vouchers with non-increasing nonces.

#### `close`

```solidity
function close(bytes32 channelId) external;
```

Consumer closes an expired channel and reclaims remaining deposit.

- SHALL revert if the channel does not exist.
- SHALL revert if `msg.sender` is not the channel's `consumer`.
- SHALL revert if `block.timestamp < channel.expiry`.
- SHALL transfer `(channel.deposit - channel.claimed)` to the consumer.
- SHALL delete the channel from storage.
- SHALL emit `ChannelClosed`.

#### `cooperativeClose`

```solidity
function cooperativeClose(bytes32 channelId, uint256 finalAmount, bytes calldata providerSignature) external;
```

Consumer closes a channel with the provider's consent. This function is permitted regardless of whether the channel has expired.

- SHALL revert if the channel does not exist.
- SHALL revert if `msg.sender` is not the channel's `consumer`.
- SHALL revert if `finalAmount > channel.deposit`.
- SHALL recover the signer from the [EIP-712](https://eips.ethereum.org/EIPS/eip-712) typed data signature (see CloseAuthorization Schema below) and revert if the recovered address is not the channel's `provider`.
- If `finalAmount > channel.claimed`, SHALL transfer `(finalAmount - channel.claimed)` to the provider (minus optional platform fee) and update `claimed`.
- SHALL transfer `(channel.deposit - finalAmount)` to the consumer.
- SHALL delete the channel from storage.
- SHALL emit `ChannelClaimed` (for the provider's portion, if any).
- SHALL emit `ChannelClosed` (for the consumer's refund).
- If a platform fee is charged, SHALL emit `FeePaid`.

#### `getChannel`

```solidity
function getChannel(bytes32 channelId) external view returns (
    address consumer,
    address provider,
    uint256 deposit,
    uint256 claimed,
    uint256 expiry
);
```

Returns channel state. SHALL return zero values for non-existent channels.

#### `getBalance`

```solidity
function getBalance(bytes32 channelId) external view returns (uint256);
```

Returns `deposit - claimed` for the given channel. SHALL return `0` for non-existent channels.

### EIP-712 Typed Data Schemas

All signatures in this protocol use [EIP-712](https://eips.ethereum.org/EIPS/eip-712) typed structured data signing.

#### Domain Separator

Implementations SHALL use the following EIP-712 domain:

| Field | Value |
| --- | --- |
| `name` | Implementation-defined string. Implementations SHOULD use a descriptive name (e.g. `"PaymentChannel"`). Note: two implementations with different domain names produce incompatible signatures. Cross-implementation voucher portability requires matching domain names. |
| `version` | `"1"` |
| `chainId` | The chain ID where the contract is deployed |
| `verifyingContract` | The address of the payment channel contract |

#### Voucher Schema

Vouchers are signed by the **consumer** and presented to the **provider** off-chain as proof of payment authorization.

```solidity
struct Voucher {
    bytes32 channelId;  // The channel this voucher applies to
    uint256 amount;     // Cumulative amount authorized (NOT incremental)
    uint256 nonce;      // Monotonically increasing sequence number
}
```

The EIP-712 type hash:

```
Voucher(bytes32 channelId,uint256 amount,uint256 nonce)
```

**Critical**: The `amount` field is **cumulative**, not incremental. A voucher with `amount = 500000` authorizes the provider to claim up to 500,000 token units total, regardless of how many previous vouchers were issued. Each new voucher supersedes all previous vouchers for the same channel.

The `nonce` field SHALL be monotonically increasing within a channel. Providers SHOULD reject vouchers where `nonce <= lastSeenNonce` for that channel. The contract MAY ignore the nonce during on-chain claim (since only the cumulative amount matters for settlement), but it MUST be included in the signed message to prevent signature reuse across different payment contexts.

#### CloseAuthorization Schema

Close authorizations are signed by the **provider** to consent to early channel closure.

```solidity
struct CloseAuthorization {
    bytes32 channelId;   // The channel to close
    uint256 finalAmount; // Final cumulative amount the provider is owed
}
```

The EIP-712 type hash:

```
CloseAuthorization(bytes32 channelId,uint256 finalAmount)
```

### Events

Implementations SHALL emit the following events:

```solidity
event ChannelOpened(
    bytes32 indexed channelId,
    address indexed consumer,
    address indexed provider,
    uint256 deposit,
    uint256 expiry
);

event ChannelClaimed(
    bytes32 indexed channelId,
    address indexed provider,
    uint256 amount
);

event ChannelClosed(
    bytes32 indexed channelId,
    address indexed consumer,
    uint256 refund
);
```

Implementations that charge a platform fee SHOULD emit:

```solidity
event FeePaid(
    bytes32 indexed channelId,
    address indexed recipient,
    uint256 amount
);
```

### Fees (OPTIONAL)

Implementations MAY charge a platform fee (in basis points) deducted from provider payments on `claim` and `cooperativeClose`. The fee SHALL be deducted only from the provider's portion (never from the consumer's refund). If present, the fee SHOULD be sent to a configurable treasury address.

### HTTP Integration (OPTIONAL)

For HTTP-based service providers, this specification RECOMMENDS the following integration pattern using HTTP 402 (Payment Required):

#### Discovery

When an unauthenticated request arrives, the provider SHOULD respond with HTTP 402 and the following headers:

| Header | Description | Example |
| --- | --- | --- |
| `X-Payment-Protocol` | Protocol identifier | `payment-channel-v1` |
| `X-Payment-Provider` | Provider's wallet address | `0xABC...` |
| `X-Payment-Contract` | Payment channel contract address | `0xDEF...` |
| `X-Payment-Chain` | Chain ID | `137` |
| `X-Payment-Signing` | URL to fetch EIP-712 signing parameters | `https://example.com/api/signing` |

#### Authenticated Requests

The consumer SHALL include a signed voucher in each request via a header:

```
X-Payment-Voucher: {"channelId":"0x...","amount":"1000000","nonce":"1","signature":"0x..."}
```

The header value is a JSON object containing the voucher fields and the EIP-712 signature. The `amount` and `nonce` fields are decimal string representations of `uint256` values.

#### Cooperative Close Endpoint

Providers SHOULD expose an endpoint for consumers to request a close authorization:

```
POST /v1/close-channel
Content-Type: application/json

{"channelId": "0x..."}
```

Response:

```json
{
    "channelId": "0x...",
    "finalAmount": "500000",
    "signature": "0x..."
}
```

## Rationale

### Off-chain vouchers over on-chain state channels

Full state channels (bidirectional, with dispute periods) provide stronger guarantees but require significantly more complexity: challenge periods, watchtowers, and multiple rounds of on-chain interaction. For unidirectional service payments where the consumer always pays and the provider always delivers, the voucher model provides equivalent security with far less overhead.

### Cumulative amounts over incremental

Vouchers use cumulative amounts (`amount = total owed so far`) rather than incremental amounts (`amount = this payment only`). This simplifies settlement: the provider only needs to submit the single highest voucher to claim all owed funds. There is no need to aggregate or order multiple vouchers on-chain.

### Cooperative close

Without cooperative close, a consumer must wait until channel expiry to reclaim unused funds. This creates a capital efficiency problem: funds are locked for the full channel duration even if the interaction ends early. Cooperative close allows immediate settlement when both parties agree, requiring only a single provider signature.

### EIP-712 signatures

EIP-712 typed data signatures (rather than raw `eth_sign`) provide:
- Human-readable signing prompts in wallet UIs.
- Domain separation preventing cross-contract and cross-chain replay.
- Structured data that can be parsed and displayed by wallets and tools.

### No on-chain nonce tracking

The contract validates only the cumulative amount and the signature. Nonce ordering is enforced off-chain by the provider. This reduces gas costs (no storage writes for nonce tracking) while maintaining security: the provider is incentivized to accept only increasing nonces, and the on-chain claim only cares about the total amount authorized.

### Minimal surface

This standard deliberately excludes:
- **Discovery and negotiation**: How consumers find providers is out of scope. Marketplaces, registries, and protocols like MCP handle this.
- **Pricing models**: Per-token, per-request, tiered — left to the application layer.
- **Reputation**: Job outcome signals belong in complementary standards (e.g. [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004), [ERC-8183](https://eips.ethereum.org/EIPS/eip-8183)).
- **Dispute resolution**: The channel model has no disputes. The consumer controls spend rate; the provider can claim at any time. If either party misbehaves, the other stops interacting.
- **Multi-hop or routed payments**: This standard covers direct consumer-to-provider channels only.

## Backwards Compatibility

No backward compatibility issues found.

## Test Cases

### Channel Lifecycle

1. **Open**: Consumer approves token spend, calls `open(provider, 1000000, 86400)`. Contract pulls 1,000,000 tokens, emits `ChannelOpened` with the returned `channelId`. After this call, `getChannel(channelId).deposit` MUST equal `1000000` and `getChannel(channelId).claimed` MUST equal `0`.

2. **Voucher signing**: Consumer signs `Voucher{channelId, amount: 100000, nonce: 1}` using EIP-712. Provider verifies signature off-chain, delivers service.

3. **Claim**: Provider calls `claim(channelId, 100000, 1, signature)`. Contract transfers 100,000 tokens to provider. After this call, `getChannel(channelId).claimed` MUST equal `100000` and `getBalance(channelId)` MUST equal `900000`.

4. **Subsequent voucher and claim**: Consumer signs `Voucher{channelId, amount: 250000, nonce: 2}`. Provider calls `claim(channelId, 250000, 2, signature)`. Contract transfers `250000 - 100000 = 150000` to provider. After this call, `getChannel(channelId).claimed` MUST equal `250000`.

5. **Close after expiry**: After expiry, consumer calls `close(channelId)`. Contract transfers `1000000 - 250000 = 750000` to consumer, deletes channel. After this call, `getChannel(channelId)` MUST return zero values for all fields.

### Cooperative Close

1. Consumer opens channel with deposit 1,000,000 and duration 86400.
2. Consumer sends vouchers for 300,000 total.
3. Consumer requests close from provider. Provider signs `CloseAuthorization{channelId, finalAmount: 300000}`.
4. Consumer calls `cooperativeClose(channelId, 300000, providerSignature)`.
5. Contract transfers 300,000 to provider (minus fee), 700,000 to consumer, deletes channel. After this call, `getChannel(channelId)` MUST return zero values.

### Edge Cases

- `claim(channelId, amount, nonce, sig)` where `amount <= getChannel(channelId).claimed` MUST revert.
- `claim(channelId, amount, nonce, sig)` where `amount > getChannel(channelId).deposit` MUST revert.
- `claim` with signature from an address other than `getChannel(channelId).consumer` MUST revert.
- `close(channelId)` where `block.timestamp < getChannel(channelId).expiry` MUST revert.
- `cooperativeClose` with a signature from an address other than `getChannel(channelId).provider` MUST revert.
- `open(address(0), amount, duration)` MUST revert.
- `open(provider, 0, duration)` MUST revert.
- `open(provider, amount, 0)` MUST revert.

## Reference Implementation

A production implementation of this standard is deployed on Polygon Mainnet as DrainChannelV2:

| Component | Address |
| --- | --- |
| Payment Channel Contract | `0x0C2B3aA1e80629D572b1f200e6DF3586B3946A8A` |
| Payment Token (USDC) | `0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359` |

EIP-712 domain name: `DrainChannel`, version: `1`, chain ID: `137`.

The reference implementation includes a 2% platform fee (200 basis points) deducted on claim and cooperative close, paid to a configurable fee wallet.

Source code: [https://github.com/handshake58/drain-protocol](https://github.com/handshake58/drain-protocol) *(TBD)*

## Security Considerations

### Voucher replay

EIP-712 domain separation (chain ID + contract address) prevents cross-chain and cross-contract replay. Within a channel, replay is harmless: claiming the same voucher twice has no effect because `amount <= claimed` causes a revert.

### Front-running

A front-runner observing a `claim` transaction in the mempool could extract the voucher signature. However, the `claim` function restricts the caller to the channel's provider (`msg.sender == provider`), so a front-runner cannot steal the claim. The same applies to `cooperativeClose` which restricts the caller to the consumer.

### Consumer protection

The consumer's maximum loss is bounded by the channel deposit. The consumer controls spend rate by choosing how quickly to increment voucher amounts. If the provider stops delivering, the consumer stops issuing vouchers. After expiry, the consumer reclaims all unspent funds via `close`.

### Provider protection

The provider can claim at any time. If the consumer disappears, the provider claims the latest voucher. If the channel is about to expire, the provider should claim before expiry to avoid racing the consumer's `close` call. Implementations SHOULD implement auto-claim logic that monitors channel expiry and claims proactively.

### Griefing via dust channels

A malicious consumer could open many small channels to force the provider to spend gas on claims. Providers SHOULD set minimum deposit thresholds and MAY batch claims across channels.

### Token safety

Implementations MUST use `SafeERC20` (or equivalent) for all token transfers to handle non-standard ERC-20 implementations that do not return a boolean.

### Reentrancy

Functions that transfer tokens SHALL be protected against reentrancy (e.g. via a reentrancy guard or checks-effects-interactions pattern).

### Expiry race condition

When a channel expires, both the provider (`claim`) and the consumer (`close`) may submit transactions simultaneously. If the consumer's `close` transaction is mined first, the channel is deleted and the provider's `claim` reverts — causing the provider to lose earned funds. Mitigations:

- Providers SHOULD claim well before expiry (e.g. one hour before). Implementations SHOULD include auto-claim logic that monitors channel expiry.
- Implementations MAY introduce a grace period after expiry during which only the provider can act (e.g. the consumer can only call `close` after `expiry + gracePeriod`). This is not required by the standard but is RECOMMENDED for production deployments.

### Fee-on-transfer tokens

Some ERC-20 tokens deduct a fee on `transfer` or `transferFrom`, causing the contract to receive fewer tokens than the `amount` parameter. If such a token is used as the payment token, `channel.deposit` will not reflect the actual escrowed balance. Implementations SHOULD NOT use fee-on-transfer tokens, or SHOULD record the actual received amount (via balance-before/after measurement) as the deposit.

### Signature malleability

ECDSA signatures have a known s-value malleability issue ([EIP-2](https://eips.ethereum.org/EIPS/eip-2)). While this is largely harmless in this protocol (since `claim` is restricted to the provider and the outcome is identical regardless of signature form), implementations SHOULD normalize signatures to low-s values using a library such as OpenZeppelin's ECDSA.

### Block timestamp manipulation

Miners can manipulate block timestamps by approximately 15 seconds. For channels with very short durations (under a few minutes), this could affect expiry logic. Implementations SHOULD enforce a minimum channel duration (e.g. 1 hour) to make timestamp manipulation negligible.

### Cooperative close trust

The provider signs a `CloseAuthorization` reflecting the highest voucher received. A dishonest provider could sign a lower `finalAmount` than actually received, causing the consumer to receive a larger refund than deserved. However, this only harms the provider (who forfeits earned funds), so there is no incentive to do so.

A dishonest consumer could present a `cooperativeClose` with a stale provider signature (lower `finalAmount` than the provider intended). This is prevented by the provider only signing `CloseAuthorization` on explicit request and using the current highest voucher amount.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
