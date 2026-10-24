---
eip: 99908
title: Credit-Matched Liquidity
description: Loans that fund the quote side of an escrowed liquidity position, paid first from its fees and valued by a price feed
author: Priors contributors (@priors-agents)
discussions-to: https://ethereum-magicians.org/t/erc-tba-credit-matched-liquidity/30039
status: Draft
type: Standards Track
category: ERC
created: 2026-10-20
requires: 20, 165, 721
---

## Abstract

This proposal defines an interface for a contract that lends an [ERC-20](./eip-20.md) quote token into a
concentrated-liquidity position that a holder pairs with base tokens it owns. The position, an [ERC-721](./eip-721.md)
token of a position manager, stays in the contract's escrow: the holder cannot withdraw it. Fees in the quote token pay
the lender first. The holder closes the position by repaying what it owes and gets the position token back. While
anything is owed, anyone may unwind the position once its value, taken from the price feed the contract names for the
pool and never from the pool's own price, no longer covers the loan by the margin fixed at opening, or once it is due.
A price set while the base token was not trading is never used. The unwind settles at the feed's price without a swap,
pays the lender's base tokens to a fallback address the lender names, and leaves the holder's part in the position
token, so a token whose transfer registry blocks an address cannot strand a position. When, past the due date, no price
has come for a delay the lender lists, at least 14 days, or once a day has passed since the base token stopped trading
for good, anyone may instead hand the position over to the lender without a price.

## Motivation

Holders of tokenized stocks and other assets with a reliable price could earn pool fees on them if someone supplied the
other side of the pool. Lenders with stablecoins could fund that side and be repaid from the fees, holding as security
both the holder's tokens and the loan itself, inside one position. Lending against pool positions and leveraged
liquidity already exist as products, each with its own contracts and events. A wallet that wants to show a holder its
positions, a lender that wants to offer this to many holders, or a reader that rebuilds a borrower's credit history has
to integrate each one separately.

Three failures recur in this kind of lending, and each is cheaper to rule out in the interface than in every
implementation. Lenders that valued pool positions from the pool's own price have been drained by trades that moved that
price for one transaction. Tokenized stocks carry transfer registries that can block an address, and a position held by
an escrow the registry blocks, with no other way out, is lost to both sides. And stock prices stop while their market is
closed and jump when it reopens, so a price that is a few hours old can be a price nobody can trade at. This proposal
fixes the calls and events, and one rule for each of the three.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT
RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- **Holder**: the account that opens a position with its base tokens.
- **Lender**: the party whose quote tokens the contract lends.
- **Base token** and **quote token**: each supported pool pairs a base token with `quoteToken()`.
- **Position manager** and **position token**: an ERC-721 contract that represents each position in a
  concentrated-liquidity pool, liquidity between a lower and an upper tick as in Uniswap v3 and v4, by a token; and that
  token. Amounts withdrawn from a position, and its fees, stay owed to the position token until they are collected.
- **Price feed**: a contract with the two functions below, whose `answer` is the price of one whole base token in whole
  quote tokens, multiplied by `10 ** decimals()`.

```solidity
interface IPriceFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
```

- **Status source**: for a base token whose reference market trades in sessions or can stop trading, such as a
  tokenized stock, a contract with the function below, which reports the base token's trading status in that market
  and since when it holds. A base token traded continuously has no status source.

```solidity
interface ITradingStatus {
    enum TradingStatus { Unknown, Trading, SessionBreak, Halted, Terminal }
    function tradingStatus() external view returns (TradingStatus status, uint64 since);
}
```

- **Trading status**: `Trading` while the market is in session and the asset trades, `since` the session opened or
  trading last resumed; `SessionBreak` while the market is closed between sessions on its schedule, at night, over a
  weekend or a holiday, or in an intraday break, `since` the break began; `Halted` while trading in the asset, or in
  its whole market, is stopped outside the schedule with no time set to resume, as in a halt or a suspension, `since`
  it stopped and through any scheduled break until trading resumes; `Terminal` once the asset will not trade in that
  market again, as after a delisting, a redemption or the end of the token's program; and `Unknown`, which is zero so
  that an unset value never reads as `Trading`, when the source cannot tell. `since` is when the status began, not
  when the source last confirmed it.
- **Usable price**: the answer of a position's feed (before opening, of the feed `oracleOf(pool)` names) when all of
  these hold:
  1. `answer` is above zero;
  2. `updatedAt` is not zero, not later than the block timestamp, and not older than `maxPriceAge`;
  3. if the base token has a status source, the source reports `Trading`, and `updatedAt` is at or after the `since`
     it reports;
  4. the price it gives, once the decimals of the feed and of both tokens are applied, is above zero and not above the
     largest price the contract accepts.
- **Value** of a position at a usable price `P`: the base and quote its liquidity holds when the price is `P`, plus the
  base and quote already owed to its position token, with the base valued at `P`. Fees that the position manager has
  not yet credited to the position token MAY be left out.

### Interface

A conforming contract MUST implement `ICreditMatchedLiquidity` and MUST implement [ERC-165](./eip-165.md), returning
`true` for the interface identifier of `ICreditMatchedLiquidity` and for `0x01ffc9a7`.

```solidity
interface ICreditMatchedLiquidity {
    enum Status { None, Open, Closed, Unwound, HandedOver }

    struct Position {
        address holder;
        uint256 agentId;
        address pool;
        address positionManager;
        uint256 tokenId;
        address priceFeed;
        address statusSource;
        uint32 maxPriceAge;
        uint16 unwindBps;
        uint16 gapBps;
        uint64 openedAt;
        uint64 dueAt;
        uint32 handoverDelay;
        uint256 baseIn;
        uint256 quoteLent;
        uint256 owed;
        Status status;
    }

    event PositionOpened(uint256 indexed positionId, address indexed holder, uint256 indexed agentId, address pool, uint256 baseIn, uint256 quoteLent);
    event FeesApplied(uint256 indexed positionId, uint256 toLender, uint256 toHolder);
    event PositionClosed(uint256 indexed positionId, uint256 repaid);
    event PositionUnwound(uint256 indexed positionId, uint256 recovered, uint256 shortfall);
    event PositionHandedOver(uint256 indexed positionId, uint256 recovered, uint256 outstanding);

    function quoteToken() external view returns (address);
    function identityRegistry() external view returns (address);
    function lenderFallback() external view returns (address);
    function oracleOf(address pool) external view returns (address priceFeed);
    function quoteLimit(address pool, uint256 baseIn) external view returns (uint256);
    function open(address pool, uint256 baseIn, uint256 quoteToBorrow, int24 tickLower, int24 tickUpper, uint256 agentId) external returns (uint256 positionId);
    function position(uint256 positionId) external view returns (Position memory);
    function health(uint256 positionId) external view returns (uint256 valueInQuote, uint256 owed, bool unwindable);
    function applyFees(uint256 positionId) external returns (uint256 toLender, uint256 toHolder);
    function close(uint256 positionId) external;
    function unwind(uint256 positionId) external;
}
```

### Tokens, pools and prices

- `quoteToken()` MUST return the ERC-20 token lent and repaid, and MUST NOT change. `quoteLent`, `owed`, `toLender`,
  `toHolder`, `repaid`, `recovered`, `shortfall`, `outstanding` and `valueInQuote` are in its base units; `baseIn` is
  in the base token's.
- `identityRegistry()` MUST return the ERC-721 contract the `agentId` values refer to, such as the Identity Registry of
  [ERC-8004](./eip-8004.md), or the zero address, and MUST NOT change.
- `oracleOf(pool)` MUST return the price feed the contract uses for positions opened from now on in `pool`, and the
  zero address for a pool it does not support.
- The contract MUST NOT use the pool's own price (its current tick, square-root price or reserves) to compute
  `quoteLimit`, `health`, or what an unwind pays to whom. The pool's price decides only the proportions in which a mint
  takes the two tokens and an unwind withdraws them.
- The contract MUST read `decimals()` from the feed, and the decimals of both tokens, rather than assume them.
- For a base token with a status source, the contract MUST read the trading status from it, and MUST treat a source
  that reverts, returns no answer, or answers with a value outside `TradingStatus`, as reporting `Unknown`.
- The contract MUST define the largest price it accepts, and MUST NOT support a pool whose feed, when the pool is added,
  gives a price above it or not above zero. It MUST compute every price conversion, valuation, threshold comparison and
  settlement amount in full precision (a multiplication kept in 512 bits before its division, or equivalent), so that
  none can overflow for a usable price and the amounts the contract documents as supported. `health` and `unwind` MUST
  NOT fail with an arithmetic error for any answer of the feed.
- Every amount of the quote token the contract records or reports (`quoteLent`, each reduction of `owed`, `toLender`,
  `toHolder`, `repaid` and `recovered`) MUST be the amount that actually moved, measured as the change in the balance
  of the account that received it, or for `quoteLent` of the lender, and not the amount requested. The base the lender
  receives at an unwind MUST likewise be valued as it arrived at `lenderFallback()`. A quote token that charges a fee on
  transfer therefore cannot be repaid through `close`, and lenders SHOULD NOT lend such a token.

### Opening

- `quoteLimit(pool, baseIn)` MUST return the most quote the contract would lend against `baseIn` now. It MUST be
  computed from the value of `baseIn` at a usable price of `oracleOf(pool)`, MUST NOT exceed the quote the lender can
  lend now, and MUST return `0`, not revert, for a pool the contract does not support or when the price is not usable.
- `open(pool, baseIn, quoteToBorrow, tickLower, tickUpper, agentId)`:
  - MUST revert if `baseIn` or `quoteToBorrow` is zero, or if `quoteToBorrow` is greater than
    `quoteLimit(pool, baseIn)`.
  - MUST revert if `agentId` is not zero and `msg.sender` is not `ownerOf(agentId)` in `identityRegistry()`.
  - MUST take `baseIn` from `msg.sender`, add liquidity between `tickLower` and `tickUpper` with at most `baseIn` base
    and `quoteToBorrow` quote, hold the position token, and return to `msg.sender` the base the position did not take.
    Quote the position did not take stays with the lender.
  - MUST record the position with `holder` set to `msg.sender`; `baseIn` and `quoteLent` set to the amounts the position
    took; `owed` set to `quoteLent` plus the lender's charge, if any; `priceFeed` set to `oracleOf(pool)`;
    `statusSource` set to the base token's status source, or the zero address for a base token traded continuously;
    the lender's `maxPriceAge`, `unwindBps` and `gapBps`; `openedAt` set to the block timestamp; `dueAt` set to the due
    time, or `0` for none; `handoverDelay` set to the hand-over delay the lender lists; and `status` set to `Open`. It
    MUST give the position a `positionId` that is not zero and is never reused, emit `PositionOpened`, and return the
    id.
  - MUST revert if the new position would be unwindable (as `health` defines it) at its usable price lowered by
    `gapBps / 10000`.
- `unwindBps` MUST be greater than `10000` and `gapBps` less than `10000`.
- For a base token traded in sessions, the lender SHOULD set `gapBps` to at least the largest move it expects between
  one session's last price and the next session's first, across a weekend or a holiday and through news, and SHOULD
  choose `unwindBps` and the ratio behind `quoteLimit` so that a position at its unwind line is still worth more than
  it owes after that move.
- A position's `handoverDelay` MUST be at least 14 days (1,209,600 seconds): `open` MUST NOT record a shorter one,
  whatever delay the lender lists.

### Escrow and terms

- While a position is `Open`, the contract MUST hold its position token and MUST NOT withdraw liquidity from it,
  collect from it or transfer it, except as `applyFees`, `close` and `unwind` define.
- A position's `priceFeed`, `statusSource`, `maxPriceAge`, `unwindBps`, `gapBps`, `dueAt` and `handoverDelay` MUST NOT
  change. Its `owed` MUST NOT increase after it is opened.
- `position(positionId)` MUST return the position as recorded, with its current `owed` and `status`, and a
  zero-valued record with status `None` for an id never issued.

### Health

- For an `Open` position, `health(positionId)` MUST revert when the position's price is not usable. Otherwise it MUST
  return the position's value at that price as `valueInQuote`, its `owed`, and `unwindable` set to `true` exactly when
  `owed` is not zero and either `dueAt` is not zero and the block timestamp is at or after it, or
  `valueInQuote * 10000 < owed * unwindBps`. A position with nothing owed is never unwindable, at its due date or after
  it.
- For a position that is not `Open`, `health` MUST return zeros and `false`.

### Fees

- `applyFees(positionId)` MUST be callable by any account and MUST revert unless the position is `Open`. It MUST collect
  the position's fees in the quote token, pay the lender the lesser of those fees and `owed`, reduce `owed` by that
  amount, pay the rest to the holder, emit `FeesApplied`, and return both amounts.
- Fees in the base token MUST stay with the position: `applyFees` MUST NOT pay them to anyone. They go to the holder with
  the position token at `close`, and are settled with the rest of the position at `unwind`.
- `applyFees` MUST NOT read a price.

### Closing

- `close(positionId)` MUST revert unless `msg.sender` is the position's holder and the position is `Open`. It MUST take
  `owed` from the holder in the quote token with `transferFrom`, and MUST revert if less than `owed` arrives. It MUST
  then set `owed` to zero and the status to `Closed`, transfer the position token to the holder, and emit
  `PositionClosed` with the amount that arrived.
- `close` MUST NOT read a price and MUST NOT transfer the base token.

### Unwinding

- `unwind(positionId)` MUST be callable by any account. It MUST revert unless the position is `Open` and its `owed` is
  not zero: a position with nothing owed is never unwound or handed over, and only its holder's `close` ends it. When
  the position's price is usable, `unwind` MUST revert unless `health` reports the position unwindable, and then
  unwinds it as below. When the price is not usable, it MUST revert unless a hand-over is due, and then hands the
  position over (see Hand-over); so it reverts when the price is not usable, including after `dueAt`, until a
  hand-over is due.
- To unwind, it MUST remove all of the position's liquidity, then settle everything owed to the position token, fees
  included, at the price `P` that `health` used:
  1. the lender receives the quote, up to `owed`;
  2. if that does not cover `owed`, the lender receives the base worth the rest at `P`, rounded up, up to all of the
     base. The position manager MUST pay this base straight to `lenderFallback()`;
  3. the rest is the holder's: the contract MUST leave it owed to the position token and transfer the position token to
     the holder.
- `unwind` MUST NOT transfer the base token to or from the contract itself, and MUST NOT revert because the base token
  refuses a transfer. If the base cannot be paid to `lenderFallback()`, `unwind` MUST transfer the position token, with
  the base still owed to it, to `lenderFallback()` instead of the holder.
- It MUST set `owed` to zero and the status to `Unwound`, and emit `PositionUnwound` with `recovered` set to the quote
  the lender received plus the base it received valued at `P`, at most `owed`, and `shortfall` set to `owed` minus
  `recovered`.
- `lenderFallback()` MUST NOT return the zero address. The lender sets it, by means outside this interface, to an address
  it expects the base token's transfer registry to accept.

### Hand-over

- `TERMINAL_GRACE` is 86,400 seconds (one day): the time a holder has to close once its base token stops trading for
  good, counted from the `since` its status source reports with `Terminal`.
- A hand-over is due for an `Open` position whose `owed` is not zero and whose price is not usable when:
  1. its status source reports `Terminal` and the block timestamp is at or after `since + TERMINAL_GRACE`, whatever
     `dueAt`; or
  2. `dueAt` is not zero, the block timestamp is at or after `dueAt + handoverDelay`, and no price has come for the
     hand-over delay: the status source reports `Halted` with a `since` more than `handoverDelay` before the block
     timestamp; or the feed is silent while the status source reports `Trading`, `Unknown` or `Terminal`, or while the
     base token has no status source.
- Before `since + TERMINAL_GRACE`, a `Terminal` status makes no hand-over due by itself: `unwind` reverts, as for any
  price that is not usable, unless condition 2 already makes a hand-over due, and `close` works as always, since it
  needs no price. A `since` later than the block timestamp has begun no window: the status gives no price, and
  condition 1 holds only from `since + TERMINAL_GRACE`.
- The feed is **silent** when its answer would not be a usable price even with `handoverDelay` in place of
  `maxPriceAge` and without condition 3 of a usable price, that is, when it has given no answer the contract could
  price within the last `handoverDelay`. A feed that answered within that time is late, not silent: the contract waits
  for it.
- An `Unknown` status, including one read from a source that reverts, returns no answer or answers outside
  `TradingStatus`, makes a hand-over due only together with a silent feed, whatever `since` it reports: a source that
  fails, for one call or for longer, never stands in for a price missing for the whole delay.
- A `SessionBreak` never makes a hand-over due, however long it lasts: the contract waits for the reopening price.
- To hand a position over, `unwind` MUST remove all of the position's liquidity, collect the quote owed to the position
  token, up to `owed`, for the lender, and transfer the position token, with everything still owed to it, to
  `lenderFallback()`. No amount it moves or reports may depend on a price, and it MUST NOT transfer the base token. It
  MUST set `owed` to zero and the status to `HandedOver`, and emit `PositionHandedOver`, not `PositionUnwound`, with
  `recovered` set to the quote the lender received, at most `owed`, and `outstanding` set to `owed` minus `recovered`.

## Rationale

- **A feed's price, never the pool's.** A pool's price is the cheapest number in the system to move: one large trade,
  funded by a flash loan and reversed in the same transaction, moves it as far as the attacker likes. A lender that
  values positions from it can be made to lend against a value that is not there, or to unwind a position that is
  healthy. A price feed aggregates trades the attacker does not control.
- **Pairs with a reliable price only.** A pool position cannot be valued without a price from outside the pool. For a
  pair without a feed any valuation falls back on the pool's own price, which this proposal excludes, so a pool is
  supported only when the contract names a feed for it.
- **The loan is inside the position.** [ERC-7565](./eip-7565.md) states loan terms against an NFT that is already locked
  and leaves its valuation aside; [ERC-4626](./eip-4626.md) accounts for deposits and shares in a vault;
  [ERC-7246](./eip-7246.md) pledges a token balance without moving it. Here the loan funds the position itself, the
  position changes composition with every trade, and its health is defined from a feed's price.
- **Prices from a closed market do not count.** A feed for a stock keeps the last session's answer through a weekend,
  and may refresh `updatedAt` without a new price, so the age of an answer cannot show that it still holds. Opening at
  Friday's price lends against a value Monday may not confirm; unwinding at it gives the lender base at a price nobody
  can trade at. The contract therefore asks a status source, and uses only an answer set after the current session
  opened or trading resumed. A halt gives no price either. Requiring the answer to postdate the session's opening also
  covers the minutes after a reopening, before the feed has caught up with the gap.
- **A trading status, not a session flag.** A flag that only says whether the market is open treats a halt as a
  weekend. A weekend is bounded and `gapBps` can be sized for it; a halt is not, and halts, delistings and redemptions
  are when the reopening price gaps the most, if it comes at all. The status therefore tells apart a session break,
  after which a price comes back, a halt, which may last, and a terminal state, after which no price will come. None
  of them gives a price; they differ past the due date: a break is waited out, a halt is waited out for the hand-over
  delay, and a terminal state is handed over after a day's grace, due or not, since waiting cannot bring a price.
  `since` dates a price against the session it belongs to, times a halt and starts a terminal state's grace. `Unknown`
  is zero so that a source that was never set reads as unknown, not as trading, and a source that cannot answer reads
  the same, so that it lets no price through. An unknown status says nothing about how long the price has been
  missing, so it counts toward a hand-over only with a feed silent for the whole delay: a source that fails for a
  moment cannot cost the holder its part.
- **A small status interface of its own.** Asset-status interfaces drafted for tokenized assets report more than the
  escrow needs: the program's lifecycle, the session and any interruption separately, the state of the valuation
  source. `ITradingStatus` reduces them to the one answer the escrow acts on, and an adapter can derive it from such an
  interface, a feed's market-status report or an issuer's pause flag. Its function is named `tradingStatus()` so that
  its selector differs from that of an `assetStatus()` view drafted for tokenized assets, whose answer has another
  layout and would otherwise decode as a wrong status.
- **Closing and fees need no price.** `owed` is in the quote token and `close` hands back the position token, so neither
  depends on a price that may no longer hold, and a holder can repay over a weekend. Only opening and unwinding wait
  for the market.
- **A gap allowance at opening.** Session prices move in jumps: the first price of a session can be far from the last of
  the one before, with no price in between at which to unwind. A position opened with no room for that jump can go from
  healthy to under water at once. `gapBps` makes the room explicit and is recorded in the position, so a reader sees it.
- **Fees, lender first.** Quote fees pay the lender before the holder sees any. Base fees stay in the position: applying
  them to a debt in the quote token would need a price, and paying a stock token to a lender may not be allowed by its
  registry.
- **Closing returns the position token.** The holder gets the position back as it is, liquidity and base fees included.
  No base token moves, so a registry that blocks the escrow or the holder cannot stop a repayment, and the holder can
  keep providing liquidity if it wants.
- **Unwinding settles at the feed's price, without a swap.** Swapping the base in the pool during an unwind is the trade
  a manipulator wants to be on the other side of. The lender takes base at `P` instead, and carries the risk of selling
  it. Withdrawing at a pool price other than `P` never lowers the value at `P` of what is withdrawn: a position trades
  along the pool's curve, so its holdings valued at `P` are lowest when the pool's price is `P`. Moving the pool before
  an unwind therefore costs the mover and takes nothing from the lender or the holder.
- **The lender's fallback address.** The lender's book holds the quote token. The base it receives, and the position
  token when the base cannot leave the pool, go to an address the lender keeps acceptable to the base token's registry.
  The holder's part never needs a transfer of the base: it waits in the position token until the holder's address is
  allowed to collect it.
- **A hand-over when no price comes.** Without one, a feed that dies after the due date leaves the holder a free option:
  close if the asset recovers, walk away if it does not, while the lender waits on a feed that may never return. Only
  the base leg of an unwind needs a price; the quote leg does not. So once a hand-over is due, `unwind` collects the
  quote up to `owed` and gives the lender the position token for the rest. Without a price the base cannot be split
  between the lender and the holder, so the token goes to the lender whole; the holder had the term and the delay to
  close, and closing needs no price. The pool's price decides only how much of what goes to the lender arrives as
  quote, so moving it before a hand-over gains nobody anything.
- **A silent feed, not a late one.** A hand-over gives the lender more than an unwind at a price would, the holder's
  part of the position, so a lender gains from triggering one, and the rule must not hand over on a price that is
  only late. A session that has just opened has no price yet, and a feed can fall behind `maxPriceAge` for a while.
  The hand-over therefore waits until the feed has given no answer the contract could price for the whole delay, or a
  halt has lasted it, which a live feed, or a halt that ends with trading resuming, does not reach; an unknown status
  waits for the silent feed too. A session break never counts, however long a source reports it: breaks are scheduled
  and end with a price.
- **The hand-over delay is the lender's, with a floor.** The delay is a term like `gapBps`: the lender lists it and the
  position records it, so a holder knows at opening how long past the due date it can still close, and lenders can
  compete on it; one delay fixed in this proposal would not fit every base token and every lender. It MUST still be at
  least 14 days, for three reasons. It is how long a feed must be silent to count as dead, and some stock exchanges
  close on schedule for up to about ten days, around the lunar new year, so a shorter delay would let a feed that does
  not answer while its market is closed look dead at the reopening, minutes before the session's first price. It is
  how long a halt must last before the position is handed over, and a trading suspension by the United States
  securities regulator lasts up to ten business days, about 14 calendar days, while most halts end within the day.
  And it is the holder's last time to close after the due date, which two weeks give across a holiday. The floor is a
  requirement, not a recommendation, so that a holder can trust the delay of any conforming contract without checking
  it pool by pool: no conforming lender can list a few hours and take positions over an ordinary outage. The lender
  waits at most the delay past the later of the due date and the moment the price stopped coming, and a lender that
  wants to wait less can lend for a shorter term.
- **A day's grace after a terminal status.** A base token that will never trade again will never give a price, so a
  terminal status does not wait for the due date. A hand-over still takes the holder's part, and closing needs no
  price, so the hand-over waits `TERMINAL_GRACE`, one day, from the `since` the status source reports: a holder that is
  watching can repay and keep its part, and a wrong `Terminal` leaves holders a day to react. The lender, which can do
  nothing with a price that will not come, waits only that day. The window is fixed in this proposal rather than
  listed by the lender, since it only protects the holder and its length depends on how long a holder needs to repay
  in the quote token, not on the base token's market. It runs from `since` because a view keeps no record of when its
  answer changed: the contract cannot tell when a status was first reported, only when the source says it began. A
  hand-over due for another reason, a feed silent for the hand-over delay past the due date, does not wait for the
  window: the holder has already had the term and the delay to close.
- **Nothing owed, nothing to unwind.** Fees can repay a position in full before it is due. A due date ends the lender's
  exposure, and with nothing owed there is none, so such a position is never unwindable and never handed over; its
  holder closes it, paying nothing, and gets the position token back as `Closed`. Otherwise anyone could pull the
  holder's liquidity at the due date, and a reader of an identity's credit history would see an unwind for a loan
  repaid in full.
- **A due date, a charge fixed at opening, terms that do not move.** A due date stops a position from holding the
  lender's quote for ever. Folding the charge into `owed` at opening lets the holder know the most it will owe. Fixing
  the feed, the status source, the price age, the unwind line and the hand-over delay per position stops a lender from
  unwinding, or taking over, a position that was healthy under the terms it was opened on.
- **The identity is the holder's.** `agentId` lets readers count a position's opening, closing and unwinding as credit
  events of an identity, such as an ERC-8004 agent. Checking ownership at opening stops anyone from attributing a
  position, and its shortfall, to an identity that is not theirs.
- **`pool` is an address.** Uniswap v3 pools have one. A pool of a singleton pool manager has an identifier instead; an
  implementation for such pools names each supported pool by an address it documents. A later revision may take the
  identifier.

## Backwards Compatibility

No backward compatibility issues found. The interface fits position managers that keep withdrawn amounts owed to the
position token until they are collected, as v3-style managers do. A manager that settles every amount within the call
that withdraws it, as v4-style managers do, needs a wrapper that keeps those amounts for the token, so that the holder's
part of an unwind can wait for the holder.

## Test Cases

A conforming implementation passes these cases. Each starts from a base token of 18 decimals that trades in sessions and
is priced 250 quote by a feed of 8 decimals, a quote token of 6 decimals, and a lender that lends up to the value of the
base brought, unwinds below an `unwindBps` of 11000, requires a `gapBps` of 2000, charges 1% for 30 days, hands over
14 days past the due date, and accepts prices at most a day old. The holder brings 100 base and borrows 25,000 quote.
The positions in the tests are full-range, so this one is worth 50,000 at 250, and 50,000 times the square root of
`P / 250` at a price `P`.

- `quoteLimit` for 100 base is 25,000 and does not move with the pool's own price. An open of 25,000 takes 100 base and
  25,000 quote, records 25,250 owed, keeps the position token, emits `PositionOpened` and returns id 1; an open of one
  unit more reverts, as does an open with an identity the caller does not own.
- An open on a pool whose price was pushed up 100 times reverts: the position would be worth 5,000 at the feed's price.
  With an `unwindBps` of 18000 an open reverts, since the position would be worth 44,721 after a 20% fall; with a
  `gapBps` of 0 it succeeds.
- Quote fees of 300 and base fees of 2, applied by a stranger, pay the lender 300 and the holder nothing, leave 24,950
  owed and leave the 2 base in the position. With 50 owed, quote fees of 300 pay the lender 50 and the holder 250.
- A close by anyone but the holder reverts. The holder's close takes 25,250 and returns the position token, also with no
  usable price and with the base token blocking the escrow and the holder.
- At 80 the position is worth 28,284 and `unwind` reverts. A pool price of 10 or 100,000 leaves `health` unchanged.
- At 70, in the feed and the pool, an unwind by a stranger pays the lender 13,228.76 quote and 171.732 base at its
  fallback address, and leaves 17.250 base in the position token, now the holder's; it reports 25,250 recovered and no
  shortfall. Opened at 256 and settled when due at 255 with the pool still at 256, where every amount is exact, the
  lender takes 25,600 quote and 1,003,921,568,627,450,981 base units (256/255 of 1e18, rounded up), and nothing is
  short. At 70 in the feed and 250 in the pool, the lender takes 25,000 quote and 3.571 base. At 20, the lender takes
  everything and the unwind reports 14,142.14 recovered and the rest as shortfall.
- An answer that is zero, negative, from the future or more than a day old, or a feed of 19 decimals, makes `health` and
  `unwind` revert and `quoteLimit` return 0. One second before `dueAt` a healthy position cannot be unwound; at `dueAt`
  it can.
- With quote fees that repay all that is owed, the position is not unwindable at `dueAt`, and an unwind by anyone
  reverts at `dueAt`, past the hand-over time with the feed silent, and with a terminal status, at once and a day
  later. The holder's close takes nothing, emits `PositionClosed` with 0, and returns the position token as `Closed`.
- With the base token blocking the escrow and the holder, the unwind at 70 still pays 171.732 base to the fallback
  address. With the base token blocking the pool, it pays the quote, gives the position token to the fallback address
  and reports the base it could not pay as shortfall.
- On a session break, a fresh answer of 70 is not used, even after `dueAt`: `health` and `unwind` revert, `quoteLimit`
  is 0 and `open` reverts, while `applyFees` and `close` succeed. After the market reopens, an answer refreshed a
  minute before the opening is not used, and the first answer of the session, 70, allows the unwind. A halt gives no
  price either. A status source that reverts, has no code or answers outside `TradingStatus` gives no price; a pool
  whose base trades continuously needs no status source.
- No position records a `handoverDelay` below 14 days: terms with a delay of 0, six hours or one second short of 14
  days are refused, and a position opened on terms of 14 days records 14 days.
- With the feed silent since the opening, an unwind one second before `dueAt + handoverDelay` reverts. At that time an
  unwind by a stranger hands the position over: the lender receives 25,000 quote, and the position token with the 100
  base still in it at its fallback address; no base token moves; the status is `HandedOver`; and `PositionHandedOver`
  reports 25,000 recovered and 250 outstanding.
- At the hand-over time, a feed whose last answer is two days old is late, not silent, and the unwind reverts until
  that answer is more than 14 days old; a fresh answer of zero counts as silence and hands the position over.
- A session break that runs past the hand-over time, even one reported for weeks with the feed silent, never hands
  over; once the market reopens, an answer from before the break is late, not silent, and the first answer of the
  session, 70, unwinds the position at a price, leaving the holder its part. The same stop reported as a halt hands
  over. A halt that began an hour before the hand-over time hands over only once it has lasted more than 14 days.
- A terminal status gives no price and hands nothing over for a day: with the feed still answering, an unwind reverts
  at once and one second before `since + TERMINAL_GRACE`, and at that time an unwind by a stranger hands a healthy
  position over, a month before `dueAt`, while the base token blocks every transfer. Inside the day, with the feed
  dead, a stranger's unwind reverts and the holder's close takes 25,250 and returns the position token, with all of
  its liquidity, as `Closed`. A terminal status dated a day ahead of the block hands over two days later, and one
  dated a day back hands over at once. Past `dueAt + handoverDelay`, a terminal status that begins when the feed has
  been silent for the delay hands the position over at once; with the feed answering, it waits its day.
- A status source that reverts or answers outside `TradingStatus`, once or for longer, hands nothing over past
  `dueAt + handoverDelay` while the feed answers; once the source answers again, the overdue position is unwound at the
  feed's 250 and the holder keeps its part. With the source failing and the feed silent for exactly 14 days the unwind
  reverts, and one second later it hands the position over.
- With a quote token that burns 1% of every transfer, a close that would deliver 24,997.5 of the 25,250 owed reverts;
  quote fees of 300 pay the lender the 297 that arrive and reduce `owed` by 297; and the unwind at 70 takes base for what
  is owed minus the quote that arrived.
- For bases of 6, 8 and 18 decimals, quotes of 6 and 18 and feeds of 8 and 18, `quoteLimit` for 100 base is exactly
  25,000 quote, 25,250 is owed, and the unwind at 70 pays the lender 171.732 base.
- For the same bases and quotes and feeds of 0, 8 and 18 decimals, with 2^100 base units owed to the position token, the
  largest answer the contract accepts lets `health` answer and an unwind past `dueAt` recover all that is owed, and one
  unit more is not used. An answer of `type(int128).max` makes `health` and `unwind` either answer or refuse the price,
  never fail with an arithmetic error. A pool whose feed gives a price out of bounds cannot be added.

## Reference Implementation

`CreditMatchedLiquidity` accompanies this proposal with its tests and mocks. It has one lender: its own quote balance is
what it lends, and the lender lists each pool with a price feed, a status source for a base traded in sessions, the
ratio behind `quoteLimit`, `unwindBps`, `gapBps`, a charge, a term, a hand-over delay and `maxPriceAge`. Its `listPool`
reverts with `BadTerms()` for a hand-over delay below `MIN_HANDOVER_DELAY`, 14 days, so that no position records a
shorter one, and it hands a position over for a terminal status `TERMINAL_GRACE`, one day, after the status's `since`;
both are public constants. It talks to a v3-style position manager through a reduced interface whose `amountsAt`
returns what a position holds at a given price; against a Uniswap v3 manager an implementation computes the same with
that protocol's tick and liquidity math. It reads the trading status through `ITradingStatus`, which an adapter can
derive from a status interface on the token, a feed's market-status report or an issuer's pause flag, with a low-level
call whose answer it checks, so that a source that reverts, has no code or answers outside `TradingStatus` reads as
`Unknown` and makes no call revert. It accepts prices up to 1e48 quote units per 1e18 base units, which keeps every
amount in range for token amounts up to 2^128, computes with a 512-bit multiply-then-divide, and measures every
movement of the quote token by balance. It is not audited and must never be deployed without an external audit.

## Security Considerations

- **Not audited.** The reference implementation is a draft, written against mocks to show the interface. It has not
  been audited and must never be deployed without an external audit.
- **Oracle manipulation and staleness.** Everything that protects the lender rests on the feed. A feed that can be moved,
  because its market is thin, it has one reporter, or someone in the loan controls it, can be used to unwind healthy
  positions or to open against a value that is not there. Lenders SHOULD use feeds aggregated from several sources, with
  a heartbeat shorter than `maxPriceAge`; holders SHOULD read a position's `priceFeed`, `statusSource` and
  `handoverDelay` before opening. A feed that stops updating stops opening and unwinding: the position then waits for
  the feed or for the holder to close, until the feed has been silent for the hand-over delay past the due date and
  the position is handed over. On rollups a halted sequencer delays feed updates, and implementations there SHOULD also
  check the sequencer's uptime. Decimals are read, never assumed, and implausibly large answers are rejected.
- **Market closures and gaps.** No price exists while a stock's market is closed, and the first price after it reopens
  can differ from the last by more than `gapBps`. A position can then be worth less than it owes when it first becomes
  unwindable, and the lender takes the shortfall; `gapBps` and `unwindBps` are its only protection, since there is no
  price in a closed market at which an unwind could do better. A halt, a delisting or a redemption can gap further, or
  end with no price at all; past the hand-over delay, or a day after a terminal status began, the lender then takes the
  position without a price.
- **The hand-over and the holder.** A hand-over gives the lender the whole position token: the holder's part of the
  base, and any quote beyond `owed`, go with it, and whatever the lender returns of it is settled outside this
  interface. A holder that wants to keep its part has to close before `dueAt + handoverDelay`; closing needs no price,
  so no outage or halt stops it. A terminal status hands a position over `TERMINAL_GRACE`, one day, after the `since`
  its source reports, before its due date too, so holders of a base token that can be delisted or redeemed SHOULD
  watch its status and keep the quote to close at hand.
- **A short hand-over delay.** The delay is the holder's last time to close after the due date, and how long a feed
  must be silent, or a halt last, before the lender takes the whole position without a price. A delay of hours would
  let a lender take positions over an outage or a halt that would have ended in an unwind at a price, in which the
  holder keeps its part, and a lender that runs the feed, or can hold back its updates, could arrange such an outage.
  A delay shorter than the longest scheduled closure of the base token's market would let a feed that does not answer
  while the market is closed look silent at the reopening, before the session's first price, when anyone, the lender's
  keeper first, could hand the position over. The floor of 14 days is therefore a requirement: a contract that records
  a shorter `handoverDelay` does not conform, and a holder can rely on the floor without reading each pool's terms.
- **A wrong or malicious status source.** The status source is trusted like the feed, and one the lender controls is
  worse than a feed it controls: by reporting `Terminal` it hands every open position over a day later, due or not,
  holder's part included, and at once if it dates the status a day back. Holders SHOULD open only against a status
  source the lender cannot write, such as the token issuer's own status or an adapter over it. A source that reports
  `Trading` during a halt or a break lets a stale price through. One that reports a session break for ever stops every
  unwind and every hand-over, and the lender waits on it as on a feed that never returns; so does one that reports
  `Terminal` with a `since` far ahead while the feed keeps answering. One that wrongly reports `Halted` can hand over
  only a position already past its due date and delay, and only once the halt it reports has lasted the delay. A
  source that reverts, has no code or answers outside `TradingStatus` reads as `Unknown`, and so does one that reports
  it: it lets no price through, and it hands a position over only from `dueAt + handoverDelay` and only when the feed
  has also been silent for the whole delay, the same bar as a silent feed alone, so a source that fails for one call
  hands nothing over. A source that stays unknown while the feed keeps answering stops every unwind and every
  hand-over, like one that reports a session break for ever.
- **A backdated `since`.** The grace after a terminal status runs from the `since` the status source reports, which
  the contract cannot check. A source that reports `Terminal` with a `since` a day or more in the past hands positions
  over with no window at all, and an honest source that learns of a delisting late, and dates it from when it took
  effect, leaves less than a day. Trusting a source with `since` is the same trust as trusting it with `Terminal`: a
  source that would backdate `since` could as well report `Terminal` falsely, and the grace protects holders only
  against a terminal state that is real and reported when it happens. Holders limit the risk as they limit a false
  `Terminal`: by opening only against a source the lender cannot write and that reports promptly, such as the token
  issuer's own status or an adapter over it, and by watching the base token's status, and the issuer's notices of a
  delisting or a redemption, which often come before it takes effect, so as to close as soon as one is announced or
  reported. A `since` later than the block timestamp begins no window: it holds the hand-over back until
  `since + TERMINAL_GRACE`, unless a feed silent for the hand-over delay past the due date makes one due first.
- **Telling a hand-over from an unwind.** A hand-over emits `PositionHandedOver` and leaves the status `HandedOver`; an
  unwind emits `PositionUnwound` and leaves `Unwound`, and neither emits the other's event. `shortfall` in an unwind is
  a loss valued at the feed's price. `outstanding` in a hand-over is not valued: it is what the quote did not cover,
  and the lender holds the position token against it, which may be worth more or less. A reader that builds a credit
  history SHOULD NOT count `outstanding` as a loss. A hand-over before `dueAt + handoverDelay` can only come from a
  terminal status of the base token, not from the holder; one at or after that time means the holder had not repaid by
  then.
- **Pool-price manipulation.** Lenders that valued pool shares from the pool's own reserves have been drained by flash
  loans that moved those reserves within one transaction, the Warp Finance exploit of 2020 being the best known. This
  interface never values a position from its pool. The pool's price still sets the proportions of a mint: a holder whose
  opening is sandwiched deposits at a moved price and loses as any liquidity provider would. The gap check makes such
  an opening revert when it would leave the lender exposed, and holders SHOULD open through a private route or a
  contract that bounds the pool's price against the feed's. At an unwind a moved pool price changes the mix withdrawn,
  not its value at the feed's price.
- **Fee accounting.** Fees are what the position manager credits to the position token. Quote fees pay the lender before
  the holder, and base fees stay in the position until it is closed or unwound, so no fee leaves for the holder while
  anything is owed. `health` may leave out fees not yet credited, which only makes a position look worse than it is. A
  holder that trades through its own range pays fees to every provider in range, itself included, and its own share
  pays the lender first, so fees cannot move value out of the position. Charges and the lender's base round up, values
  round down.
- **Transfer-blocked tokens.** A tokenized stock's registry can block any address. No base token passes through the
  contract at closing, unwinding or a hand-over: at an unwind the lender's base goes from the position manager to
  `lenderFallback()` and the holder's part stays owed to the position token, and at a hand-over all of the base stays
  owed to the position token the lender receives. If the registry blocks the pool or the position manager, no base can
  leave it; the unwind then pays the quote, gives the position token, with all of its base, to the lender's fallback
  address and reports the base it could not pay as shortfall. The holder's part of that base is then held by the lender,
  outside this interface. A quote token that blocks the contract or the holder can stop `applyFees` and `close`.
- **Tokens that do not move exact amounts.** A token that charges on transfer, or rebases, makes the amount requested
  differ from the amount received. Accounting by the amount requested would let a holder close while the lender
  receives less than it lent, and would overstate what fees and unwinds repaid. Measuring each movement by balance keeps
  `owed` and the events true; such a quote token cannot be repaid in full through `close`, so lenders should not lend it.
- **Arithmetic.** A feed can report any answer, and decimals vary: a base of 6 decimals priced by a feed of 0 decimals
  in a quote of 18 turns a large answer into a very large price per base unit. Products of prices and amounts that
  overflow would make `health` and `unwind` revert exactly when a position needs unwinding. Bounding prices, refusing
  pools whose feed is out of bounds, and computing in full precision keep both answering.
- **Liquidation front-running.** An unwind is open to anyone, pays no reward and settles at the feed's price, so racing
  another caller gains nothing: the caller only chooses the moment. A holder that sees a feed update coming may close or
  apply fees first, which is allowed. Anyone may unwind in the block that makes a position unwindable, but since the
  unwind pays at the feed's price, nobody profits at the holder's expense. An implementation that rewards the caller
  creates a race; it SHOULD pay the reward from the lender's share and cap it.
- **Re-entrancy.** The position manager, both tokens, the feed and the status source are external contracts.
  Implementations SHOULD guard `open`, `applyFees`, `close` and `unwind` against re-entry.
- **Identity.** `agentId` is checked against the registry at opening. A reader that counts positions as credit events
  of an identity still trusts the contract to have checked it.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
