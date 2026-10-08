---
title: Settlement-Decoupled Nanopayment Ledger
description: A settlement-decoupled fiat nanopayment ledger with three-party authorization and independently signed batching.
author: Zhe Han (@iampkuhz), Dasong Ji, Yunyi Zhu, Qinwei Fu, Xiaoyu Liu, Shenglong chen
discussions-to: https://ethereum-magicians.org/t/proposal-settlement-decoupled-nanopayment-ledger/29919
status: Draft
type: Standards Track
category: ERC
created: 2026-10-08
requires: 712, 1271, 2098, 5267
---

## Abstract

This proposal defines a shared ledger for fiat nanopayments, with publicly visible data and no token semantics. Each contract instance serves one Payment Network. The Payment Network, payer institution, and payee institution jointly authorize each Payment or Refund, which is recorded in four debit and credit accounts across the three parties. Individual requests and their signatures can be produced independently and submitted together in a Batch. Off-chain systems then use successfully posted records to debit users, transfer funds between institutions, and credit merchants. The contract does not issue, hold, or transfer payment assets; successful ledger posting does not imply completion of fiat processing.

## Motivation

1. **Support fiat nanopayments**: Metered services and agent-to-agent interactions require amounts smaller than a fiat currency's minor unit. A high-precision ledger records individual amounts, then aggregates and converts them while retaining rounding residuals for integration with existing fiat accounts.
2. **Decouple institutions through the payment network**: Payer and payee institutions incur payables or receivables only against the Payment Network, without directly maintaining accounts with their counterparty institutions.
3. **Maintain balanced accounting across three parties**: Each Payment and Refund updates four paired accounts across the payer institution, Payment Network, and payee institution. Every outstanding balance has a corresponding balance in its paired account.
4. **Batch independently signed requests**: The three parties sign only individual requests. Submitters can choose to submit them individually or assemble batches without obtaining new signatures.
5. **Use on-chain records to drive funds processing**: Institutions process their own fiat accounts based on verifiable records, using existing funds transfer infrastructure.

## Specification

The key words "MUST" and "MUST NOT" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174) when, and only when, they appear in all capitals.

### 1. Participants and Prerequisites

| Participant | Primary responsibilities |
|---|---|
| User | Initiates payments and uses the account and payment services provided by the Wallet |
| Merchant | Accepts user orders and submits payment or refund requests to the Acquirer |
| Wallet | The wallet institution manages user relationships, verifies user intent and ability to fund payments, authorizes Payments and Refunds, and is responsible for institutional statements and fiat processing on the user side |
| Acquirer | The acquiring institution manages merchant relationships, verifies orders and the basis for refunds, authorizes Payments and Refunds, and is responsible for institutional statements and merchant credits on the merchant side |
| Payment Network | Operates through one ledger contract instance, verifies compliance with network rules, and authorizes each request; records receivables from payer institutions and payables to payee institutions in its own books |

Participants use two types of systems. The **on-chain Settlement-Decoupled Nanopayment Ledger** validates requests and all three parties' signatures, maintains the four `debit`/`credit` accounts across the payer institution, Payment Network, and payee institution, and exposes events and queries. **Off-chain fiat systems** execute user debits, refunds, funds transfers, and merchant credits, and report their processing results independently. The `debit`/`credit` fields are accounting aggregates between institutions and the Payment Network, not token balances; an on-chain record does not indicate that fiat funds have moved.

Each deployment identifies its Payment Network authorizing party through the immutable signing address returned by `paymentNetwork()`. The EIP-712 domain actually used for signature verification is exposed through the ERC-5267 `eip712Domain()` function. The Payment Network address MUST differ from institution addresses. Before using the protocol, institutions MUST complete onboarding or obtain authorization under the deployment's rules. This proposal does not specify interfaces or data models for institution admission, suspension, rotation, or Wallet/Acquirer role assignment.

#### Customer Relationships and Three-Party Authorization

The Wallet and Acquirer manage their service relationships with the User and Merchant, respectively, and check account, authorization, and revocation status before signing. Core does not register, query, or evaluate `(account, institution)` relationships. The Payment Network, payer institution, and payee institution MUST explicitly sign the same individual typed request; the caller's identity cannot substitute for any signature. If the payer and payee institutions share the same address, one valid institution signature covers both institutional roles, but a separate Payment Network signature is still required.

Any address may submit an individual request or Batch with all required signatures. Three-party authorization means that each party accepts the transaction as recorded on-chain; it does not mean that Core independently establishes customer relationships, user intent, or fiat processing outcomes.

### 2. Service and Account Model

#### 2.1 Overview

1. The user requests a payment through a participating institution.
2. The payer institution, payee institution, and Payment Network verify the transaction and sign the request.
3. A submitter sends the authorized request on-chain, individually or in a batch.
4. The ledger validates the request and signatures, posts the accounting entries, and emits the corresponding events.
5. Institutions call `flush` on their agreed schedules to close their on-chain statements.
6. Off-chain fiat systems use the reconciled statements to perform settlement.

#### 2.2 Three-Party Accounting with Four Accounts

A transaction involves only three parties: the payer institution, Payment Network, and payee institution. The four-account model refers to four accounts arranged in pairs across these three parties, not a fourth participant. Each institution holds the `debit` and `credit` amounts of its current statement in `institutionState[institution]`; the Payment Network holds its own `debit` and `credit` amounts in the single `networkState`.

| Account pair | Left-hand account | Right-hand account | Meaning |
|---|---|---|---|
| Payer institution–network | Payer institution `debit` | Payment Network `credit` | The payer institution's current payable to the network is paired with the network's current receivable from that institution |
| Network–payee institution | Payment Network `debit` | Payee institution `credit` | The network's current payable to the payee institution is paired with that institution's current receivable from the network |

A `pay` operation for amount `A` updates all four accounts together:

```text
institutionState[payerInstitution].debit += A
networkState.credit                       += A
networkState.debit                        += A
institutionState[payeeInstitution].credit += A
```

A `refund` makes corresponding entries in the opposite payment direction: the original payee institution becomes the paying side, and the original payer institution becomes the receiving side.

```text
institutionState[originalPayeeInstitution].debit += A
networkState.credit                               += A
networkState.debit                                += A
institutionState[originalPayerInstitution].credit += A
```

The `flush` operation closes each institution's statement independently. If the institution currently has `debit = D` and `credit = C`, it records both amounts in `Flushed`, resets both institutional balances to zero, subtracts `D` from `networkState.credit` and `C` from `networkState.debit`, and increments that institution's `currentStatementId`. These operations MUST be atomic. If the institution has balances on both sides, both account pairs MUST be reduced together. The operation MUST NOT reset the network's entire aggregate balances or change other institutions' balances or any individual paymentState. Closing a statement moves it into history reconstructible from events; it does not signify completion of fiat settlement. Calling conditions and the complete state transition are specified in Section 3.5.

All outstanding balances therefore satisfy the following two paired invariants after every Payment, Refund, and Flush. Together, they imply equality of aggregate debits and credits. A Batch applies the same Payment or Refund updates using the sum of its items' amounts.

```text
Σ institutionState[institution].debit = networkState.credit
networkState.debit = Σ institutionState[institution].credit
```

When the same institution is on both the paying and receiving sides, both its `debit` and `credit` increase. Implementations MUST combine these updates within the same state word so that neither overwrites the other. Institutions' internal customer asset, customer liability, income, expense, and funds accounts belong to their off-chain general ledgers; this proposal does not standardize those internal offsetting accounts.

### 3. Data Structures and Interfaces

#### 3.1 Data Types and Complete Declarations

The declarations below define the complete ABI of `INanopaymentCore`.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @notice Both sides of an institution's current statement; the three fields occupy 224 bits in total.
struct InstitutionState {
    uint32 currentStatementId; // Institution statement number; Batch calls do not create or close statements or increment this number.
    uint96 debit; // The institution's payable to the Payment Network when acting as the paying side.
    uint96 credit; // The institution's receivable from the Payment Network when acting as the receiving side.
}

/// @notice The Payment Network's current outstanding aggregates across all institutions; the two fields occupy 192 bits in total.
struct NetworkState {
    uint96 debit; // Payables to payee institutions, equal to the sum of all institutions' credit amounts.
    uint96 credit; // Receivables from payer institutions, equal to the sum of all institutions' debit amounts.
}

/// @notice The complete signed payload for an individual payment.
/// @dev paymentId is a globally unique Payment instruction identifier that must never be reused; paymentId, participant account and institution addresses, and amount must be nonzero.
struct PaymentRequest {
    bytes32 paymentId;
    address payer;
    address payerInstitution;
    address payee;
    address payeeInstitution;
    uint96 amount;
    uint48 expiresAt;
}

/// @notice The complete signed payload for a refund, bound to the original payment's current state through paymentId and expectedRefundedAmount.
/// @dev refundId is a globally unique Refund instruction identifier that must never be reused and is associated with only one paymentId; refundId must be nonzero.
struct RefundRequest {
    bytes32 paymentId;
    bytes32 refundId;
    uint96 amount;
    uint96 expectedRefundedAmount;
    uint48 expiresAt;
}

/// @notice One party's signature on an individual request; party is the Payment Network or the relevant institution.
struct PartyAuthorization {
    address party;
    bytes signature;
}

/// @notice A complete authorized Payment that can be submitted individually or included directly in a batch.
struct AuthorizedPayment {
    PaymentRequest request;
    PartyAuthorization[] authorizations;
}

/// @notice A complete authorized Refund that can be submitted individually or included directly in a batch.
struct AuthorizedRefund {
    RefundRequest request;
    PaymentRequest originalPayment;
    PartyAuthorization[] authorizations;
}

/// @notice Core interface for payments, refunds, batch submission, institution statement closing, and ledger state queries.
interface INanopaymentCore {
    /// @notice Emitted once for each successfully posted Payment, with the public fields needed to reconstruct the original request.
    event PaymentPosted(
        bytes32 indexed paymentId,
        address payer,
        address indexed payerInstitution,
        address payee,
        address indexed payeeInstitution,
        uint96 amount,
        uint48 expiresAt
    );
    /// @notice Emitted once for each successfully posted Refund; institution fields retain the original Payment's payer/payee order, not the refund direction.
    event RefundPosted(
        bytes32 indexed paymentId,
        bytes32 refundId,
        address indexed originalPayerInstitution,
        address indexed originalPayeeInstitution,
        uint96 amount,
        uint96 refundedAmount
    );
    /// @notice Emitted when an institution closes its current statement, recording both amounts before reset and the corresponding reductions in network state.
    event Flushed(address indexed institution, uint32 indexed statementId, uint96 debit, uint96 credit);

    /// @notice Verifies three-party authorization of an individual PaymentRequest and atomically records the payment.
    function pay(PaymentRequest calldata request, PartyAuthorization[] calldata authorizations) external;

    /// @notice Verifies three-party authorization of an individual RefundRequest, binds it to the original payment, and atomically records the refund.
    function refund(
        RefundRequest calldata request,
        PaymentRequest calldata originalPayment,
        PartyAuthorization[] calldata authorizations
    ) external;

    /// @notice Atomically records multiple payments for the same institution pair using each item's existing individual signatures.
    function batchPay(AuthorizedPayment[] calldata payments) external;

    /// @notice Atomically records multiple refunds for the same institution pair using each item's existing individual signatures.
    function batchRefund(AuthorizedRefund[] calldata refunds) external;

    /// @notice Closes both sides of an institution's current statement, reduces the paired network balances, resets the institutional aggregates, and increments the statement number.
    function flush(address institution, uint32 expectedStatementId) external;

    /// @notice Returns, per ERC-5267, the EIP-712 domain actually used to verify Payment and Refund signatures.
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );

    /// @notice Returns the Payment Network signing address for this deployment.
    function paymentNetwork() external view returns (address);

    /// @notice Returns the deployment's immutable currency: an ISO 4217 code of exactly three uppercase ASCII characters.
    function currency() external view returns (string memory);

    /// @notice Returns the deployment's immutable number of decimal places for amounts.
    function decimals() external view returns (uint8);

    /// @notice Returns an institution's debit, credit, and statement number for its current open statement; historical queries are not provided.
    function institutionState(address institution) external view returns (InstitutionState memory);

    /// @notice Returns the Payment Network's current outstanding debit and credit aggregates; historical queries are not provided.
    /// @dev debit equals the sum of all institutions' current credit amounts; credit equals the sum of their current debit amounts.
    function networkState() external view returns (NetworkState memory);

    /// @notice Returns the single-slot state commitment keccak256(abi.encode(P, refundedAmount)) for paymentId, where P is the PaymentRequest hashStruct; zero means not yet recorded.
    /// @dev A nonzero value prevents duplicate posting and validates subsequent refunds; original request fields cannot be recovered from it. See Section 3.3 for the commitment rules.
    function paymentState(bytes32 paymentId) external view returns (bytes32);

    /// @notice Returns the paymentId associated with a successfully recorded refundId; zero means that refundId has not yet been recorded.
    /// @dev A refundId can be successfully recorded only once in this Ledger; paymentId is nonzero, so zero serves as the sentinel for an unrecorded refund.
    function refundPaymentId(bytes32 refundId) external view returns (bytes32);
}
```

The interpretation of amounts MUST be immutable for each Ledger deployment. The `currency()` function MUST always return a valid ISO 4217 code consisting of exactly three uppercase ASCII characters. The value of `decimals()` is selected for the deployment and MUST remain unchanged. All `amount`, `debit`, `credit`, and cumulative refunded amounts are expressed in units of `10^-decimals()` of that currency. Implementations MUST NOT change either return value through configuration, governance, or upgrades. A change of currency or precision requires a new Ledger deployment; outstanding signed requests and historical events in an existing deployment MUST NOT be reinterpreted using different currency or precision settings.

#### 3.2 Three-Party Signing and Submission Flow

##### 1. Transaction Authorization

1. The user initiates a payment or refund request through the Acquirer.
2. The Acquirer verifies the merchant-side transaction and sends the request and its signature to the Payment Network.
3. The Payment Network forwards the same request to the Wallet for verification and signature.
4. The Wallet verifies the user-side transaction and returns its signature.
5. The Payment Network verifies network rules, signs the same request, and collects all three parties' signatures.

1. **Illustrative allocation of responsibilities**: The Network collects signatures and submits requests in this example; neither the business entry point nor the signing order is fixed.
2. **Open collection and submission**: Any participant or service may perform either function, and the two responsibilities may be separated.

##### 2. On-Chain Posting

6. The Payment Network calls `pay` or `refund` with the request and all three parties' signatures.
7. The ledger validates the request and signatures, updates all four accounts and the individual transaction state, and emits `PaymentPosted` or `RefundPosted`.

1. **Calling does not replace signing**: All three parties MUST authorize the same complete digest. The Network MUST supply its signature even when it submits the request itself.
2. **Shared events**: Each party monitors the same Posted logs independently. Failure reverts the call without emitting a success event.
3. **Batch reuses individual authorizations**: Signed requests for the same institution pair can be batched directly without new batch signatures. Failure reverts the entire Batch; see Section 3.4.

##### 3. Flush and Off-Chain Funds Processing

8. The Wallet calls `flush` to close its statement on its own schedule.
9. The ledger records the Wallet's period payables and receivables in `Flushed`, resets the Wallet's aggregates, and subtracts the corresponding network amounts.
10. The Wallet reconciles its closed statement and creates off-chain funds processing tasks.

1. **Independent statement closing**: The diagram illustrates the Wallet; the same process applies to the Acquirer. Institutions follow independent statement cycles and do not wait for each other. They arrange funds processing after reconciling the closed statement; Flush does not signify completion of fiat processing.
2. **Statement reconstruction**: Off-chain systems obtain statement payable and receivable totals from `Flushed`, associate them with transaction details, and reconcile the amounts. See Section 3.5 for reconstruction rules.

#### 3.3 `pay` and `refund`: Individual Requests and State

##### Shared Request and Signature Rules

The `expiresAt` field is the first Unix timestamp, in seconds, at which the request is invalid. Execution MUST satisfy `block.timestamp < expiresAt`. A Refund does not recheck the original Payment's expiry.

The signed payloads are the `PaymentRequest` and `RefundRequest` declared in Section 3.1. EIP-712 type names, field names, field types, and field order MUST match those declarations. Type encoding and digests are computed according to [EIP-712](https://eips.ethereum.org/EIPS/eip-712#definition-of-encodetype).

The domain used for each signature MUST match the actual verification domain returned by `eip712Domain()`. Its `fields` and `extensions` describe the fields and extensions used by that domain, as specified by ERC-5267. This proposal does not prescribe the domain's field set or specific values for salt, extensions, or `verifyingContract`. The `paymentNetwork()` address is not repeated in requests: the contract identifies the network signer from immutable configuration. Neither `currency()` nor `decimals()` is included in requests or the domain, because Section 3.1 makes their interpretation of amounts immutable for the deployment.

Each digest MUST be explicitly signed by `paymentNetwork()`, the payer institution, and the payee institution. The `PartyAuthorization[]` array MUST contain all and only the required addresses, without duplicates; the caller's address does not count as a signature. When the payer and payee institutions are the same, one institution signature covers both roles, so signatures from two distinct parties are required. Otherwise, three signatures are required.

Each signature is verified against the complete EIP-712 digest. For signers with no code at execution time, implementations MUST accept both canonical 65-byte and ERC-2098 64-byte encodings, and reject invalid `v` values, high `s` values, recovery to the zero address, and recovered addresses that do not match the signer. For signers with code at execution time, implementations MUST pass the signature bytes unchanged in a read-only ERC-1271 call and accept only `0x1626ba7e`. A failed call MUST NOT fall back to ECDSA verification. Account type and contract validation policy MUST be evaluated from execution-time state and MUST NOT be cached.

The `paymentId` and `refundId` fields identify immutable Payment and Refund instructions, respectively. Adopters MUST generate globally unique identifiers within their business domain and preserve that uniqueness permanently: an identifier MUST never be signed as part of a different instruction. If the amount, `expectedRefundedAmount`, `expiresAt`, or any other field of a signed Refund MUST change, a new refundId MUST be used. An identical complete request that has not been successfully recorded may be retried unchanged. Core can enforce duplicate prevention only within its own Ledger; off-chain systems MUST still retain chain, Ledger, and event provenance to locate records and handle reorganizations.

All validation for `pay` and `refund` MUST complete before any writes. Statement updates, state updates, and events MUST either all succeed or all revert.

##### `pay`

1. **State precondition**: `paymentState(paymentId)` MUST be zero. Once successfully recorded, that paymentId MUST NOT be recorded again.
2. **Ledger updates**: Update the four accounts in the Payment direction specified in Section 2.2.
3. **State commitment**: Let `P` be `hashStruct(PaymentRequest)` computed according to EIP-712, excluding the domain. Store `keccak256(abi.encode(P, uint96(0)))`. Signature verification still uses the complete EIP-712 digest containing the domain and `P`.

##### `refund`

1. **Binding to the original payment and identifier**: The caller supplies the original `PaymentRequest`. The contract recomputes `P` and requires the current state to equal `keccak256(abi.encode(P, expectedRefundedAmount))`. The value of `refundPaymentId(refundId)` MUST be zero.
2. **Refund limit**: The amount MUST NOT exceed the original amount minus the cumulative refunded amount. At most one of multiple concurrent refunds starting from the same cumulative refunded amount may succeed.
3. **Ledger and state updates**: Update the four accounts in the Refund direction specified in Section 2.2, store `keccak256(abi.encode(P, expectedRefundedAmount + amount))`, and atomically record `refundPaymentId(refundId) = paymentId`. Any subsequent use of the same refundId MUST be rejected, whether it supplies the same or a different paymentId.

#### 3.4 `batchPay` and `batchRefund`: Reusing Individual Authorizations

A Batch array MUST be nonempty, and each call MUST contain requests for a single payer/payee institution pair. A `batchPay` array MUST NOT contain duplicate paymentId values. A `batchRefund` array MUST NOT contain duplicate paymentId or refundId values. Each item is subject to all checks for the corresponding individual entry point in Section 3.3. Core verifies authorizations individually; a single aggregate signature or authorization proof for the entire batch cannot replace those checks.

A Batch has no separate signing type or batch root. Individual signatures do not cover the time of batch assembly, array length, item position, or other items. A submitter may therefore add, remove, or reorder complete authorized requests that remain valid and unexecuted.

After all items pass validation, update the four accounts once using the aggregate amount, then store each item's state according to the individual request rules and emit success events in input order. Failure of any item or shared processing MUST revert the entire batch without partial results.

##### `batchPay`

Apply the Payment updates in Section 2.2 using the sum of all item amounts. Per-item state and events follow the rules for `pay`.

##### `batchRefund`

Apply the Refund updates in Section 2.2 using the sum of all item amounts. Binding to the original payment, refundId duplicate prevention, the expected cumulative refunded amount, refund limits, and per-item state and events follow the rules for `refund`.

#### 3.5 `flush`: Institution Statement Closing and History

This version does not define a fixed statement cycle enforced by the contract. Only `institution` itself or `paymentNetwork()` may call `flush`, and `expectedStatementId` MUST equal `currentStatementId`. Empty statements may be closed. Core does not block Flush based on institution eligibility or suspension status. On success, given the institution's current state `(debit, credit)`, `Flushed` records both amounts, and the contract MUST atomically perform:

```text
networkState.credit -= debit
networkState.debit  -= credit
institutionState[institution].debit  = 0
institutionState[institution].credit = 0
currentStatementId += 1
```

##### Events and Historical Reconstruction

Core stores no historical snapshots, transaction lists, or batch summary events. The paymentId and refundId are the business identifiers for Payment and Refund, respectively. A Refund is uniquely identified by its refundId and linked to the original payment through its associated paymentId. Off-chain systems retain `(chain, ledger)` as on-chain provenance and use `(blockHash, transactionHash, logIndex)` to locate an event occurrence. Event coordinates are used only to locate and order logs and rescan after reorganizations; they MUST NOT be used as idempotency keys for business operations or funds processing tasks. Canonical logs from the same deployment are ordered by `(blockNumber, transactionIndex, logIndex)`.

1. **Statement totals**: Locate `Flushed` using `(ledger, institution, statementId)`. Its `debit` is the statement's total payable, and its `credit` is the total receivable.
2. **Transaction details**: In log order, collect the `PaymentPosted` and `RefundPosted` events involving the institution after its previous `Flushed` and before its current `Flushed`. Statement 0 begins at deployment. A refund links to its original Payment through paymentId; that Payment may belong to an earlier statement.
3. **Amount reconciliation**: Accumulate payables and receivables separately from the transaction details, following the posting directions for payments and refunds. Both totals MUST match the corresponding amounts in the statement's `Flushed` event.

The same transaction may belong to different statements at the two institutions. Historical reconciliation combines an institution's `Flushed` amounts with its current `institutionState`. Each party retains requests and all three parties' signatures off-chain.

A future version that defines and validates fixed statement cycles could allow any address to trigger Flush once the cycle conditions are met. The caller would merely trigger execution, and the rules would have to prevent the same cycle from being closed twice. That model is not combined with this version's independent statement cycles.

### 4. Off-Chain Funds Processing

Institutions reconstruct transaction details from `PaymentPosted` and `RefundPosted`, and use `Flushed` to identify the scope of a closed statement. They create funds processing tasks after reconciling the statement. Receipt of an event does not imply that all conditions for funds processing have been met or that fiat processing is complete. An off-chain failure does not revert the on-chain ledger.

| Stage | Minimum requirements |
|---|---|
| Reconstruct the statement scope | Reconstruct `(ledger, institution, statementId)` as specified in Section 3.5. Link each Refund to its original Payment and reverse the account direction. If the same institution appears on both sides, accumulate receivables and payables separately |
| Execute funds processing tasks | Use paymentId for Payment and refundId for Refund as the business idempotency key. Each user debit, inter-institution funds transfer, or merchant credit task MUST additionally include the action type and executing institution. For Flush, `(chain, ledger, institution, statementId)` identifies the scope of the closed statement. Chain and Ledger identify provenance; they do not replace Payment/Refund business identifiers. Institutions handle failures, uncertain outcomes, and disputes through existing payment mechanisms |
| Record and reconcile | Retain the source transaction or closed statement scope, amounts at the original precision, conversion results, rounding residuals, and execution status. Specify units, rounding rules, and allocation of residuals. Retain scan progress to support rescanning and chain reorganizations |

Core does not maintain merchant balances, funds processing task status, or fiat outcomes, and does not prescribe algorithms for handling different currencies, negative net amounts, or rounding residuals. Adopters MUST prevent duplicate execution within the same processing scope and ensure that ledger aggregates at the original precision can be reconciled against processed amounts and remaining residuals.

### 5. Implementation Policies and Extensions

1. **Additional institutional checks**: Institutions may manage customer relationships, authorization revocation, and user limits before signing. Implementations may also maintain on-chain `(account, institution)` relationships and add checks for per-transaction, periodic, or cumulative limits, institution roles, call permissions, and account eligibility. This proposal does not standardize those states or administrative interfaces. Any policy that rejects new transactions MUST apply consistently to `pay`, `refund`, `batchPay`, and `batchRefund`, and MUST NOT prevent Flush of existing balances.
2. **Consistent limit enforcement**: On-chain limits may only impose additional rejection conditions. They MUST cover all affected individual and Batch entry points and specify whether and when Refund restores available limits, as well as the rules for concurrent updates. A failed limit check MUST revert the entire call. Such checks MUST NOT weaken three-party authorization or alter successful state transitions or events.
3. **Extension boundaries**: This version does not reserve an undefined extensionData field. Future extensions MUST define new types or interfaces and specify their version, validating parties, scope of validity, activation policy, and failure handling. Extension data MUST be included in the payload signed by all three parties and MUST NOT bypass any required signature. Amounts are public in this version; privacy is outside the scope of this version.

## Rationale

### Relationship Between Payment, Refund, and Batch

A Payment posts institutional statement entries in the payment direction and creates payment state that can be updated over time. A Refund differs in posting direction, request fields, and audit meaning, so it has its own function, signing type, and event. It does not create a separate payment state; it validates and updates the original Payment's cumulative refunded amount. The `expectedRefundedAmount` field prevents over-refunding and handles concurrency conflicts. The refundId is a globally unique identifier for an individual Refund instruction. On success, Core permanently binds it to one paymentId, allowing it to serve as an idempotency key for off-chain refund processing.

A Batch is not a third transaction type. It places multiple Payments or Refunds that already carry all three parties' signatures into one call. Each transaction retains the same request digest, signatures, identifiers, state, and events as the individual entry point. Batching shares the base transaction cost and statement access for the same institution pair without requiring any party to sign the batch again. Adopters choose the trade-off between batching delay and the scope of failure; this proposal does not prescribe batch sizes.

Core provides native Batch interfaces so that all four accounts for the same institution pair can be updated using an aggregate amount. Callers do not need to deploy a separate router to access batching. Retaining per-item authorization verification gives individual and Batch calls the same EOA and ERC-1271 authorization rules, without introducing separate cross-request authorization aggregation, proof generation, or verification-key management. Savings come from sharing common processing. Per-item state updates, events, and signature verification remain necessary, so a constant cost for an entire batch cannot be inferred.

This version does not define a Core-level ZK/BLS batch verification interface. This boundary governs only how Core accepts and verifies batches; ERC-1271 signing contracts remain free to choose their own validation policies. [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271#specification)

### Neutrality Across Submitters and Institutional Account Types

The Payment Network, Wallet, and Acquirer are responsible for network rules, the user side, and the merchant side, respectively. They must therefore explicitly authorize the same transaction. The submitter's identity neither changes the request nor replaces any party's signature. This allows the same individual authorization to be submitted through an individual entry point or later included in a Batch by a third party.

The Payment Network signing address and institution addresses may be externally owned accounts (EOAs) or ERC-1271 contracts. Supporting both canonical 65-byte and ERC-2098 64-byte EOA signatures avoids interoperability differences between implementations accepting equivalent encodings. ERC-1271 signatures remain opaque to accommodate smart accounts' own validation policies.

### Institutional Autonomy

Core records only payments jointly authorized by the payment network and institutions. It does not standardize institution admission, roles, customer relationships, authorization revocation, or statement cycles. An institution's authorization binds its responsibility to a specific request; `expiresAt` only limits that request's execution window. Neither means that Core independently verified user intent. The base protocol defines neither a general-purpose nonce nor a relationship revision. Implementations requiring real-time controls may add on-chain relationship or revocation checks, but only as additional rejection conditions.

A shared statement cycle would require institutions to close their periods in sync. Instead, each institution closes its statements independently. Either the institution itself or the Payment Network can trigger Flush according to its funds processing and reconciliation schedule. The trade-off is that the same transaction may fall under different statementId values at the two institutions, requiring separate off-chain reconstruction in event order.

### Allocation of Information Across Requests, State, and Events

Requests do not repeat fields already used in the actual EIP-712 domain; clients obtain those fields from `eip712Domain()`. Signature verification uses the complete EIP-712 digest, including the domain. For each Payment, on-chain state stores `keccak256(abi.encode(P, refundedAmount))`, where `P = hashStruct(PaymentRequest)` excludes the domain, for subsequent duplicate prevention and Refund validation. Each successful Refund also stores a permanent association from its refundId to its paymentId. This ensures that a domain change does not prevent subsequent state validation of already recorded Payments. The `PaymentPosted` event carries the data needed to reconstruct the original Payment; `RefundPosted` carries the refund outcome and both business identifiers. Other historical data and institution statements are reconstructed from event order. Request digests, actual submitters, and per-transaction statementId values can be derived from existing information and are therefore not repeated in events.

Storing a complete PaymentRecord would increase permanent storage per payment, while storing only an exists flag and cumulative refunded amount would not allow validation of the original participants, institutions, and amount supplied by the caller. A state hash preserves these validation capabilities in one storage slot. The trade-off is that a Refund must resupply the original Payment and institutions must have access to the corresponding events. An undefined extensionData field would not ensure consistent signing and validation semantics across implementations, so this version does not reserve one.

### Fiat Amounts and Field Widths

This proposal selects field widths based on the precision needed for fiat processing, reasonable amount ranges, and protocol lifetime, rather than defaulting to `uint256`. Deployments may select a `decimals()` value appropriate to their nanopayment use case. For both individual amounts and institutional aggregates, `uint96` represents up to `2^96 - 1` smallest ledger units; the corresponding range in whole fiat currency units depends on the deployment's precision. A `uint32` statement counter lasts approximately 136 years even with one Flush per second, allowing currentStatementId, debit, and credit to share one storage slot.

Fixing the currency and selected precision for the lifetime of a deployment prevents later getter changes from reinterpreting integer amounts in outstanding signed requests or public events. These values therefore need not be repeated in each request or in the EIP-712 domain. Changing currency or precision requires a new Ledger deployment. This amount representation does not introduce token balances or token transfer semantics. The `expiresAt` field uses Unix seconds, consistent with `block.timestamp`; it defines a request's validity window, not transaction ordering.

### On-Chain Posting and Off-Chain Funds Processing

On-chain Payments and Refunds are ledger records jointly authorized by the payment network and both institutions. Off-chain systems use those records to debit users, transfer funds between institutions, and credit merchants. Core cannot atomically verify final outcomes in external fiat systems, so off-chain failures do not delete or revert successful on-chain records. Retries, exception handling, and disputes remain the responsibility of the relevant payment processing mechanisms.

## Backwards Compatibility

This proposal introduces a new, opt-in application-layer interface and does not modify existing ERCs. Contracts and off-chain systems that do not integrate it are unaffected. Ledgers using different request, authorization, event, or state semantics are not automatically compatible; they may operate independently or integrate through adapters or new deployments. This proposal does not migrate their historical state, events, or signatures.

## Reference Implementation

A conforming reference implementation of the four-account model is not yet available. No gas benchmarks are claimed for this specification.

## Security Considerations

### Institutional Trust and Customer Authorization

Institutional authorization establishes only that the payment network and both institutions accept the same on-chain transaction. It does not establish that Core independently verified customer relationships, user intent, or fiat funds.

1. **Relationship revocation**: Core cannot prevent execution of an already signed request after a customer relationship changes. Institutions must check their own customer relationships before signing. Institutions using EOAs without a dynamic revocation mechanism rely primarily on short expiry windows through `expiresAt`; ERC-1271 or additional implementation policies can reject a request at execution time.
2. **Policy consistency**: On-chain relationship checks, institution roles, and other additional policies must cover all affected entry points so that a request cannot be routed through a weaker path. Implementations should also explain how policy changes affect outstanding requests.
3. **Continuing responsibility**: The Acquirer's obligations to the merchant for a successfully posted payment are not extinguished by a refund, a change in customer relationship, or a change of submitter. Funds arrangements and dispute handling remain governed by business rules.

### Signatures, Submission, and Replay

Permissionless submission does not allow a submitter to alter a request. Security depends on correctly enforcing the required signer set, complete digest, and signature verification rules in Section 3.3.

1. **Execution-time account validation**: Account code, ownership, or validation policies may change; signatures must be verified against execution-time state. Caching EOA/contract classifications, restricting ERC-1271 signature lengths, or falling back to ECDSA after ERC-1271 failure can bypass smart account policies. External validation calls also require protection against reentrancy.
2. **Protocol replay**: The EIP-712 type and actual verification domain separate signature scopes through the fields they use. The paymentId prevents replay of successful Payments, refundId prevents replay of successful Refunds, and `expiresAt` limits the execution window. Batches must also reject duplicates of the applicable identifiers within the input array.
3. **Identifier generation and duplicate business operations**: Core can only check whether an identifier has already been successfully recorded in its own Ledger; it cannot establish global uniqueness across deployments. Adopters must persist identifier generation records within their business domain, and must not use the same identifier for another signed request. For EOA signers, request fields cannot safely be replaced under the same identifier after signing. The protocol also cannot detect that different global identifiers refer to the same order or reason for refund; institutions must prevent such duplicates at the business layer. The `expectedRefundedAmount` field continues to handle conflicts over a Payment's cumulative refunded amount.

### Refund and Batch State Safety

All input validation, three-party signature verification, external calls, and arithmetic checks must complete before any successful state becomes observable. Failure must not leave partial statement updates, per-item state, or events.

1. **Binding to the original payment**: Neither the original request nor the cumulative amount supplied by the caller is trusted. They must match the current state commitment before their participants, amount, or institutions are used. Omitting this check could allow substitution of the refund's original payment or inflation of the refundable amount.
2. **Arithmetic, paired accounts, and same-address updates**: Refunds check the remaining refundable amount before addition. Institutional aggregates, NetworkState, and statementId use checked arithmetic. All four accounts for each Payment or Refund must be updated atomically. Flush must reduce the institution's amounts and the corresponding network balances together, reverting on any underflow. When the same institution is on both sides, debit and credit updates must be combined within the same state word so that neither overwrites the other.
3. **Batch atomicity**: Validate all items, check paymentId/refundId uniqueness and the aggregate amount, and only then update shared state for the payer institution, Payment Network, and payee institution, together with per-item state. Failure of any item reverts the entire Batch. A Refund of a Payment from an earlier statement is posted to the institutions' current statements at refund execution, while also updating the original Payment's state commitment and the refundId association.

### Events and Off-Chain Funds Processing

Success events establish ledger records, not completion of fiat processing. Reorganizations, duplicate event consumption, and uncertain acknowledgments can all trigger incorrect or duplicate funds movements.

1. **Idempotency and verification**: Prevent duplicate execution within an explicitly defined funds processing task scope, and retain on-chain and fiat processing status separately. Query an uncertain outcome before retrying.
2. **Chain reorganizations**: Event consumers must process records in accordance with the target chain's stability guarantees. If the source block changes after funds have been processed, initiate exception reconciliation rather than directly repeating the funds movement. This draft does not define automatic compensation or arbitration.
3. **Amount precision**: Retain the original precision, processing scope, and rounding residuals as specified in Section 4 to avoid per-transaction truncation or double counting across periods.
4. **Statement reconstruction**: Event consumers must process all success events and `Flushed` events from the same ledger, advancing each institution's statements in log order. If gaps, ordering conflicts, or reorganizations are detected, stop funds processing for the affected scope and rescan. Historical statement membership cannot be inferred from the `currentStatementId` returned at query time.

### Data Availability and Privacy

A single state hash neither retains historical transaction details nor conceals data disclosed in events.

1. **Historical data availability**: Institutions must retain or be able to retrieve `PaymentPosted` and `RefundPosted` events. Without the original Payment, Refund parameters cannot be reconstructed from the hash alone.
2. **Cryptography and versioning**: Digest security depends on Keccak-256 collision resistance and second-preimage resistance. Different protocol versions use separate deployments and signing domains; each deployment handles only its own state and events.
3. **Public data**: Amounts and account and institution addresses are publicly visible. Raw Know Your Customer (KYC) identity records should not be included in requests or events. This version does not provide privacy protection.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
