---
eip: <to be assigned>
title: Stateful Fungible Token
description: An ERC-20 extension that records and updates per-holder provenance lineage on every transfer.
author: cc358 (@cc358) <fishierita881@gmail.com>
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2026-05-23
requires: 20
---

## Abstract

This standard extends [ERC-20](./eip-20.md) with per-holder provenance tracking. Each address holding a conforming token carries an on-chain lineage record — a weighted set of ancestor addresses representing the historical sources of its current balance. On every transfer between externally-owned accounts (or any non-exempted addresses), the recipient's lineage is updated as a weighted blend of its prior lineage and the sender's lineage, with the weight of each side determined by the recipient's existing balance and the transferred amount. Tokens remain fully fungible and divisible at the unit level — `balanceOf`, `transfer`, `approve`, and all other ERC-20 semantics are preserved — but each holder's position acquires an unforgeable historical context that can be queried and reasoned about by other contracts.

## Motivation

ERC-20 and [ERC-721](./eip-721.md) sit at opposite ends of a spectrum. ERC-20 tokens are fully fungible: every unit is interchangeable and carries no history. ERC-721 tokens are fully non-fungible: every unit carries identity and history but cannot be divided or merged. The space between these two extremes has remained largely unexplored. Prior attempts such as ERC-1155 (multi-token contracts) and ERC-3525 (semi-fungible tokens) address efficiency or class-grouping concerns but do not introduce per-holder history into fungible balances.

This gap matters because many useful on-chain primitives require both **liquidity** (the ability to freely transfer and trade) and **identity** (the ability to reason about provenance). Reputation systems, sybil-resistant airdrops, on-chain social graphs, and lineage-based access control all need to answer questions of the form "where did this balance come from?" — a question ERC-20 cannot answer at all, and ERC-721 can only answer at the cost of liquidity.

This standard introduces **Stateful Fungible Tokens** (SFTs in the sense of "state-bearing fungible," not to be confused with prior uses of the acronym): tokens that preserve full ERC-20 compatibility while attaching a per-holder, transfer-derived lineage record to every address. The lineage record is automatically maintained by the contract on every transfer, requires no off-chain coordination, and is queryable through a small extension to the ERC-20 interface.

### Primary use case: on-chain social identity

The motivating use case is **on-chain social identity**. In existing token ecosystems, a wallet's identity is reduced to its balance — a number that says nothing about the wallet's history of interactions, the breadth of its on-chain relationships, or the trust network it participates in. A Stateful Fungible Token surfaces this information natively. Two wallets holding the same balance of the same token can be meaningfully distinguished by their lineage: one may carry the inherited weight of dozens of historical counterparties, while the other may carry only a single ancestor. This makes the **shape** of a wallet's holdings — not merely the size — a first-class on-chain property that other applications can build upon.

### Extended use cases

Beyond social identity, the lineage structure enables several adjacent applications:

- **Sybil resistance**: A wallet's lineage depth and the diversity of its ancestor set are difficult to forge cheaply. Any attempt to inflate lineage depth requires real on-chain interactions with distinct counterparties, each carrying a transferable cost. Lineage statistics can therefore serve as a sybil signal in airdrops, governance weighting, and access control without requiring centralized identity providers.

- **Provenance and inheritance**: Each holder can verify and display the historical sources of their balance. This enables collection-style mechanics where users derive meaning or rights from the specific ancestors present in their lineage (e.g., gating membership on the presence of a known founding address in one's lineage).

- **Composable reputation**: Because lineage is recorded on-chain and queryable by other contracts, it can be composed with existing reputation primitives. A lending protocol could weight collateral by the lineage diversity of the collateral token, or a voting system could discount votes from addresses with shallow lineage.

### Why not non-fungible identity?

One might ask why per-holder lineage is preferable to per-token identity (as in ERC-721 or ERC-3525). The answer is liquidity. Per-token identity destroys fungibility, fragments liquidity across distinct token IDs, and makes the token unusable as a unit of exchange. By attaching lineage to the **holder** rather than the **unit**, this standard preserves full ERC-20 fungibility — pools, swaps, and accounting all work unchanged — while still allowing applications to query the identity-bearing dimension when needed.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

### Interface

A conforming contract MUST implement the ERC-20 interface and the following extension:

```solidity
interface IStatefulFungibleToken /* is IERC20 */ {
    /// @notice A single ancestor entry in a holder's lineage.
    /// @param ancestor The ancestor address.
    /// @param weight   The ancestor's share of the holder's lineage, in basis points (0 to 10000).
    struct LineageSegment {
        address ancestor;
        uint256 weight;
    }

    /// @notice Returns the full lineage of `holder`.
    /// @dev The returned array MUST satisfy: (a) all weights sum to exactly 10000
    ///      when `holder` has a non-zero balance, or (b) the array is empty when
    ///      `holder` has a zero balance. Ordering is implementation-defined but
    ///      MUST be stable across calls when no state-changing operation has
    ///      occurred between them.
    function lineageOf(address holder) external view returns (LineageSegment[] memory);

    /// @notice Returns the number of distinct ancestor entries in `holder`'s lineage.
    /// @dev MUST equal the length of `lineageOf(holder)`.
    function lineageDepth(address holder) external view returns (uint256);

    /// @notice Returns the weight of `ancestor` in `holder`'s lineage, in basis points.
    /// @dev Returns 0 if `ancestor` is not present in `holder`'s lineage.
    function ancestorWeight(address holder, address ancestor) external view returns (uint256);

    /// @notice The maximum number of distinct ancestor entries a holder's lineage may contain.
    /// @dev Implementations MUST enforce this cap. When merging two lineages would exceed
    ///      this cap, segments with the lowest weight MUST be evicted first.
    function maxLineageDepth() external view returns (uint256);

    /// @notice The share, in basis points, attributed to the sender side of a transfer
    ///         when blending lineages. The recipient's prior lineage receives the
    ///         complementary share (10000 - blendRatio).
    /// @dev See the "Transfer Behavior" section for the precise blending formula.
    function blendRatio() external view returns (uint256);

    /// @notice The minimum weight, in basis points, a lineage segment must retain
    ///         after blending to be preserved. Segments falling below this threshold
    ///         MUST be discarded, with their weight redistributed to surviving segments
    ///         in proportion to those segments' relative weights.
    function dustThreshold() external view returns (uint256);

    /// @notice Emitted when a holder's lineage is updated as a result of a transfer.
    /// @param holder    The address whose lineage was updated.
    /// @param ancestors The full list of ancestor addresses after the update.
    /// @param weights   The corresponding weights, in basis points. weights[i] is the
    ///                  weight of ancestors[i]. The arrays MUST have equal length.
    event LineageUpdated(
        address indexed holder,
        address[] ancestors,
        uint256[] weights
    );
}
```

### Transfer behavior

Let `r` denote the recipient and `s` denote the sender of a transfer of amount `a`. Let `B_r` denote `r`'s balance immediately before the transfer (i.e., not including `a`). Let `L_r` denote `r`'s lineage immediately before the transfer, expressed as a mapping from ancestor address to weight in basis points. Let `L_s` denote `s`'s lineage at the same moment. Let `K` denote `blendRatio()` and `M` denote `maxLineageDepth()` and `D` denote `dustThreshold()`, all in basis points.

On a transfer that triggers lineage update (see "Exemptions" below), the implementation MUST update `L_r` according to the following procedure:

**Step 1 — Determine the source lineage attributed to the incoming amount.** The portion of the incoming amount that contributes "fresh" sender lineage is parameterized by `K`. Define the *contribution lineage* `L_in` as `L_s` scaled by `K / 10000` and `L_r` scaled by `(10000 - K) / 10000`, weighted by the relative magnitudes of `a` and `B_r`. The combined weight assigned to the sender side is:

```
w_sender = (K * a) / (K * a + (10000 - K) * B_r)     -- in basis points after normalization
w_self   = 10000 - w_sender
```

When `B_r == 0`, `w_sender = 10000` and `w_self = 0`, so the recipient inherits the sender's lineage in full (modulo a special-case below).

**Step 2 — Blend the lineages.** For each ancestor `x`, compute the new weight as:

```
L_r'[x] = w_self * L_r[x] / 10000 + w_sender * L_s[x] / 10000
```

This produces an intermediate lineage `L_r'` whose total weight equals `10000` (modulo rounding error, which the implementation MUST correct by adjusting the largest segment).

**Step 3 — Apply the dust threshold.** Any segment in `L_r'` whose weight is strictly less than `D` MUST be discarded. The total weight discarded MUST be redistributed pro-rata across the remaining segments in proportion to their relative weights. After redistribution, the sum of remaining weights MUST equal `10000`.

**Step 4 — Apply the depth cap.** If the resulting lineage contains more than `M` segments, the implementation MUST evict segments with the lowest weight first until `M` segments remain. The total weight evicted MUST be redistributed pro-rata across the surviving segments, as in Step 3.

**Step 5 — Emit `LineageUpdated`.** The event MUST reflect the final `L_r'` after all eviction and redistribution.

### Special cases

- **First-time recipient (`B_r == 0`, `L_r` empty):** The recipient's new lineage MUST be set to `L_s` directly (no blending necessary, since there is no prior lineage to blend with).

- **First-time mint (no prior sender lineage):** When a transfer originates from an address with no lineage record (e.g., a minter address or an exempted address — see below), the recipient's lineage MUST be initialized such that the recipient themselves is the sole ancestor with weight `10000`. This treats the act of acquiring the token from a non-tracked source as a "genesis" event for that holder.

- **Self-transfer (`s == r`):** Lineage MUST NOT be updated.

- **Zero-amount transfer:** Lineage MUST NOT be updated.

### Exemptions

The lineage update procedure MUST NOT be applied when either the sender or recipient is an *exempted address*. Exempted addresses include, at minimum:

- The zero address (mint and burn operations).
- The contract's own address (token sweeps).
- Any address designated by the implementation as a "router" or "liquidity-managing" contract (e.g., Uniswap V4 PoolManager, ERC-4626 vaults, lending markets).

Exemptions are necessary because AMM swaps, vault deposits, and similar operations route tokens through intermediary contracts that are not the economic counterparty to the trade. Updating lineage on such transfers would attribute counterparty status to the contract itself rather than the real buyer or seller, polluting the lineage record with bookkeeping addresses.

The set of exempted addresses MAY be configured at deployment time. Implementations MAY also expose a public view function `isExempt(address) returns (bool)` for off-chain consumers; this function is RECOMMENDED but not required.

### Invariants

Conforming implementations MUST maintain the following invariants at all times:

1. **Conservation of weight.** For every address `h` with `balanceOf(h) > 0`, the sum of weights in `lineageOf(h)` MUST equal exactly `10000`.
2. **Empty on zero balance.** For every address `h` with `balanceOf(h) == 0`, `lineageOf(h)` MUST be empty.
3. **Depth cap respected.** For every address `h`, `lineageDepth(h) <= maxLineageDepth()`.
4. **No dust persisted.** For every segment `(x, w)` returned by `lineageOf(h)`, `w >= dustThreshold()`.

## Rationale

### Why store lineage on the holder rather than the token unit

Attaching lineage to each transferable unit would require non-fungible accounting, which destroys liquidity and breaks compatibility with existing ERC-20 infrastructure (DEXs, lending markets, wallets). Per-holder lineage is a strict generalization: any application that wants per-unit semantics can synthesize them by querying the holder's lineage and applying its own attribution model, while applications that don't care about lineage can ignore it entirely and treat the token as a plain ERC-20.

### Why a weighted blend rather than a transfer log

The naive alternative — storing the full transfer history of every wallet — has unbounded storage cost and rapidly becomes prohibitive on-chain. A weighted blend collapses the history into a fixed-size representation parameterized by `maxLineageDepth()`, trading lossless history for bounded gas cost. The blend ratio `K` and the depth cap `M` are tunable parameters that let implementers balance fidelity against cost.

### Why the depth cap and dust threshold are MUST-enforce rather than MAY

Without a depth cap, an attacker could inflate any victim's lineage by sending a stream of dust transactions from many distinct addresses, eventually causing every transfer to exceed the block gas limit. Without a dust threshold, the same attacker could keep the depth small but pollute the victim's lineage with arbitrarily many near-zero segments. Both protections are necessary, and both must be uniform across implementations so that consumers can rely on the bounded-size guarantee.

### Why blending uses `K`-weighted sender share rather than amount-proportional

Pure amount-proportional blending (i.e., `w_sender = a / (a + B_r)`) gives the sender no influence when transferring a small amount to a large holder. This eliminates one of the standard's most useful properties: that frequent small interactions accumulate into observable lineage. The `K`-weighted variant ensures the sender always contributes a meaningful share when `a > 0`, while still scaling with the relative magnitudes of the transfer and the recipient's existing balance.

### Why exemptions are necessary

Transfers through AMM routers, vault wrappers, and similar intermediary contracts do not represent economic interaction between the on-chain parties involved. If lineage were updated naively on every transfer, every wallet that ever swapped on Uniswap would have the Uniswap PoolManager as a dominant ancestor, drowning out genuine peer-to-peer history. The exemption mechanism preserves the standard's economic meaning at the cost of requiring implementers to designate intermediary contracts explicitly.

### Why parameters are queryable rather than fixed

Different applications have different fidelity needs. A high-throughput memecoin may want a low `maxLineageDepth()` to minimize gas; a reputation token may want a high one to maximize signal. Rather than fix the values in the standard, this proposal exposes them as view functions so that consumers can adapt their behavior to the specific token they're reading.

### Recommended parameter values

While this standard intentionally leaves parameter values to the implementer, the reference implementation uses the following values, which the authors recommend as a balanced starting point for L2 deployments:

- `blendRatio() = 3000` (30%) — gives the sender meaningful influence on every transfer while preserving the recipient's dominant share.
- `maxLineageDepth() = 64` — large enough to capture substantial peer-to-peer history, small enough to keep worst-case transfer gas under ~500k on L2s.
- `dustThreshold() = 10` (0.1%) — high enough to make 1-wei sybil attacks economically impractical, low enough to preserve genuine small-share ancestors.

Implementations targeting L1 mainnet, low-throughput tokens, or high-fidelity reputation use cases SHOULD reconsider these values for their specific gas and signal requirements.

## Backwards Compatibility

This standard is fully backwards compatible with ERC-20. Conforming contracts inherit the entire ERC-20 interface unchanged — `balanceOf`, `transfer`, `transferFrom`, `approve`, `allowance`, `totalSupply`, `name`, `symbol`, `decimals`, the `Transfer` event, and the `Approval` event all behave exactly as specified in ERC-20. Existing ERC-20 consumers (wallets, DEXs, indexers) can interact with Stateful Fungible Tokens without modification and without awareness of the lineage extension.

The extension adds only view functions and a new event (`LineageUpdated`). It does not change the signature, return value, or observable side effects of any ERC-20 function. Implementations that emit `LineageUpdated` in addition to `Transfer` introduce no incompatibility, as ERC-20 does not constrain what additional events a contract may emit.

The lineage update procedure is implemented in the contract's internal transfer hook (e.g., OpenZeppelin's `_update`) and is invisible to callers other than through the `LineageUpdated` event and the view functions.

## Reference Implementation

A reference implementation is available at:

`https://github.com/cc358/dna-standard`

The reference implementation uses OpenZeppelin's ERC-20 base contract and integrates with Uniswap V4 hooks via the `IPoolManager.unlock` callback for fee collection. The lineage update logic is encapsulated in a separate library (`DNAMath`) with property-based tests verifying conservation of weight, depth-cap enforcement, dust eviction, and resistance to 1-wei sybil attacks.

Key implementation notes:

- Lineage updates are performed in the ERC-20 internal `_update` hook, after the balance change is committed.
- Exemption checks are performed inline; the set of exempted addresses includes the zero address, the contract address itself, and the Uniswap V4 PoolManager.
- The depth-cap eviction uses a partial sort: only the lowest-weight segments are identified, not a full sort of all segments.
- Weight redistribution after dust eviction uses proportional rounding with the largest-segment correction to ensure exact conservation.

## Security Considerations

### Dust-flood lineage pollution

An attacker can attempt to fill a victim's lineage with attacker-controlled addresses by sending many 1-wei transfers from distinct addresses. The dust threshold and depth cap together bound this attack: at most `maxLineageDepth()` distinct ancestors can ever appear in any lineage, and any ancestor whose share falls below `dustThreshold()` is automatically evicted. The cost to the attacker — gas plus the value of the transferred amount — scales linearly with the number of distinct ancestors they attempt to insert.

Implementations SHOULD set `dustThreshold()` high enough that ancestor insertion has a meaningful cost. A threshold of 10 basis points (0.1%) is a reasonable starting point: an attacker who wants to occupy one lineage slot must contribute at least 0.1% of the victim's eventual balance.

### Lineage slot exhaustion

Even with dust protection, an attacker with enough capital can fill all `maxLineageDepth()` slots of a victim's lineage by transferring meaningful amounts from distinct addresses. This is not preventable at the protocol level, since it reflects genuine on-chain interaction. Consumers that want to weight lineage by intrinsic vs. attacker-controlled ancestors should apply their own attribution models off-chain or at the application layer.

### Gas cost of deep lineage

A transfer between two holders with full lineages requires merging up to `2 * maxLineageDepth()` segments, applying the dust threshold, and re-truncating to the depth cap. With `maxLineageDepth() = 64`, this is approximately 400k gas in the reference implementation on Base. Implementations targeting L1 mainnet should consider lower depth caps or alternative storage layouts.

### Front-running of lineage-gated mechanisms

If an application gates rewards or access on a lineage property (e.g., "wallets with lineage depth ≥ 20"), an attacker can observe pending transactions and front-run to manipulate their own or others' lineage. Application designers SHOULD treat lineage queries as eventually-consistent and not assume that a query and a subsequent action will see the same lineage state.

### Privacy

Lineage records are public on-chain and reveal the historical counterparties of every holder. This is a strictly stronger privacy disclosure than ERC-20, which reveals only balances. Users who require counterparty privacy should not hold Stateful Fungible Tokens directly, or should route their holdings through privacy-preserving intermediary contracts (subject to the exemption mechanism above).

### Exemption list governance

The set of exempted addresses materially affects the meaning of every lineage record produced by the contract. If the exemption list is mutable post-deployment, the contract owner can retroactively alter the interpretation of historical lineage by adding or removing exemptions. Implementations SHOULD make the exemption list immutable after deployment, or expose any mutation through a clearly-bounded governance process.

### Integer overflow in weight arithmetic

All weight arithmetic operates in basis points (0 to 10000) and intermediate products fit in a `uint256` without overflow for any plausible balance. Implementations MUST use checked arithmetic or formal verification to confirm this for their specific blending formula, particularly when `K` is configurable.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
