---
eip: 99993
title: Stock Locates
description: Ask a lending venue whether, how much and at what rate a token can be borrowed now, and against what
author: Borro (@BorroMarkets)
discussions-to: https://ethereum-magicians.org/t/draft-erc-stock-locates/30128
status: Draft
type: Standards Track
category: ERC
created: 2026-10-28
requires: 20, 165
---

## Abstract

This proposal defines a read interface for any contract that lends [ERC-20](./eip-20.md) tokens, tokenized stocks
above all, so a would-be borrower can "locate" a token before a short sale: whether `amount` can be borrowed now, the
most that can be borrowed, the borrow rate before and right after the borrow, the collateral a new borrower posts and
the limit it is held to, and the contract and market the borrow goes through. Three view functions, discoverable
through [ERC-165](./eip-165.md), answer the same questions at every conforming venue, so a borrower, a wallet or an
agent compares venues with one call each.

## Motivation

In securities lending, a short seller must locate the shares before selling them: a lender confirms the shares can be
borrowed and quotes a fee. Tokenized stocks now trade and lend on chain, and lending venues for them differ in every
detail a short seller needs: how much is free to borrow, how the rate is quoted (per second, per year, simple or
compounded), how the rate moves as the borrow draws down supply, what collateral is taken and at what limit, and which
contract to call. Each venue answers these in its own shape, or across several contracts, so comparing them takes
venue-specific code for every venue.

The same is true for automated borrowers. An agent that wants to short a stock, or to borrow a token for any reason,
should be able to ask every venue the same question and rank the answers. The rate that matters is the one after the
borrow: venues whose rates follow utilization charge more as a borrow draws down supply, so a venue with a low rate
and little supply can cost more at size than one with a higher rate and deep supply.

This proposal standardizes that question and its answer. It does not standardize how to borrow, which differs by venue
(a plain borrow, a borrow that sells in the same transaction, a borrow against a position held in an account); the
answer names the contract and the venue's own market id, and the borrow is made through the venue's own interface.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT
RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

interface IStockLocate {
    struct Locate {
        bool borrowable;
        uint256 available;
        uint256 rateNow;
        uint256 rateAfter;
        address collateralToken;
        uint256 collateralNeeded;
        uint256 maxLtv;
        address venue;
        bytes32 market;
    }

    function locatableTokens() external view returns (address[] memory tokens);

    function maxLocate(address token) external view returns (uint256 available);

    function locate(address token, uint256 amount) external view returns (Locate memory);
}
```

A conforming contract MUST implement [ERC-165](./eip-165.md) and MUST return `true` from `supportsInterface` for the
interface id `0x68b6211d`.

A conforming contract MAY be the lending venue itself or a separate contract that reads the venue.

### Units

- `available`, `amount` and `collateralNeeded` are in the smallest units of the token they count.
- `rateNow` and `rateAfter` are borrow rates per second, simple (not compounded), scaled by 10^18: a rate `r` means a
  debt grows by `r / 10^18` of itself each second at that rate. A yearly simple rate is `r * 31536000`.
- `maxLtv` is a ratio scaled by 10^18: 10^18 is 100%.

### `locatableTokens`

MUST return every token for which `maxLocate` can return a value above zero. It MAY return tokens that cannot be
borrowed at the moment (a paused market, no free supply). It MUST NOT revert.

### `maxLocate`

MUST return the most of `token` that can be borrowed through `venue` at the current block: the same value as the
`available` field of `locate(token, amount)` for every `amount`. It MUST return 0 for a token the contract does not lend,
and for a token it lends but would refuse to lend now (for example, a paused market). It MUST NOT revert.

### `locate`

MUST NOT revert, for any `token` and `amount`. For a token the contract does not lend, every field MUST be zero (the
zero address for addresses, `false` for `borrowable`).

Otherwise, at the current block:

- `borrowable` MUST be `true` exactly when a borrow of `amount` through `venue` from `market` goes through with no
  change other than a borrower with no position at the venue posting `collateralNeeded` of `collateralToken`. It MUST be
  `false` when `amount` is zero or greater than `available`.
- `available` MUST equal `maxLocate(token)`.
- `rateNow` MUST be the rate the venue charges on this market's borrows from the current block on, with no new borrow.
  If the venue updates its rate or accrues interest when it is next called, `rateNow` MUST be the rate as it stands
  after that update.
- `rateAfter` MUST be the rate the venue charges on this market's borrows right after a borrow of `amount`, or of
  `available` if `amount` is greater, made in the current block. For a venue whose rate does not depend on the amount
  borrowed, `rateAfter` equals `rateNow`. When `available` is zero, `rateAfter` equals `rateNow`.
- `collateralToken` MUST be the token the borrower hands to `venue` as collateral for this borrow. Where the venue holds
  collateral in another form (for example, shares of a vault it deposits the token into), `collateralToken` is the
  token the borrower hands over, and `collateralNeeded` counts that token.
- `collateralNeeded` MUST be the least amount of `collateralToken` that, posted by a borrower with no position at the
  venue, lets a borrow of `amount` pass the venue's own collateral check at the current block, with the position at
  the venue's limit. It MUST be zero when `amount` is zero. It MUST be computed for `amount` even when `borrowable` is
  `false` because `amount` is greater than `available`. If the venue cannot value the collateral (for example, its price
  source reports no price), it MUST be `type(uint256).max`.
- `maxLtv` MUST be the ratio of the debt's value to the collateral's value past which the venue may close or liquidate
  the position.
- `venue` MUST be the contract a borrow is made through, and `market` the venue's own identifier for the market `token`
  is borrowed from, or zero if the venue has one market per token. How to call `venue` is outside this proposal.

When a venue lends `token` from more than one market, `locate` SHOULD answer for the market with the lowest `rateAfter`
for `amount` among those with `available` of at least `amount`, and otherwise for the market with the most `available`.

## Rationale

**The shape of a flash loan lender.** [ERC-3156](./eip-3156.md) asks a flash lender two questions,
`maxFlashLoan(token)` and `flashFee(token, amount)`, and leaves the loan itself to a separate call. This proposal asks
the same two questions of an ordinary lender, `maxLocate(token)` and `locate(token, amount)`, and adds what a borrow
that stays open needs: the rate and how it moves, and the collateral.

**One struct, one call.** A borrower comparing venues wants every number from the same block in one call. A struct
keeps the answer in one return value and lets the interface stay three functions.

**Per second, simple, 10^18.** Most variable-rate lenders on Ethereum keep rates per second, and a per-second simple
rate converts without ambiguity to any yearly figure a reader wants: `r * 31536000` for a simple yearly rate,
`exp(r * 31536000) - 1` for a compounded one. Yearly figures, by contrast, come compounded and simple and are easy to
misread.

**The rate after the borrow.** Venues whose rates follow utilization charge more as a borrow draws down supply. The
rate before the borrow alone ranks venues wrongly for any borrow that is large next to the supply. The rate after the
borrow is the marginal cost, and with `available`, a borrower can split a borrow across venues.

**The rate as it stands after the next update.** Some rate models move with time as well as with use, and update when
the market is next touched. A rate read from stored state can then be the average over the time since the last update
rather than the rate from now on. The specification asks for the rate from now on, which is what a new borrow pays.

**Collateral at the limit, with the limit.** The least collateral that passes the venue's check is exact and comparable
across venues. Posting exactly that leaves no room for the price to move, so the answer also carries `maxLtv` and leaves
the margin to the borrower, who knows how long it means to hold the position.

**Where to borrow, not how.** Borrowing interfaces differ more than the questions before a borrow do: some venues lend
to the caller, some through an account per borrower, some sell the token in the same transaction to open a short. An
earlier proposal for one shared borrow and supply interface did not advance. Standardizing the question before the borrow, and
pointing to the venue and its market, gives aggregators and agents a common read without asking venues to change how
they lend.

**A locate is not a hold.** In securities lending a locate can set shares aside for the borrower for a time. On chain,
any borrower can take free supply in the next block, and setting supply aside would need an escrow and a fee for it.
This proposal reports what is borrowable at the current block and reserves nothing; a venue that offers holds can do so
through its own interface.

**Any lent token.** The interface works for any ERC-20 a venue lends. Tokenized stocks are the case that motivates it,
because short sellers need a locate before they sell.

**Related work.** [ERC-4626](./eip-4626.md) standardizes the lender's side of a vault, not the borrower's question.
[ERC-7726](./eip-7726.md) standardizes price quotes, which a reader can use to value `collateralNeeded` and
`available` in a common unit. Proposals for the operating status of tokenized assets (whether the reference market is
open or halted) answer a question a short seller asks alongside this one. Proposals for credit lines to agent
identities cover unsecured lending to an identity, where this proposal covers secured borrowing of a token by anyone.

## Backwards Compatibility

This proposal adds view functions and changes nothing in existing lending venues. A venue that cannot add functions can
be covered by a separate contract that reads it, as the reference implementation does.

## Test Cases

The reference implementation's tests run against twelve live tokenized stock markets at a fixed block and check each
field against the venue itself:

- `available` equals the market's supply less its borrows once the market accrues interest in the same block, and is
  zero for a market the venue has paused.
- `rateNow` equals the rate the venue's rate model reports once the market accrues in the same block.
- In each of the twelve markets, a new borrower posts exactly `collateralNeeded` through the venue and borrows half of
  `available`: the borrow goes through, the tokens arrive, and the rate the venue reports right after equals
  `rateAfter`.
- Posting a thousandth less than `collateralNeeded` fails the venue's collateral check.
- Borrowing `available` goes through and leaves the market fully borrowed, at the rate `rateAfter` named; borrowing one
  unit more fails the venue's liquidity check, with any amount of collateral.
- A token the contract does not lend answers zero from `maxLocate` and an all-zero `Locate`, without reverting.

## Reference Implementation

A deployment of `BorroStockLocator` is live on Robinhood Chain (chain id 4663) at `0xd86522162EBFc75bc3f959174be878FeD09dFc1f`, with its source verified (exact match) on Sourcify and Blockscout. It is a read-only adapter: no owner, no storage of its own, nothing to upgrade.

`BorroStockLocator` answers locates for Borro's stock lending markets. Each market lends one tokenized stock against
shares of a USDG lending vault, on Morpho Blue with its adaptive curve rate model; a borrow goes through Borro's short
contract (`venue`), which takes USDG, deposits it into the vault and borrows on an account of the borrower's own.

- `available` is the market's supply less its borrows after the interest Morpho Blue accrues at the start of any
  borrow, and zero while the short contract has the market paused or unlisted.
- `rateNow` and `rateAfter` come from the adaptive curve model's own arithmetic: the rate at target the model moves to
  when the market next accrues (from the utilization since the last update and the time elapsed), on the curve at the
  utilization before and after the borrow.
- `collateralNeeded` is the USDG that mints the vault shares whose value, at the market's oracle price and liquidation
  limit, covers the debt Morpho Blue counts for `amount` (borrow shares rounded up).

The contract has no owner, holds nothing and changes no state. Its full source is verified at that address, under
GPL-2.0-or-later because its rate library follows Morpho's IRM, so it stays there rather than in this proposal's
assets. The function that answers a locate, from that source, released here under CC0:

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

function _locate(address token, uint256 amount) internal view returns (Locate memory q) {
    bytes32 id = marketOf[token];
    if (id == bytes32(0)) return q;
    MarketParams memory p = morpho.idToMarketParams(Id.wrap(id));
    (MarketParams memory listed,,, bool paused,) = short.deskOf(id);
    bool open = listed.loanToken == token && !paused;

    (uint256 supplied,, uint256 borrowed, uint256 borrowShares) = morpho.expectedMarketBalances(p);
    uint256 free = supplied > borrowed ? supplied - borrowed : 0;
    q.available = open ? free : 0;

    Market memory m = morpho.market(Id.wrap(id));
    int256 rat = AdaptiveCurveRate.rateAtTargetAfter(
        IAdaptiveCurveIrm(irm).rateAtTarget(Id.wrap(id)),
        AdaptiveCurveRate.utilizationOf(m.totalSupplyAssets, m.totalBorrowAssets),
        block.timestamp - m.lastUpdate
    );
    uint256 draw = amount < q.available ? amount : q.available;
    q.rateNow = AdaptiveCurveRate.curve(rat, AdaptiveCurveRate.utilizationOf(supplied, borrowed));
    q.rateAfter = AdaptiveCurveRate.curve(rat, AdaptiveCurveRate.utilizationOf(supplied, borrowed + draw));

    q.borrowable = open && amount != 0 && amount <= free;
    q.collateralToken = usdg;
    q.collateralNeeded = amount == 0 ? 0 : _usdgToBorrow(p, amount, borrowed, borrowShares);
    q.maxLtv = p.lltv;
    q.venue = address(short);
    q.market = id;
}
```

## Security Considerations

**A locate is a reading, not a promise.** Every field holds for the current block. Another borrower, a repayment, a
withdrawal by a lender or a price update can change all of them in the next block. A borrower MUST bound the borrow
itself (by the venue's own minimums and maximums, or by checking the position after it) and MUST NOT rely on a locate
read in an earlier transaction.

**Not an oracle.** Free supply and utilization can be moved within one transaction, for example with a flash loan, so
`available`, `rateNow` and `rateAfter` can be pushed for the length of a transaction. Contracts MUST NOT move value
based on a locate read in the same transaction as state another party controls.

**Collateral at the limit.** A position opened with exactly `collateralNeeded` is at the venue's limit and can be
liquidated on the smallest price move. Borrowers SHOULD post more and size the margin from `maxLtv` and how long they
mean to hold.

**Prices of tokenized stocks.** `collateralNeeded` uses the venue's price source. While the reference market of a
tokenized stock is closed, price sources hold the last price, and the price at the reopen can differ widely. Borrowers
SHOULD check the token's market status before relying on `collateralNeeded` near a close.

**Rates can jump.** A rate that follows utilization can move far after the borrow, as others borrow or lenders
withdraw. `rateAfter` is the rate at the moment after the borrow, not a fixed rate for the life of the debt.

**Reading many venues.** Aggregators calling `locate` on many contracts SHOULD bound the gas of each call, since a
conforming contract cannot make every answer cheap, and SHOULD check `supportsInterface` before trusting the shape of a
return value.

**Trust in the reader.** A contract that reads a venue, rather than the venue itself, can misreport it. Readers SHOULD
use a reading contract published by the venue, or verify its source against the venue's contracts.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
