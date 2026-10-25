---
eip: 99902
title: Agent Repay-First Payees
description: A revenue address for an agent identity that pays its creditors before its owner
author: Priors contributors (@priors-agents)
discussions-to: https://ethereum-magicians.org/t/erc-tba-agent-repay-first-payees/30025
status: Draft
type: Standards Track
category: ERC
created: 2026-10-20
requires: 20, 165, 721, 7254, 8183
---

## Abstract

This proposal defines a payee: a contract that an agent identity, held in an [ERC-721](./eip-721.md) identity registry,
uses as the address where it is paid. When the payee is swept, it pays each registered creditor what that creditor says
it is owed, most senior first and up to a share of the swept balance the creditor agreed to, and forwards the rest to the
agent's owner or an address the owner chose. What a creditor does not take, up to what it is owed, stays in the payee in
reserve for it, so a lender that takes repayment only in full is repaid once its reserve covers what is due. The owner
adds creditors, each junior to the ones before, and cannot remove a creditor that still has a claim. A small creditor
interface lets any lender take part, and any payer, explorer or lender can tell that an identity's revenue address is
encumbered. An optional part lets the payee be the provider of an [ERC-8183](./eip-8183.md) job: ERC-8183 pays the
provider and takes the work only from it, so the payee submits the work for the owner and is paid by the job. Another
lets the holders of an [ERC-7254](./eip-7254.md) revenue-sharing token share what the creditors leave, with the token
as the payee's beneficiary.

## Motivation

Lending to an agent against what it earns is safest when repayment comes from the earnings themselves, before the agent
or its owner can spend them. Agent revenue already arrives at addresses the agent names: a pay-to address for HTTP
payments signed with [ERC-3009](./eip-3009.md) transfers, the provider address of an ERC-8183 job, the
payment wallet of an [ERC-8004](./eip-8004.md) identity. None of these says anything about what happens to the money
once it arrives. A payee can be the first two: a pay-to address, and a job's provider. It cannot be set as an ERC-8004
payment wallet as that proposal is specified, since ERC-8004 sets `agentWallet` only with the new wallet's signature
and a payee validates none (Rationale).

Lenders that route revenue through a contract of their own today can only trust their own contract, and nobody else can
tell that the address is encumbered. A common payee interface lets several lenders share one revenue address with a
clear order of priority, lets a new lender see existing claims before it lends, and lets an agent move between lenders
without changing where it is paid.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT
RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interfaces

A payee MUST implement `IRepayFirstPayee` and [ERC-165](./eip-165.md), returning `true` for the interface identifier of
`IRepayFirstPayee` and for `0x01ffc9a7`. A creditor MUST implement `IRepayFirstCreditor`.

```solidity
interface IRepayFirstPayee {
    event CreditorAdded(address indexed creditor, uint16 maxShareBps);
    event CreditorRemoved(address indexed creditor);
    event BeneficiarySet(address indexed beneficiary);
    event Swept(address indexed token, uint256 toCreditors, uint256 forwarded);
    event Reserved(address indexed creditor, address indexed token, uint256 amount);

    function identityRegistry() external view returns (address);
    function agentId() external view returns (uint256);
    function beneficiary() external view returns (address);
    function creditors() external view returns (address[] memory);
    function maxShareBps(address creditor) external view returns (uint16);
    function reserved(address creditor, address token) external view returns (uint256);
    function addCreditor(address creditor, uint16 maxShareBps) external;
    function removeCreditor(address creditor) external;
    function setBeneficiary(address beneficiary) external;
    function sweep(address token) external returns (uint256 toCreditors, uint256 forwarded);
}

interface IRepayFirstCreditor {
    function amountOwed(uint256 agentId, address token) external view returns (uint256);
    function hasClaim(uint256 agentId) external view returns (bool);
    function collect(uint256 agentId, address token, uint256 amount) external returns (uint256 applied);
}
```

### The payee

- `identityRegistry()` and `agentId()` MUST NOT change. The **owner** is the registry's `ownerOf(agentId())` at the
  time of each call.
- `beneficiary()` MUST return the address last set with `setBeneficiary` while the owner that set it still owns the
  identity, and the owner otherwise (including when none is set or the zero address was set). When the registry cannot
  name an owner (its `ownerOf` reverts, as for a burned identity), it MUST return the address last set, or the zero
  address when none is set, and MUST NOT revert.
- `creditors()` MUST return the creditors in order of seniority: the earliest added first.
- `maxShareBps(creditor)` MUST return the share given when the creditor was added, and `0` for an address that is not a
  creditor.
- `reserved(creditor, token)` MUST return the creditor's reserve in `token` (see Sweeping) as the last sweep of `token`
  left it, and `0` for an address that is not a creditor.

### Adding and removing creditors

- `addCreditor(creditor, maxShareBps)` MUST revert unless called by the owner, and MUST revert if `creditor` is already
  a creditor, is the zero address, or if `maxShareBps` is `0` or greater than `10000`. It MUST place the new creditor
  after every existing one and emit `CreditorAdded`. A payee MAY cap the number of creditors.
- `removeCreditor(creditor)` MUST succeed when called by `creditor` itself. When called by the owner it MUST revert if
  the creditor's `hasClaim(agentId())` returns `true` or reverts. It MUST revert for any other caller. It MUST keep the
  order of the remaining creditors and emit `CreditorRemoved`. It MUST end the creditor's reserves in every token: what
  they held counts in `B` at the next sweep. A creditor added again starts with no reserve.
- A creditor's share and position MUST NOT change while it remains a creditor.
- `setBeneficiary(beneficiary)` MUST revert unless called by the owner, and MUST emit `BeneficiarySet`.

### Sweeping

The payee keeps, for each creditor and token, a **reserve**: what sweeps offered the creditor in that token and the
creditor did not take. Only a sweep or the creditor's removal changes it.

`sweep(token)` MUST be callable by any account. It MUST first read, for each creditor, `owed`, its
`amountOwed(agentId(), token)`, and lower the creditor's reserve in `token` to `owed` where the reserve is greater. With
`B` the payee's balance of the [ERC-20](./eip-20.md) `token` at the start of the call less the creditors' reserves in
`token` so lowered (zero if they are greater), it MUST then, for each creditor in order of seniority:

1. compute `give` as the least of `owed` less the creditor's reserve, `B * maxShareBps(creditor) / 10000` (rounded
   down), and what remains of `B`, and deduct `give` from what remains of `B`;
2. with `offer` the creditor's reserve plus `give`, if `offer` is not zero, approve the creditor for exactly `offer`,
   call `collect(agentId(), token, offer)`, then set the approval back to zero;
3. count as paid to that creditor the decrease of the payee's balance across the call, and set its reserve to `offer`
   less what it was paid.

Then, unless `beneficiary()` is the zero address, it MUST transfer what remains of `B` to `beneficiary()`; when it is
the zero address, what remains stays in the payee, outside any reserve, and counts as not forwarded. It MUST emit
`Reserved` for each creditor whose reserve in `token` the call changed, with the new reserve, and `Swept` with the
totals, and return them. A creditor whose `amountOwed` reverts MUST be treated as owed nothing for that sweep, which
releases its reserve. A creditor whose `collect` reverts is paid nothing, and what it was offered stays in its reserve.
In both cases the sweep MUST go on. A payee SHOULD call each creditor with a bounded amount of gas, so that one creditor
cannot make every sweep fail.

### The creditor

- `amountOwed(agentId, token)` MUST return what the identity owes the creditor in `token` and may be paid now. A
  creditor that accepts a payment only when it settles a debt in full returns the whole amount that settles it.
- `hasClaim(agentId)` MUST return `true` while the creditor has any claim on the identity, due or not.
- `collect(agentId, token, amount)` MUST take at most `amount` of `token` from the calling payee and apply it to what
  the identity owes; it MUST return the amount taken. It MUST NOT take what it cannot apply now in order to hold it for
  a later repayment: what it leaves stays in the payee's reserve for it and is offered again at the next sweep.

### Acting as an ERC-8183 provider (optional)

ERC-8183 pays a job's escrow to the job's provider when the job is completed, and accepts a budget proposal and the
submission of the work only from that provider. A payee that is to be a job's provider implements
`IRepayFirstProvider`, and MUST then return `true` from `supportsInterface` for the interface identifier of
`IRepayFirstProvider`.

```solidity
interface IRepayFirstProvider {
    event OperatorSet(address indexed operator);

    function operator() external view returns (address);
    function setOperator(address operator) external;
    function setJobBudget(address commerce, uint256 jobId, uint256 amount, bytes calldata optParams) external;
    function submitJob(address commerce, uint256 jobId, bytes32 deliverable, bytes calldata optParams) external;
}
```

- `operator()` MUST return the address last set with `setOperator` while the owner that set it still owns the identity,
  and the zero address otherwise, including when the registry cannot name an owner. `setOperator(operator)` MUST revert
  unless called by the owner, and MUST emit `OperatorSet`.
- `setJobBudget(commerce, jobId, amount, optParams)` MUST call `setBudget(jobId, amount, optParams)` on `commerce`, and
  `submitJob(commerce, jobId, deliverable, optParams)` MUST call `submit(jobId, deliverable, optParams)` on it. Both
  MUST revert unless called by the owner or by `operator()` when it is not the zero address, and MUST revert when the
  call to `commerce` reverts.
- A payee MUST NOT make any other call for the owner or the operator. What a job pays the payee on completion is a plain
  transfer, which sweeps pay out like any other revenue.

### Paying holders after creditors (optional)

An agent can pay the holders of a token from what its creditors leave. The token implements `IHoldersAfterCreditors`
and ERC-7254, under which holders accrue rewards in registered reward assets and withdraw them with `getReward`. The
owner sets the token as the payee's beneficiary with `setBeneficiary`. A token that implements
`IHoldersAfterCreditors` MUST implement ERC-7254 and ERC-165, returning `true` for the interface identifier of
`IHoldersAfterCreditors` and for `0x01ffc9a7`.

```solidity
interface IHoldersAfterCreditors {
    event RevenueFromPayee(address indexed payee, address indexed asset, uint256 amount);

    function payee() external view returns (address);
    function syncFromPayee(address asset) external returns (uint256 booked);
}
```

- The token's place is the payee's beneficiary, never one of its creditors. The token MUST NOT implement
  `IRepayFirstCreditor`, so that a payee that lists it as a creditor finds it owed nothing.
- `payee()` MUST return the agent's payee and MUST NOT change.
- `syncFromPayee(asset)` MUST be callable by any account. What it books is the amount by which the token's balance of
  `asset` exceeds what the token already accounts for: what earlier syncs and `updateReward` calls booked, less what
  holders withdrew. It MUST book that amount as ERC-7254 rewards of `asset`, raising the reward per share by the amount
  divided by `totalSupply()` as `updateReward` does, and MUST return it. Each unit MUST be booked once: a second sync
  with nothing new received books nothing, and what `updateReward` brought in is not booked again.
- `syncFromPayee` MUST emit `RevenueFromPayee` with `payee()`, `asset` and the amount booked when that amount is not
  zero, and only then. `updateReward` MUST NOT emit `RevenueFromPayee`.
- `syncFromPayee(asset)` MUST revert if `existsTokenReward(asset)` returns `false`.
- When `totalSupply()` is zero, `syncFromPayee` MUST book nothing and return `0`. What the token holds stays unbooked,
  and the first sync at a non-zero supply books it.
- `syncFromPayee` MUST NOT revert because the payee's `beneficiary()` is not the token. It books what reached the token,
  including what sweeps forwarded while the token was the beneficiary, and nothing that a sweep sent elsewhere.

A beneficiary set by an owner holds only while that owner holds the identity. After a sale, sweeps forward what is left
to the new owner, not to the token, until the new owner calls `setBeneficiary` with the token. Holders SHOULD check that
the payee's `beneficiary()` returns the token, and read its `creditors()` and their shares, before counting on the
agent's revenue.

## Rationale

- **Plain transfers in, sweeps out.** HTTP payments signed with ERC-3009 and job payouts are plain token transfers that
  call nothing on the receiver. A payee that acts on arrival would need every payer to change; a payee that anyone can
  sweep needs none to change.
- **Seniority by order of addition.** Each creditor lends knowing who is ahead of it. Allowing the owner to reorder or
  re-share creditors would let it subordinate a lender after the loan was made.
- **A share per creditor.** A lender that takes all revenue can starve the agent of what it needs to keep working. The
  share lets the owner and the lender agree on how much of each payment services the debt.
- **The creditor applies the money.** Only the creditor knows which of its loans a payment repays and how. Approving
  exactly `offer` and measuring the balance keeps the payee correct whatever the creditor does.
- **A reserve in the payee, not a forward.** Some lenders take a repayment only in full: a loan opens once and closes
  once. If a sweep forwarded what such a lender could not take yet, ten payments of 10 would all reach the owner while
  100 stayed due, and only a single payment of 100 would repay it. The payee keeps what a creditor does not take and
  offers it again at each sweep, so the loan is repaid once the reserve covers it. The money stays in the contract
  whose rules the owner and the creditor already rely on: neither can move it outside a sweep, and the creditor stays a
  thin adapter. A reserve held by the creditor would put the agent's money in the creditor's custody and count it as
  paid before anything was repaid; requiring partial repayment would change how every lender accounts for its loans.
- **A reserve follows what is owed.** The payee knows no due dates or defaults, only `amountOwed`. Lowering a reserve
  to it at each sweep releases what a debt repaid from elsewhere, forgiven or closed no longer needs, and ending the
  reserves with the creditor's place means a creditor that leaves takes nothing with it.
- **Removal needs no claim.** The owner can drop a creditor it no longer uses, but not one that is still owed, which is
  what makes the payee worth lending against. A creditor whose claim check fails is treated as owed, so it cannot be
  dropped by making it unreachable.
- **A beneficiary lapses with its owner.** If a beneficiary outlived a sale, a seller could set its own wallet just
  before selling and, since anyone may sweep, collect the revenue the buyer earns until the buyer noticed. Tying the
  choice to the owner that made it sends post-sale revenue to the buyer without any action from the buyer.
- **The identity, not the owner.** The payee belongs to the identity; after a transfer the new owner controls it but
  inherits its creditors. Whether a debt follows the identity or its former owner is each creditor's choice, expressed
  through `amountOwed` and `hasClaim`.
- **The payee is the provider.** ERC-8183 takes the submission only from a job's provider and pays the provider. An
  adapter set as the provider in front of the payee would be paid in its place and hold each payment until someone moved
  it on, and readers would have to check the adapter's routing as well as the payee. As the provider, the payee is paid
  directly, and since ERC-8183 sets a job's provider once, before funding, a job that names the payee cannot be pointed
  elsewhere.
- **Two calls, not a general one.** A call forwarded for the owner to any function would let the owner call a token from
  the payee and move its balance outside a sweep. `setBudget` and `submit` move nothing out of the payee: a token has
  neither function, and outside a sweep the payee holds no approval. They take `optParams` as ERC-8183's reference
  implementation does.
- **An operator that lapses with its owner.** The key that does the agent's work can submit it without holding the
  identity. Like a beneficiary, it stops acting for the agent once the owner that named it no longer holds the identity.
- **A pay-to address, not an ERC-8004 payment wallet.** ERC-8004's `setAgentWallet` takes the new wallet's signature:
  [EIP-712](./eip-712.md) for an account without code, [ERC-1271](./eip-1271.md) for a contract. A payee validates no
  signature, so it cannot be set as `agentWallet`. Accepting the owner's signatures would be the wrong way to allow it:
  Permit2 and some tokens accept ERC-1271 signatures for transfers, so the owner could sign the payee's balance away
  outside a sweep. A payee that validates only an `agentWallet` digest it computes itself would avoid that, but ERC-8004
  leaves the typed data of that digest to each registry; whether such a part is worth specifying, or a pay-to address is
  enough, is left open.
- **Holders as the beneficiary.** With seniority by order of addition, a token added as a creditor would rank ahead of
  every lender added after it, the opposite of holders last. As the beneficiary, the token receives only what every
  creditor, present or future, left. A splitter that pays fixed tranches in order before a residual recipient gives the
  same order for debts fixed once; here lenders join and leave, and holders stay last.
- **A sync, not a pull.** ERC-7254 books rewards only through `updateReward`, which pulls them from its caller. A sweep
  is a plain transfer that calls nothing on the receiver, so the token books what arrived when anyone calls
  `syncFromPayee`, and the payee needs no change.
- **A marker, not a total.** `updateReward` stays open to anyone, so a token's rewards can come from elsewhere.
  `RevenueFromPayee` separates what arrived by plain transfer, which for a token set as beneficiary is what the payee
  forwarded.
- **Registered assets only.** ERC-7254 adjusts holders' entries on each transfer only for its registered reward assets.
  Booking another asset would let a holder claim it again after receiving tokens. `updateReward` refuses such assets
  too.
- **No booking without holders.** At zero supply there is nobody to share among and no reward per share to compute.
  Leaving the balance unbooked keeps it for the first holders.
- **The token's place lapses with the owner.** The rule that a beneficiary holds only while its owner holds the
  identity has no exception for a token. Otherwise a seller holding most of a token could set it as beneficiary before
  selling and keep a share of the revenue the buyer earns.

## Backwards Compatibility

No backward compatibility issues found. The payee is an ordinary address for payers, so existing payment flows need no
change.

## Test Cases

A conforming payee passes these cases, each for one identity whose owner receives what is forwarded:

- With no creditors, a sweep of 100 units forwards 100 units.
- With one creditor owed 30 units at a share of 10000, a sweep of 100 units pays it 30 units and forwards 70 units.
- With one creditor owed 50 units at a share of 2000, a sweep of 100 units pays it 20 units and forwards 80 units.
- With two creditors owed 60 units each at a share of 10000, a sweep of 100 units pays the first 60 units and the second
  40 units, and forwards nothing.
- A creditor whose calls revert is paid nothing, nothing is reserved for it, and the rest is forwarded.
- A creditor at a share of 3000, owed more than 30 units, that tries to take more than it was approved for is paid
  nothing on a sweep of 100 units; 30 units stay in its reserve and 70 units are forwarded. The approval to every
  creditor is zero after each sweep.
- With one creditor owed 50 units at a share of 10000 that takes half of what it is offered, a sweep of 100 units pays
  it 25 units, keeps 25 units in its reserve and forwards 50 units.
- With one creditor owed 100 units at a share of 10000 that takes a payment only when it covers all 100 units, each of
  nine sweeps of 10 units pays it nothing and forwards nothing, and its reserve rises by 10 units each time, emitting
  `Reserved`; a tenth sweep of 10 units pays it 100 units and leaves no reserve; a sweep of 100 units after that
  forwards 100 units.
- With 90 units in that creditor's reserve, once its loan is repaid from elsewhere, or defaulted and it reports nothing
  owed, a sweep of 10 more units forwards 100 units and leaves no reserve. A reserve is released in the same way when
  the creditor's `amountOwed` reverts, and when the creditor removes itself; added again, it starts with no reserve.
- The owner cannot remove a creditor still owed; it can once the creditor is repaid; a creditor can always remove itself,
  and the others keep their order.
- After the identity is transferred, the new owner is the default beneficiary and cannot remove a creditor still owed.
- An owner sets a beneficiary and then transfers the identity; a sweep of 100 units received afterwards forwards 100
  units to the new owner and nothing to the beneficiary the former owner set.
- After the identity is burned, with no beneficiary set, a sweep of 100 units with one creditor owed 30 units pays it 30
  units, forwards nothing, and leaves 70 units in the payee.

A payee implementing the ERC-8183 provider part passes these cases, for a job whose provider is the payee:

- With one creditor owed 30 units at a share of 10000, the owner proposes a budget of 50 units through the payee and the
  client funds it; the owner's own address cannot submit, and the owner submits through the payee; the evaluator
  completes, the job pays the payee 50 units, and a sweep pays the creditor 30 units and forwards 20 units.
- An operator the owner set proposes a budget and submits. After the identity is transferred, `operator()` is the zero
  address, the operator can do neither, and the new owner can.
- Any other account can neither propose a budget, submit, nor set the operator, and after the identity is burned no one
  can propose a budget or submit.
- With a token or an address with no code named as `commerce`, both calls revert and the payee's balance is unchanged.

A token implementing the holders part passes these cases, with the token as the beneficiary and two holders of 75%
and 25% of its supply:

- With one creditor owed 20 units, a sweep of 100 units pays it 20 units and forwards 80 units to the token; a sync by
  any account books 80 units, of which the holders can withdraw 60 and 20 units.
- A second sync with nothing new received books nothing. After the holders withdraw, a forward of 40 units is booked as
  40 units.
- A sync that books 80 units emits `RevenueFromPayee` with the payee, the asset and 80 units; a sync that books nothing
  emits nothing.
- An `updateReward` of 10 units by another account is shared by the holders, emits no `RevenueFromPayee`, and is not
  booked again by the next sync.
- A sync of an asset the token does not reward reverts.
- At zero supply a sync books nothing; once tokens are minted, the next sync books the whole balance, once.
- The owner lists the token as a creditor ahead of a lender owed 30 units; a sweep of 100 units pays the lender 30
  units, the token nothing as a creditor, and forwards 70 units to the token as the beneficiary.
- After the identity is sold, a sweep of 100 units with a creditor owed 20 units forwards 80 units to the buyer, and a
  sync books nothing without reverting. Once the buyer sets the token as beneficiary, the next sweep's rest is booked.
- A sync after a sale still books what sweeps forwarded to the token before the sale.

## Reference Implementation

`RepayFirstPayee` and a factory that deploys one payee per identity at a CREATE2 address known before deployment
accompany this proposal with their tests. The payee calls each creditor with a fixed gas budget and holds at most eight
creditors. It keys each creditor's reserves by the place it was given when added, never reused, so removing a creditor
ends its reserves in every token without listing them. It implements `IRepayFirstProvider`; its tests run a job through
a minimal ERC-8183 contract, from creation to the sweep.

`HoldersAfterCreditorsToken`, an ERC-20 token that implements ERC-7254 and `IHoldersAfterCreditors`, accompanies the
holders part with its tests. Its reward assets are fixed when it is deployed. Unlike ERC-7254's own reference, which
counts the remainder below one unit of a claim as withdrawn, it keeps that remainder claimable.

## Security Considerations

- **The revenue address can be changed.** Payers pay whatever address the agent advertises. An owner can advertise a
  new address and route future revenue around the payee. Creditors SHOULD check, where the agent publishes the address
  on chain, that it still points to the payee before each draw, and price the rest as unsecured. A payee cannot be the
  agent's ERC-8004 payment wallet (Rationale), so what payers send to `agentWallet` does not reach it.
- **Creditors are trusted with their own figures.** A creditor reports its own `amountOwed`. A creditor the owner added
  can over-report and take up to its share of every sweep, or leave it in its reserve, out of the owner's reach until
  the creditor reports less or leaves. Owners SHOULD add only lenders they borrowed from.
- **A reserve short of what is due.** A lender that takes repayment only in full is repaid when its reserve reaches
  what is due. If the agent's revenue, within the lender's share, has not reached it by the due time, the loan runs late
  with the reserve held. A creditor that reports nothing owed once its loan is defaulted releases the reserve to the
  creditors after it and to the beneficiary; a creditor that means to recover from the reserve after a default SHOULD
  keep reporting what it can recover, and apply what it takes as a recovery. Lenders SHOULD set the share and the term
  so that the agent's expected revenue covers what is due before the due time.
- **Creditor calls.** Creditors are external contracts; a payee MUST approve only `offer`, MUST reset the approval, and
  SHOULD bound the gas of each call and guard against re-entry into `sweep`, `addCreditor` and `removeCreditor`.
- **Jobs.** A job pays the provider it names, so the payee is paid only by jobs that name it. As with an advertised
  address, creditors that count on job revenue SHOULD check that the jobs name the payee as their provider. An operator
  can propose budgets and submit work for any job that names the payee, but cannot move the payee's balance; the owner
  can replace it at any time. `commerce` is whatever address the caller names: the payee calls only `setBudget` and
  `submit` on it, and SHOULD guard those calls against re-entry as it guards its creditor calls.
- **Tokens.** Tokens that take a fee on transfer, rebase, or block addresses change what a sweep can pay. Balances are
  measured, not assumed, so accounting stays correct, but a blocked creditor is paid nothing and what it is offered
  stays in its reserve. A token whose balances fall on their own can leave the reserves above the balance; sweeps then
  forward nothing until it covers them again.
- **Ownership changes.** A transfer of the identity transfers control of the payee with its creditors and their
  reserves, and ends the former owner's choice of beneficiary. Buyers SHOULD read `creditors()`, each creditor's
  `hasClaim` and its `reserved` amounts before buying.
- **A burned identity.** With no owner to read, no one can configure the payee. Sweeps still pay the creditors, and
  what is left stays in the payee rather than being sent to the zero address. Owners who may burn an identity SHOULD
  set a beneficiary first.
- **Holders are paid last, and only by the owner's choice.** A token receives only what every creditor leaves, and the
  owner can add creditors with shares up to `10000`, which can leave holders nothing. The owner can point the
  beneficiary elsewhere at any time, and a sale ends its choice of the token. Holders SHOULD read the payee's
  `beneficiary()`, `creditors()` and their shares, and treat the revenue as junior and revocable.
- **`RevenueFromPayee` counts any plain transfer.** A sync cannot tell a sweep from another transfer, so anyone can raise
  the figure by sending the asset to the token, at the cost of giving it to the holders. Readers that need the agent's
  revenue alone SHOULD sum the `forwarded` amounts of the payee's `Swept` events while its `beneficiary()` was the
  token.
- **Timing of syncs.** Revenue is booked to whoever holds the token at the sync. Since anyone may sweep and sync, a buyer
  can buy just before a sweep and a sync and sell after. Frequent syncs make each one smaller.
- **Assets the token does not reward.** A payee forwards every asset it is swept in. An asset the token does not reward
  is not booked and stays in the token. Token deployers SHOULD register every asset the agent is paid in.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
