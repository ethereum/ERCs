---
title: Sealed-Bid Award Mechanism for Task Tenders
description: A commit-reveal award interface with pluggable pricing rules for competitive task tenders between agents
author: Shenton Yan (@shentonyan)
discussions-to: https://ethereum-magicians.org/t/sealed-bid-award-mechanism-for-task-tenders-companion-to-erc-8183-8195-8414/29814
status: Draft
type: Standards Track
category: ERC
created: 2026-10-01
requires: 20, 165
---

## Abstract

This ERC defines how a task posted for competitive fulfilment is awarded: which bidder wins and at what price. It specifies a sealed-bid procedure (commit, reveal, award), a stateless mechanism interface that computes the award from revealed bids, four normative pricing rules (first-price, second-price (Vickrey), uniform-price for multiple identical units, and posted-price), and two integration profiles that state what an award means to the standard that consumes it. Incentive properties such as truthful bidding under second-price hold only for price-binding integrations, in which the consumer pays the award price and executes every award; allocation-only integrations must use the posted-price rule. The contract that runs the procedure holds only bidder bonds; it never holds the task reward, judges a deliverable, or records reputation. It returns an award that an existing task-escrow standard such as [ERC-8183](./eip-8183.md) can consume.

## Motivation

Existing task-escrow designs describe how an agent posts a task, escrows the reward, and settles on delivery. None of them says how the task is awarded when more than one agent wants it. [ERC-8183](./eip-8183.md) runs bidding through an off-chain hook and receives only the outcome through `setProvider`. the task-market working draft has an Auction mode whose bids are relayed off-chain and whose rule is fixed to lowest-bid-wins. the token-bound task working draft states that bidding is a companion extension outside its kernel. Each market therefore writes its own award logic, agents encounter incompatible bidding rules, and no indexer can say what an award meant or whether the price was fair.

This ERC fills that gap with the smallest interface that makes an award auditable: bids are committed before they are seen, revealed together, and resolved by a pure function whose code anyone can read. The interface is deliberately narrow so that it composes with task-escrow protocols instead of replacing their settlement rules.

The interface separates allocation from payment, as in direct mechanisms in auction theory.[^1] Second-price is the recommended single-unit default because, in the private-cost, quasi-linear utility model with no collusion or externalities, truthful reporting is weakly dominant when the stated payment and execution commitments hold. This is not a claim that any plugin is truthful or that second-price minimizes procurement cost in every environment. Revenue equivalence requires additional assumptions, including equilibrium behavior and the same allocation and boundary utility; it does not make arbitrary pricing plugins economically interchangeable.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Terms

- **Requester**: the party that opens a tender and will pay the award.
- **Bidder**: an address that commits and reveals a bid. A bid is the price the bidder asks for performing the task.
- **Reserve**: the highest price the requester will pay. No bid above it may win.
- **Unit**: one identical instance of the task. A tender for a single task has one unit.
- **Mechanism**: a contract implementing `IAwardMechanism` that maps revealed bids to an award.
- **Award**: the set of winning bidders and the price each is paid.
- **Task content**: the description of the work that bidders price. A tender commits to it by hash in `contentHash`.
- **Target**: the task, job, or tender in another standard that this tender is run for. The companion produces an award for the target; it never acts on the target.

### Target reference

Every tender names its target by a single canonical commitment:

```solidity
targetRef = keccak256(abi.encode(chainId, targetContract, targetId));
```

where `chainId` is the chain on which `targetContract` is deployed and `targetId` is the target's identifier normalised to `bytes32`: an identifier that is already `bytes32` (such as a target's `jobId` or `taskId`) is used as is; a `uint256` identifier (such as a task token's `tokenId`) is left-padded with zero bytes. Implementations MUST compute `targetRef` with `abi.encode`, not `abi.encodePacked`.

### Payment denomination

Before bidding opens, the target or its authorised adapter MUST publish the payment asset and the integer unit used for `reserve`, every bid `amount`, and every award `price`. All three MUST use that same denomination. For an ERC-20 asset, amounts MUST be expressed in the token's smallest units; for the native asset, in its smallest units. `bondAsset` defines only the bond and MUST NOT be interpreted as the payment asset.

The target's content commitment described below MUST bind the payment asset, its chain, and this unit convention, together with the work description and the acceptance policy bidders rely on. These terms MUST remain fixed for this tender. An integration MUST NOT consume an award using another payment denomination.

### Award mechanism interface

A mechanism contract MUST implement the following interface and MUST return `true` from `supportsInterface(type(IAwardMechanism).interfaceId)` per [ERC-165](./eip-165.md).

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IAwardMechanism {
    struct Bid {
        address bidder;
        uint256 amount;   // price asked, in the tender's unit of account
    }

    struct Award {
        address winner;
        uint256 price;    // price paid to this winner
    }

    /// @notice Canonical identifier of the rule, e.g. bytes4(keccak256("award.vickrey")).
    function mechanismId() external pure returns (bytes4);

    /// @notice Compute the award from revealed bids.
    /// @dev MUST be pure. Bids are passed in commit order. An empty return means no award.
    /// @param bids    Revealed bids in commit order.
    /// @param reserve Highest acceptable price. MUST be > 0.
    /// @param units   Number of identical units to award. MUST be >= 1.
    function award(Bid[] calldata bids, uint256 reserve, uint256 units)
        external pure returns (Award[] memory);
}
```

`award` MUST satisfy all of the following:

1. It MUST be deterministic and MUST NOT read state.
2. Each returned `winner` MUST be the `bidder` of an entry in `bids`, and that entry's `amount` MUST NOT exceed `reserve`.
3. No returned `price` MAY exceed `reserve`.
4. Each returned `winner` MUST appear at most once, and the number of awards MUST NOT exceed `units`.
5. Lowering one bidder's `amount` while holding all other inputs fixed MUST NOT remove that bidder from the award. This is the monotonicity condition that incentive compatibility requires.
6. Ties on `amount` MUST be broken in favour of the bid that appears earlier in `bids`.
7. No returned `price` MAY be less than the winner's own `amount`.

The output of `award` MUST depend only on its arguments and MUST NOT change over the life of the mechanism contract. In particular a mechanism MUST NOT be upgradeable and MUST NOT delegate the computation to code that can be replaced.

### Normative mechanisms

Let the revealed amounts sorted ascending be b(1) ≤ b(2) ≤ … ≤ b(n), and let r be the reserve.

| `mechanismId` string | Winners | Price per winner | Award condition |
| --- | --- | --- | --- |
| `award.first-price` | lowest `units` bids | each winner's own bid | bid ≤ r |
| `award.vickrey` | lowest bid (units = 1) | min(b(2), r); r if n = 1 | b(1) ≤ r |
| `award.uniform-price` | lowest `units` bids | min(b(units+1), r); r if n ≤ units | bid ≤ r |
| `award.posted-price` | earliest `units` bids in commit order with bid ≤ r | r | bid ≤ r |

`award.vickrey` MUST revert if `units != 1`. The other three rules accept any `units >= 1`.

Under `award.posted-price` a bid at or below the reserve is an acceptance of the reserve as the price, and its amount has no other effect: a lower bid does not move a bidder ahead of an earlier acceptance. Bidders SHOULD bid exactly `r`.

A mechanism contract MAY implement a rule not listed here. Its `mechanismId` MUST be `bytes4(keccak256(<canonical string>))` for a string that is not one of the four above.

### Tender interface

A tender contract MUST implement the following interface and MUST return `true` from `supportsInterface(type(ISealedBidTender).interfaceId)`.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./IAwardMechanism.sol";

interface ISealedBidTender {
    enum Phase { None, Commit, Reveal, Awarded, Void }

    struct TenderTerms {
        bytes32 targetRef;       // canonical target commitment, see "Target reference"
        address mechanism;       // IAwardMechanism
        uint256 reserve;         // MUST be > 0
        uint256 units;           // MUST be >= 1
        uint64  commitDeadline;  // commits accepted while block.timestamp <= commitDeadline
        uint64  revealDeadline;  // reveals accepted while commitDeadline < block.timestamp <= revealDeadline
        uint256 bond;            // amount escrowed per commit
        address bondAsset;       // address(0) for the chain's native asset, else an ERC-20
        address slashRecipient;  // where slashed bonds go; MUST be non-zero when bond > 0
        uint256 maxBidders;      // commitments accepted; MUST be >= 1 and within the implementation's limit
        bytes4  integrationProfile; // see "Integration profiles"
        bytes32 contentHash;        // hash of the task content the bids price
    }

    event TenderOpened(
        bytes32 indexed tenderId,
        bytes32 indexed targetRef,
        address indexed requester,
        address mechanism,
        uint256 reserve,
        uint256 units,
        uint64 commitDeadline,
        uint64 revealDeadline,
        bytes4 integrationProfile,
        bytes32 mechanismCodehash
    );
    event BidCommitted(bytes32 indexed tenderId, address indexed bidder, bytes32 commitment);
    event BidRevealed(bytes32 indexed tenderId, address indexed bidder, uint256 amount);
    event BidSlashed(bytes32 indexed tenderId, address indexed bidder, uint256 bond);
    event TenderAwarded(bytes32 indexed tenderId, address indexed winner, uint256 price, bytes4 mechanismId);
    event TenderVoid(bytes32 indexed tenderId);
    event SlashClaimed(bytes32 indexed tenderId, address indexed recipient, uint256 amount);

    function openTender(TenderTerms calldata terms) external returns (bytes32 tenderId);
    function commitBid(bytes32 tenderId, bytes32 commitment) external payable;
    function revealBid(bytes32 tenderId, uint256 amount, bytes32 salt) external;
    function finalize(bytes32 tenderId) external returns (IAwardMechanism.Award[] memory);
    function claimSlashed(bytes32 tenderId) external returns (uint256 amount);

    function termsOf(bytes32 tenderId) external view returns (TenderTerms memory);
    function requesterOf(bytes32 tenderId) external view returns (address);
    function phaseOf(bytes32 tenderId) external view returns (Phase);
    function awardOf(bytes32 tenderId) external view returns (IAwardMechanism.Award[] memory);
    function slashedOf(bytes32 tenderId) external view returns (uint256);
    function mechanismCodehashOf(bytes32 tenderId) external view returns (bytes32);
}
```

### Tender lifecycle

**Opening.** `openTender` MUST revert unless `reserve > 0`, `units >= 1`, `commitDeadline > block.timestamp`, `revealDeadline > commitDeadline`, `mechanism` reports `IAwardMechanism` through ERC-165, either `bond == 0` or `slashRecipient != address(0)`, `maxBidders` is at least 1 and no greater than the implementation's limit, and `integrationProfile` is valid for the mechanism as set out under "Integration profiles". Implementations MUST choose that limit so that `finalize` with `maxBidders` revealed bids fits well within a block's gas limit, and SHOULD expose it. If `bondAsset` is not `address(0)` it MUST be a contract. `slashRecipient` MUST NOT be the requester. The caller is recorded as the requester. `tenderId` MUST be `keccak256(abi.encode(block.chainid, address(this), msg.sender, nonce))` where `nonce` is a per-requester counter incremented on each call. The contract MUST emit `TenderOpened` and set the phase to `Commit`.

**Committing.** `commitBid` MUST revert unless the phase is `Commit` and `block.timestamp <= commitDeadline`. The commitment MUST be `keccak256(abi.encode(tenderId, msg.sender, amount, salt))`; implementations MUST use `abi.encode`, not `abi.encodePacked`. An address MUST NOT commit more than once per tender, and `commitBid` MUST revert once `maxBidders` commitments have been accepted. The contract MUST take `bond` in `bondAsset` from the caller (for a native-asset bond, `msg.value` MUST equal `bond`; for an [ERC-20](./eip-20.md) bond, `msg.value` MUST be zero and the contract MUST pull exactly `bond` by `transferFrom`, accepting tokens that return no value) and MUST emit `BidCommitted`.

**Revealing.** `revealBid` MUST revert unless `commitDeadline < block.timestamp <= revealDeadline`, the caller has an unrevealed commitment for this tender, and `keccak256(abi.encode(tenderId, msg.sender, amount, salt))` equals that commitment. On success the contract MUST record the bid, MUST emit `BidRevealed`, and MUST return the caller's bond. The phase becomes `Reveal` on the first valid reveal or, if none arrives, remains `Commit` until finalization.

**Finalizing.** `finalize` is permissionless and MUST revert unless `block.timestamp > revealDeadline` and the phase is `Commit` or `Reveal`. The contract MUST revert if the mechanism's code hash differs from the one recorded at opening. It MUST call `mechanism.award(bids, reserve, units)` with the revealed bids in commit order, and MUST then check the result against the revealed bids, reverting unless every award satisfies all of the following: the winner revealed a bid in this tender; that bid is at most `reserve`; the price is at least that bid and at most `reserve`; no winner appears twice; and there are no more awards than `units`. These are conditions 2, 3, 4 and 7 of the award mechanism interface. None of them depends on the pricing rule. The mechanism is a third-party contract and the tender contract is the last check before an award reaches a target. If the result is non-empty the contract MUST store it, set the phase to `Awarded`, and emit one `TenderAwarded` per winner. If the result is empty the contract MUST set the phase to `Void` and emit `TenderVoid`. `Awarded` and `Void` are terminal: once either is set, the phase and the stored award MUST NOT change. In either case the contract MUST slash the bond of every committed bidder who did not reveal, emitting `BidSlashed` for each, and MUST credit the total slashed amount to the tender. `finalize` MUST NOT transfer slashed bonds itself, so that a `slashRecipient` that rejects payment cannot prevent an award.

**Claiming slashed bonds.** `claimSlashed` is permissionless. It MUST revert if nothing is credited, and otherwise MUST set the credit to zero, transfer it to `slashRecipient`, and emit `SlashClaimed`. `slashedOf` MUST return the current credit. `slashRecipient` MUST NOT be an address from which the requester can recover funds, directly or through the target. In particular it MUST NOT be the target's escrow or vault where funds sent there offset the requester's own contribution or return to the target's owner. The RECOMMENDED `slashRecipient` is a burn address.

**Pinning the mechanism.** `openTender` MUST record the mechanism's code hash (`EXTCODEHASH`) and emit it in `TenderOpened`, and `mechanismCodehashOf` MUST return it.

**Views.** All view functions MUST revert for a `tenderId` that does not exist. `awardOf` MUST return an empty array unless the phase is `Awarded`, and once the phase is `Awarded` MUST return the same result on every call.

### Integration profiles

Every tender declares, in `integrationProfile`, what its award means to the standard that consumes it. Bidders see it before committing, so it fixes the meaning of a bid.

| Profile | Identifier | The consumer | Allowed rules |
| --- | --- | --- | --- |
| price-binding | `bytes4(keccak256("profile.price-binding"))` | is (a) payment-binding and (b) execution-binding, as defined below | any |
| allocation-only | `bytes4(keccak256("profile.allocation-only"))` | uses the winners only; the payment is fixed by the consumer, or execution is at its discretion | `award.posted-price` only |

An integration is:

- **payment-binding** if it pays each winner exactly its `Award.price` for the work awarded;
- **execution-binding** if, before the commit deadline, it holds an authorization such that, for every admissible non-empty award, the transition that executes that award at `Award.price` can be triggered by anyone, and neither the requester nor any third party can withhold, pre-empt, block or cause that transition to revert. Escrowing the reserve is one way to meet the funding part of this condition; it does not meet the condition by itself.

`openTender` MUST revert if `integrationProfile` is neither identifier, and MUST revert if it is allocation-only and the mechanism's `mechanismId` is not `award.posted-price`. An integration that cannot guarantee both (a) and (b) MUST declare allocation-only. Any incentive property this ERC states for a pricing rule, including truthful bidding under `award.vickrey`, holds only under the price-binding profile.

### Task content

`contentHash` is the hash of the task content as it stands when the tender opens; the target or adapter MUST publish a deterministic encoding and hash algorithm before opening. The committed descriptor MUST include the work description, the payment denomination defined above, and the acceptance policy, including any verifier address and configuration that determine which work is payable. The discovered award price itself is not part of this descriptor. An award applies only to that content. A consumer MUST NOT treat an award as making anyone eligible for, or as setting the price of, a task whose content no longer matches `contentHash`; a changed task needs a new tender. A price-binding integration MUST prevent the task content from changing between opening and execution, since a requester that can change the work after the reveals can renegotiate with the winner's revealed cost in hand. An integration that relies on content binding MUST reject a tender whose `contentHash` is zero. A mint-after-award integration MUST initialise the created task with the committed content and verify that binding in the same settlement transaction, before treating the award as executed. Retaining update authority alone is insufficient if the initial content was not bound. The commitment does not establish the correctness or immutability of an external verifier; an integration claiming price-binding MUST also ensure that its acceptance policy cannot be changed to defeat the precommitted outcome.

### Authority boundary

A valid award confers no authority over its target. The companion's output is a replay-safe, target-bound `Award`; whether and how that award changes the target is decided by the target standard's own authority model. Code that carries an award into a target (an adapter) MUST NOT act with authority the target standard does not already grant it. An adapter MAY set a provider, fund a task, or initialise its reward only when it is the target's authorised client or holds an explicit pre-authorisation under the target's existing rules. An award alone MUST NOT grant any such permission. An adapter without that authority MAY only verify that a transition made by an authorised party is consistent with the stored award.

## Rationale

**The mechanism contract is stateless.** The revelation principle motivates representing an allocation and payment rule as functions on reported types, under its incentive and equilibrium assumptions. A pure `award` function is that pair, and nothing else. Because it reads no state, a mechanism can be verified against the feasibility conditions by exhaustive test vectors, and its bytecode can be pinned by anyone opening a tender.

**Pricing rules are explicit.** Two mechanisms can have the same allocation but different realized payments and strategic incentives. Revenue equivalence concerns expected payments under additional assumptions, including equilibrium behavior and equal boundary utility. The interface therefore identifies the chosen rule before bidding; plugins are not presumed to be economically equivalent.

**Second-price is the recommended default.** For single-unit procurement with private costs and quasi-linear utilities, without collusion or externalities, the allocation and second-price payment rule make truthful reporting weakly dominant. The rule needs no prior over competitors' costs. This claim assumes the integration preserves both the payment and the execution commitment; it does not assert optimality for asymmetric, correlated-cost or unrestricted multi-identity environments.

**Reserve is a field of its own.** A requester may prefer its outside option to every submitted bid, so no award must be a valid result. The reserve is the committed maximum acceptable price. Choosing an economically optimal reserve depends on the environment and is outside this specification.

**Uniform-price is limited to one unit per bidder, and a bidder is an address.** With several units and bidders who want more than one, uniform-price invites demand reduction and is not truthful. Deployments that need multi-unit demand should use a Vickrey-Clarke-Groves rule as a plugin. The tender cannot tell operators apart, only addresses, so the one-unit limit holds only if each operator bids from one address. An operator with two addresses can win one unit and use the other address to set the clearing price, which is demand reduction by another route; it can also decide which to do after seeing earlier reveals. `award.uniform-price` is therefore truthful only where an admission layer binds each operator to one address. Single-unit `award.vickrey` does not have this weakness: a second identity only adds another bid, which can lower the lowest other bid but never raise it, so it can never raise the price paid. This point was raised by zexoverz in the discussion thread; the general problem is known as false-name bidding.[^2]

**Asymmetric and correlated-type mechanisms are out of scope.** Rules that discriminate between bidders need per-bidder beliefs about cost distributions. Full-surplus extraction under correlated types needs the requester to pay losing bidders, which the escrow standards forbid. Scoring rules that satisfy the award conditions can be plugins. Payments to losing bidders are outside this award interface; full-surplus extraction is not expressible by the normative rules.

**Commit–reveal over encrypted bids.** It needs no off-chain committee and no new cryptography. The cost it adds, one extra transaction and a bond, is the least that makes a sealed report credible on a public ledger.

**Ties break by commit order.** Any deterministic tie-break is compatible with the theory. Commit order is observable on-chain, needs no randomness, and rewards early commitment, which shortens commit windows in practice.

**Bonds return on reveal, not on award.** A bidder who reveals has done what the procedure asked. Holding the bond until award would penalise honest losers and give the requester a lever to delay.

**The award holds no authority.** An award is a fact about bids, not a permission on the target. A mechanism computes an outcome; a separately authorised client or adapter executes it under the target's existing authority model. In an allocation-only integration the authorised party may decline to act. A price-binding integration instead precommits that authority before bidding closes. This distinction allows one companion to serve targets with different authority models.

**One canonical target reference.** Task-escrow protocols use different identifier domains. Committing to `(chainId, targetContract, targetId)` under one hash makes an award bind to exactly one target, so a tender cannot be replayed against a different job that happens to share an identifier, and indexers can join awards to targets without per-standard rules.

**Truthfulness depends on the integration.** Incentive compatibility is a property of the allocation rule and the payment rule together. In procurement form it requires each bidder's expected payment to satisfy X(c) = c·Q(c) + ∫ Q(s) ds + K over costs above c, where Q is its probability of winning. If the consumer pays a fixed reward R instead of the award price, then X(c) = R·Q(c), and together these give (R − c)·Q′(c) = 0: below R the probability of winning cannot depend on the bid. In this private-cost model, a truthful fixed-payment rule cannot rank accepted bids by their reported costs; a posted-price rule satisfies that restriction. A bid ranking combined with a fixed reward fails in practice as well as in theory. Every bidder whose cost is below R bids as low as it can, so the award goes to whoever committed first. With reward 100 and true cost 60, a bidder facing a bid of 50 loses by bidding 60 and wins 40 by bidding 40. Hence `award.posted-price`, and the requirement that allocation-only tenders use it. This counterexample is due to SergeevDmitry, and the split into price-binding and allocation-only integrations to chugarchugarr, both in the discussion thread.

**Price-binding needs execution-binding.** Paying the award price is not enough. If the consumer can decline after seeing the revealed bids, it is choosing the reserve after the fact, and that choice can depend on the winner's own bid. For example, a requester who executes only when the price exceeds the winning bid by at most 10 rewards a bidder with cost 40, facing a bid of 60, for bidding 50 instead of 40. Myerson's results assume the mechanism designer is bound by the mechanism; without that, revealed costs also leak into whatever the requester does next. Execution-binding is that commitment. It is stated over reachable states, not transactions: what matters is that no state is reachable in which an award is final and its execution can be withheld or made impossible. Performing finalize and execution in one transaction is the simplest way to meet it, but `finalize` stays permissionless because other consumers read the same award. The terms payment-binding and execution-binding, and the point that escrow is one way to meet the second rather than its definition, are due to chugarchugarr in the discussion thread.

**Content is fixed at opening, not at award.** Bidders price the task they see when they commit, so a change to the task at any point after the first commitment, before or after the award, means the bids no longer price the same work. Fixing the content at award time would still let a requester change the task between the reveals and the award, with the bids in view. The case of a task changed after the award was raised by Ted in the token-bound task working draft discussion thread.

**Awards are final.** A consumer that reads an award must be able to rely on it not changing afterwards. A dispute layer, with proposed and challenged states and a challenge window, was suggested in the discussion thread by predge-ai. It is not needed here, because the award is a pure function of on-chain data: whether each commitment was opened is known at `finalize`, which can run only after the reveal deadline, and the bond enforces nothing else. Nothing that could disqualify a winner arrives later. The specification therefore makes `Awarded` and `Void` terminal. A winner who fails to deliver is handled by the target's own acceptance rules, and a requester who wants to re-award opens a new tender for the same `targetRef`.

**Slashed value is a tender term.** Where slashed bonds go changes bidders' incentives, so it belongs in the terms every bidder sees before committing, not in an adapter or a deployment setting.

### Composition with escrow standards (informative)

This ERC does not specify adapters. The following patterns are consistent with the authority boundary:

- With [ERC-8183](./eip-8183.md), if the client calls `setProvider(jobId, winner)` and `setBudget(jobId, price)` itself, with a hook that reverts unless the values equal `awardOf(tenderId)`, the client can still decline to act. That integration is allocation-only. It becomes price-binding only through an adapter that escrows the reserve and can make both calls once the tender is awarded, whoever triggers it, and that the client cannot race, for example because the adapter is itself the job's client.
- With the task-market working draft, an Auction-mode implementation that reads `awardOf` inside its own selection transition, pays the award price and lets anyone trigger that transition is price-binding. One that keeps the requester's discretion is allocation-only.
- With the token-bound task working draft, a token minted with a fixed `rewardPerCompletion` is allocation-only: the award can only admit the winner through the eligibility policy, and its tender MUST use `award.posted-price` with `reserve` equal to `rewardPerCompletion`. Because the token's update authority may change the task after minting, the eligibility gate must also stop admitting the winner once the task content no longer matches `contentHash`. For price discovery the award must come first and fix the reward. A price-binding pattern is an adapter that escrows the reserve, reserves the token identifier it will mint, opens the tender against that identifier, and exposes one permissionless settle transition that finalizes the tender if needed, mints the token with `rewardPerCompletion = Award.price` and refunds the rest. The mint initialises the task with the committed content, and settlement checks the resulting content hash. The adapter keeps the token's update authority itself, or mints with none that can change the task, so the content stays fixed until the work is settled. The reservation matters as much as the escrow. the token-bound task working draft leaves minting to the implementation; if anyone else can mint the chosen identifier first, the settle transition reverts and the award cannot be executed. If the requester mints later at its own discretion, execution-binding fails.

## Backwards Compatibility

This ERC introduces new interfaces and does not change any existing one. Existing task-escrow contracts are unaffected unless they choose to consume an award.

## Test Cases

Test vectors are provided in [award vectors](../assets/erc-draft_sealed_bid_award/vectors/award-vectors.json). Each vector supplies a list of bids in commit order, a reserve, a unit count, and the expected award for each normative mechanism. The set covers: all bids under the reserve; a single bid, which pays the reserve under `award.vickrey` and `award.uniform-price`; no bid under the reserve; a second-lowest bid above the reserve, which caps the Vickrey price at the reserve; ties, which go to the earlier commit; an empty bid list; and multi-unit cases where the clearing price is the first excluded bid or, when there is none, the reserve.

The following must hold for every vector and for any further input an implementation is tested on, since they restate conditions 1 to 7 of the specification: the same input gives the same output; every winner is a bidder whose bid is within the reserve; no price exceeds the reserve; no winner appears twice and there are no more awards than units; lowering a winner's bid keeps it a winner; equal bids resolve to the earlier commit; and no winner is paid less than its bid. For `award.vickrey`, in addition, a bidder's payoff from bidding its true cost is never less than its payoff from any other bid, holding other bids fixed. For `award.posted-price`, accepting exactly when cost is at most the reserve is never worse than any other bid, at any commit position. The vectors also cover the posted-price rule: the earliest acceptances win at the reserve, and a lower bid does not overtake an earlier acceptance.

## Reference Implementation

A reference `SealedBidTender` contract and the four normative mechanism contracts are provided as [tender](../assets/erc-draft_sealed_bid_award/SealedBidTender.sol), [first-price](../assets/erc-draft_sealed_bid_award/mechanisms/FirstPriceAward.sol), [Vickrey](../assets/erc-draft_sealed_bid_award/mechanisms/VickreyAward.sol), [uniform-price](../assets/erc-draft_sealed_bid_award/mechanisms/UniformPriceAward.sol) and [posted-price](../assets/erc-draft_sealed_bid_award/mechanisms/PostedPriceAward.sol) contracts. The tender contract holds bonds only, validates the integration profile, passes revealed bids to the mechanism in commit order, re-checks each award against the specification before storing it, and credits slashed bonds for the tender's `slashRecipient`. The mechanism contracts are pure; a stable sort over bids in commit order is what makes the tie rule hold.

## Security Considerations

**Unrevealed commitments.** Without a bond, a bidder can commit and abandon at no cost, or commit from many addresses to probe the mechanism. `bond` must be non-zero for tenders open to unrestricted participation, and implementations should size it against the reserve.

**Public reveals.** Bids become public at reveal. In a second-price rule the second-lowest reveal sets the price, so two colluding bidders can arrange their reveal order to expose the winner's margin. The award is unchanged, but implementations should not attach any meaning to reveal order.

**Collusion and correlated costs.** Agents built on the same model API have strongly correlated costs, and a bidding ring can hold the second price at the reserve. Requesters should derive the reserve from their own outside option rather than from observed past prices. Reputation layers should index `TenderAwarded` events to detect rings.

**Shill bidding by the requester.** A requester can commit a bid at the reserve to push a second price toward it. Because the reserve is the requester's own declared limit, this does no harm under first-price or second-price. Uniform-price is more exposed, and implementations may exclude the requester's address from bidding.

**Commit order, not reveal order.** Bids must reach the mechanism in commit order. An implementation that passes them in the order they were revealed lets whoever controls transaction ordering in the reveal window decide ties, and under `award.posted-price` decide the winner outright.

**Discretionary execution.** A consumer that declares price-binding but can decline an award after the reveals breaks the incentive properties the profile promises, and the bidders cannot detect it from the tender alone. Bidders should verify that a price-binding tender's requester is a contract that executes awards without discretion, such as an escrowing adapter, before relying on truthful bidding.

**Pre-empting execution.** An execution-binding adapter depends on every step of its settle transition succeeding. If the target lets anyone create the object the adapter will create, such as an the token-bound task working draft token with a chosen identifier, an attacker can create it first and make settlement revert permanently, locking the escrow. Adapters should reserve every such identifier when the tender opens, and bidders should check that reservation before relying on the price-binding profile.

**A faulty or replaced mechanism.** The mechanism is third-party code. The tender checks every award against the revealed bids, so a faulty mechanism cannot name a bidder who never revealed, award a bid above the reserve, or pay a winner less than it asked, but it can still choose the wrong winner among valid bids or the wrong price within those bounds. Bidders therefore rely on the mechanism's code. Pinning the code hash at opening stops the code at that address from being replaced before `finalize`, but a code hash does not reveal a proxy, whose behaviour changes with its implementation behind an unchanged hash. Bidders should check that the code at the pinned hash computes the result itself, for example by comparing it with a known reference deployment, rather than relying on `mechanismId`, which any contract can return. The need to state and enforce these checks was raised by Revinand in the discussion thread.

**False-name bids.** Under `award.uniform-price`, one operator bidding from several addresses can win fewer units than it could serve in order to raise the clearing price, as explained in the Rationale. Deployments that use `award.uniform-price` with `units > 1` should admit bidders through a layer that binds operators to addresses, or accept that the rule is not truthful for operators with several addresses.

**Bidder cap.** `finalize` sorts the revealed bids and visits every commitment, so its cost grows faster than linearly in the number of bidders: in the reference implementation it is about 2M gas at 128 revealed bids, 8M at 256, 31M at 512 and 122M at 1,024. A bond does not prevent flooding, since a bidder who reveals recovers it, so without a cap anyone could make a tender impossible to finalize for the cost of gas. Hence the `maxBidders` term and the implementation limit. The reference implementation's limit is 256.

**Timestamp manipulation.** Deadlines are block timestamps and can shift by a few seconds. Commit and reveal windows shorter than a few minutes should not be used.

**Mechanism trust.** A malicious mechanism can award arbitrarily. Because `award` is pure, its behaviour can be checked offline and its bytecode pinned. Requesters should reference only audited mechanism addresses.

**Bond asset handling.** Fee-on-transfer and rebasing assets make slashed amounts ambiguous. Implementations should reject them as `bondAsset`.

**Re-tendering.** If a tender is void and the requester opens another for the same `targetRef`, the revealed bids of the first round inform the second. Implementations may enforce a minimum interval or refuse to reuse a `targetRef`.

**Slash recipient as an incentive.** If slashed bonds reach the requester, directly or indirectly, two things go wrong. The requester gains from bidders failing to reveal and may try to induce that, for instance by congesting the reveal window. And the requester can post commitments it never intends to reveal at almost no cost. Under a first-price rule such phantom commitments inflate the number of apparent competitors and lower bids; in the uniform-cost case with three real bidders, three phantom commitments reduce the requester's expected payment by about 19%. Sending slashed bonds to the target's vault looks neutral but is not: under the token-bound task working draft, funds sent to the vault are spent on the reward before the requester's own funds, and any residual returns to the token owner. Hence the requirement that `slashRecipient` be an address the requester cannot recover funds from. Implementations should also reject a `slashRecipient` that is a bidder of the same tender if one can be identified at commit time.

**Commit–reveal is not sealed.** Reveals are public transactions, so a bidder who reveals late has seen earlier reveals, and anyone watching a public mempool sees pending ones. A bidder can also hold several commitments and open only the one that does best against what it has seen. Under `award.vickrey` this is worthless: truthful bidding is dominant for every profile of other bids, so information about them has no value, and each abandoned commitment forfeits a bond. Under `award.first-price` it is valuable: a last revealer with a fine ladder of commitments is paid close to the lowest rival bid while rivals shade as in a sealed first-price auction. In the uniform-cost case the gain reaches about 27% of the reserve, and deterring even a two-commitment ladder needs a bond of 10 to 12% of the reserve when there are three or fewer bidders. Deployments that use `award.first-price` should make reveals simultaneous, for example through threshold encryption, rather than rely on the bond.

**Adapters that act.** An adapter authorised to mutate a target is a privileged actor and must be audited as such. Its authority comes from the target's client or pre-authorisation rules, never from the award or mechanism. Its permissions, funding, identifier reservation, content initialisation and acceptance policy all need to satisfy the declared integration profile.

[^1]:
    ```csl-json
    {
      "type": "article-journal",
      "id": 1,
      "author": [
        {
          "family": "Myerson",
          "given": "Roger B."
        }
      ],
      "DOI": "10.1287/moor.6.1.58",
      "title": "Optimal Auction Design",
      "container-title": "Mathematics of Operations Research",
      "volume": "6",
      "issue": "1",
      "page": "58-73",
      "original-date": {
        "date-parts": [
          [1981, 2, 1]
        ]
      },
      "URL": "https://doi.org/10.1287/moor.6.1.58"
    }
    ```

[^2]:
    ```csl-json
    {
      "type": "article-journal",
      "id": 2,
      "author": [
        {
          "family": "Yokoo",
          "given": "Makoto"
        },
        {
          "family": "Sakurai",
          "given": "Yuko"
        },
        {
          "family": "Matsubara",
          "given": "Shigeo"
        }
      ],
      "DOI": "10.1016/S0899-8256(03)00045-9",
      "title": "The effect of false-name bids in combinatorial auctions: new fraud in internet auctions",
      "container-title": "Games and Economic Behavior",
      "volume": "46",
      "issue": "1",
      "page": "174-188",
      "original-date": {
        "date-parts": [
          [2004, 1, 1]
        ]
      },
      "URL": "https://doi.org/10.1016/S0899-8256(03)00045-9"
    }
    ```

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
