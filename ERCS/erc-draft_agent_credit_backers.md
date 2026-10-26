---
eip: 99907
title: Agent Credit Backers
description: Third parties that stand behind a lender's credit line to an agent identity and absorb its defaults
author: Priors contributors (@priors-agents)
discussions-to: https://ethereum-magicians.org/t/erc-tba-agent-credit-backers/30062
status: Draft
type: Standards Track
category: ERC
created: 2026-10-20
requires: 20, 165, 712, 721, 1271
---

## Abstract

This proposal lets a third party, a backer, stand behind a lender's credit line to an identity of an
[ERC-721](./eip-721.md) identity registry, such as the Identity Registry of [ERC-8004](./eip-8004.md), and absorb the
line's losses. It extends the Agent Credit Lines draft, in which a lender lends an [ERC-20](./eip-20.md) token to such
identities. With the identity owner's signed consent, a backer puts itself behind a line of a given size. The lender
then asks the backer before each draw (`canBorrow`), tells it of each draw (`onBorrow`), takes the principal of each
defaulted loan from the backer's balance and tells it (`onDefault`), and tells it when part of the line is no longer
its concern (`onRelease`). A backer can refuse a draw. It cannot stop a repayment, a default or the end of its backing.
After a default, the backer, or anyone for it, can pay in a part of its charge it left unpaid (`payLoss`), and money
paid toward the defaulted loan (`recover`) goes first to that part, then back to the backer, credited to it until anyone
pays it out (`payBacker`), then to the lender's fee.

## Motivation

A line of credit to an agent is a bet on whoever stands behind the agent. Lenders to agent identities already let third
parties take that place: stakers who put stake behind a line, vaults that hold collateral for it, a lender's own
treasury that backs first lines. Each does it through a hook written for one lender. A staker or an insurer that backs
an agent at one lender cannot back the same agent at another, and a lender cannot accept a backer written for someone
else's contract.

What a lender and a backer tell each other is short and the same everywhere: may this draw go ahead, a draw happened,
a loan defaulted and this is your loss, this part of the line is no longer yours. Fixing those four calls, how the loss
is taken, and how the identity's owner consents, lets one backer stand behind agents at any conforming lender, and lets
anyone see on chain who carries the risk of a line.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT
RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interfaces

A lender MUST implement `IBackedCreditLine` and `IAgentCreditLine`, and MUST implement [ERC-165](./eip-165.md),
returning `true` for the interface identifiers of `IBackedCreditLine` and `IAgentCreditLine` and for `0x01ffc9a7`. A
backer MUST implement `ICreditBacker` and ERC-165, returning `true` for the interface identifier of `ICreditBacker` and
for `0x01ffc9a7`.

`IAgentCreditLine` is the interface of the Agent Credit Lines draft, restated here unchanged:

```solidity
interface IAgentCreditLine {
    enum LoanStatus { None, Active, Repaid, Defaulted }

    struct LoanInfo {
        uint256 agentId;
        address owner;
        uint256 principal;
        uint256 fee;
        uint64 issuedAt;
        uint64 dueAt;
        uint64 defaultableAt;
        LoanStatus status;
    }

    event Borrowed(uint256 indexed loanId, uint256 indexed agentId, address indexed to, uint256 principal, uint256 fee, uint64 dueAt);
    event Repaid(uint256 indexed loanId, uint256 indexed agentId, address indexed payer, uint256 principal, uint256 fee);
    event Defaulted(uint256 indexed loanId, uint256 indexed agentId, address indexed owner, uint256 principal);

    function identityRegistry() external view returns (address);
    function asset() external view returns (address);
    function isController(uint256 agentId, address account) external view returns (bool);
    function availableCredit(uint256 agentId) external view returns (uint256);
    function quote(uint256 agentId, uint256 amount, uint64 term) external view returns (uint256 fee);
    function borrow(uint256 agentId, uint256 amount, uint64 term, address to, uint256 maxFee) external returns (uint256 loanId);
    function amountDue(uint256 loanId) external view returns (uint256);
    function repay(uint256 loanId, uint256 maxDue) external returns (uint256 paid);
    function markDefault(uint256 loanId) external;
    function loanInfo(uint256 loanId) external view returns (LoanInfo memory);
}
```

This proposal adds:

```solidity
interface ICreditBacker {
    function canBorrow(address lender, uint256 agentId, uint256 amount, uint64 term, uint256 fee, address caller, address owner, address to) external view returns (bool);
    function onBorrow(address lender, uint256 agentId, uint256 loanId) external;
    function onDefault(address lender, uint256 agentId, uint256 loanId, uint256 principal, uint256 paid) external;
    function onRelease(address lender, uint256 agentId, uint256 amount, uint8 reason) external;
}

interface IBackedCreditLine is IAgentCreditLine {
    event BackerSet(uint256 indexed agentId, address indexed backer, uint256 line);
    event BackerCharged(uint256 indexed loanId, uint256 indexed agentId, address indexed backer, uint256 principal, uint256 paid);
    event BackerHookFailed(uint256 indexed agentId, address indexed backer, bytes4 selector);
    event LossPaid(uint256 indexed loanId, address indexed backer, address indexed payer, uint256 amount);
    event Recovered(uint256 indexed loanId, address indexed backer, address indexed payer, uint256 amount, uint256 toBacker);
    event BackerPaid(address indexed backer, uint256 amount);
    event ConsentsRevoked(uint256 indexed agentId, address indexed owner, uint256 nonce);

    function backerOf(uint256 agentId) external view returns (address);
    function backedLine(uint256 agentId) external view returns (uint256 line, uint256 outstanding);
    function backerOfLoan(uint256 loanId) external view returns (address);
    function consentNonce(uint256 agentId) external view returns (uint256);
    function lossInfo(uint256 loanId) external view returns (uint256 paid, uint256 unpaid, uint256 recovered, uint256 returned);
    function dueToBacker(address backer) external view returns (uint256);
    function payLoss(uint256 loanId, uint256 amount) external returns (uint256 taken);
    function recover(uint256 loanId, uint256 amount) external returns (uint256 taken);
    function payBacker(address backer) external returns (uint256 amount);
    function setBacker(uint256 agentId, address backer, uint256 line, uint256 deadline, bytes calldata ownerConsent) external;
    function removeBacker(uint256 agentId) external;
    function revokeConsents(uint256 agentId) external;
}
```

### What the Agent Credit Lines draft provides

This proposal relies on these parts of the Agent Credit Lines draft. `identityRegistry()` is the ERC-721 contract
whose token identifiers are the `agentId` values, and `asset()` is the ERC-20 token lent and repaid; neither changes,
and every amount is in the token's base units. `borrow` can only be called by a controller of the identity (its owner,
or a delegate the lender accepts); it records a loan whose `loanId` is never zero and never reused, whose `owner` is the
identity's owner at the draw and whose `fee` is what `quote` returns, and sends `amount` to `to`. `availableCredit` is
the largest amount `borrow` would lend now. Anyone can `repay` a loan in full, and anyone can `markDefault` a loan once
the block timestamp reaches its `defaultableAt`. A loan's status is `Active` until it is repaid or defaulted.

### Terms

- The **owner** of an identity is the identity registry's `ownerOf(agentId)` at the time of the call.
- A **backing** is a backer standing behind one identity's line at one lender. It begins when `setBacker` names a
  backer for an identity that has none or another, and ends when `removeBacker` is called or `setBacker` names another
  backer. An identity has at most one backer at a lender at a time.
- The backing's **line** is the most principal the identity can have outstanding under it. Its **outstanding**
  principal is the sum of the principals of the `Active` loans drawn under it. `backedLine(agentId)` returns both, and
  zeros when the identity has no backer.
- A loan is **drawn under** the backer that `backerOf(agentId)` returned when it was drawn.

### Owner consent

`ownerConsent` is a signature by the owner of this [EIP-712](./eip-712.md) typed structure:

```text
BackerConsent(address lender,uint256 agentId,address backer,uint256 line,uint256 nonce,uint256 deadline)
```

where `lender` is the lender's address, `nonce` is `consentNonce(agentId)`, and the other fields are the arguments of
`setBacker`. The domain has the fields `name`, `version`, `chainId` and `verifyingContract`, set to "Agent Credit
Backers", "1", the chain's identifier and the lender's address.

A consent is valid when it is 65 bytes holding `r`, `s` and `v` in that order, with `v` equal to 27 or 28 and `s` at
most half the secp256k1 order, from which `ecrecover` returns the owner; or when the owner is a contract whose
[ERC-1271](./eip-1271.md) `isValidSignature` returns `0x1626ba7e` for the typed data hash and `ownerConsent`.

### Setting a backer

`setBacker(agentId, backer, line, deadline, ownerConsent)`:

- MUST revert unless `msg.sender` is `backer`.
- MUST revert unless `backer` reports through ERC-165 that it implements `ICreditBacker`.
- MUST revert if `line` is zero, if the block timestamp is greater than `deadline`, or unless `ownerConsent` is a valid
  consent for these arguments and the current nonce. On success it MUST increase `consentNonce(agentId)` by one, so
  that a consent can be used once.
- When `backer` is not the identity's backer, MUST revert while the outstanding principal is not zero. Otherwise the
  current backing, if there is one, ends, and a backing by `backer` with a line of `line` begins.
- When `backer` is already the identity's backer, MUST revert if `line` is less than the outstanding principal.
  Otherwise the line becomes `line`.
- MUST emit `BackerSet(agentId, backer, line)`, and then MUST call `onRelease` as set out under Releases.
- MAY revert for lender-specific reasons, such as a backer the lender does not accept or a line above its limits.

### Removing a backer

`removeBacker(agentId)`:

- MUST revert if the identity has no backer, if `msg.sender` is neither its backer nor its owner, or if the outstanding
  principal is not zero.
- MUST increase `consentNonce(agentId)` by one, so that no consent signed before the removal can be used after it.
- MUST end the backing, so that `backerOf(agentId)` returns the zero address, MUST emit
  `BackerSet(agentId, address(0), 0)`, and then MUST call `onRelease` as set out under Releases.

### Revoking consents

`revokeConsents(agentId)`:

- MUST revert unless `msg.sender` is the identity's owner.
- MUST increase `consentNonce(agentId)` by one, and emit `ConsentsRevoked(agentId, owner, nonce)` with `nonce` the new
  `consentNonce(agentId)`.
- MUST NOT change the backing, if there is one, or call the backer.

### Drawing

When the identity has a backer, `borrow(agentId, amount, term, to, maxFee)`:

- MUST revert if `amount` is greater than the line less the outstanding principal. `availableCredit(agentId)` MUST NOT
  return more than that difference.
- MUST call `canBorrow(lender, agentId, amount, term, fee, caller, owner, to)` on the backer before it sends any of the
  asset, with `lender` its own address, `fee` the fee the loan would record, `caller` the `msg.sender` of `borrow` and
  `owner` the identity's owner, and MUST revert unless the call returns `true`. A call that reverts, or returns anything
  but `true`, is a refusal.
- MUST record the loan as drawn under the backer and add its principal to the outstanding principal.
- After it has recorded the loan and sent the asset, MUST call `onBorrow(lender, agentId, loanId)` on the backer, and
  MUST revert if that call reverts.

`backerOfLoan(loanId)` MUST return the backer the loan was drawn under, and the zero address for a loan drawn under no
backer and for a `loanId` never issued.

`availableCredit` does not ask the backer. A client that wants to know whether a draw would go through calls the
backer's `canBorrow` with the same arguments. This proposal does not say whether a lender lends to an identity that has
no backer; a loan drawn without one has no backer, and the rest of this proposal does not apply to it.

### Repaying

`repay` MUST NOT call the backer. When the loan was drawn under a backer, `repay` MUST subtract its principal from the
outstanding principal.

### Defaults

When `markDefault(loanId)` marks a loan drawn under a backer defaulted, the lender:

1. MUST charge the backer the loan's principal, subtracting it from both the line and the outstanding principal. The
   fee is not part of the charge.
2. MUST then take from the backer, with the asset's `transferFrom(backer, lender, amount)`, an `amount` equal to the
   least of the principal, the backer's `balanceOf` and its `allowance` to the lender. A read that reverts, or does not
   return exactly 32 bytes, counts as zero. `paid` is `amount` when the transfer does not revert and returns either no
   data or exactly 32 bytes holding `true`, and zero otherwise, including when `amount` is zero.
3. MUST make each of these three calls to the asset with a gas limit it fixes, and MUST revert, rather than make one
   with less, when it cannot give the call that limit. It MUST NOT copy more than the first 32 bytes of what a call
   returns, and MUST NOT revert because of anything the asset does in these calls.
4. MUST emit `BackerCharged(loanId, agentId, backer, principal, paid)`.
5. MUST then call `onDefault(lender, agentId, loanId, principal, paid)` on the backer, as a notification.

The backer, or anyone for it, can pay in later, through `payLoss`, a part of the principal the backer did not pay. What
else the lender does about that part, such as lending no more under that backer until it is paid, is outside this
proposal.

### After a default

For each loan drawn under a backer and marked defaulted, the lender keeps four amounts, and `lossInfo(loanId)` MUST
return them: `paid`, what the backer has paid of its charge; `unpaid`, the part of the charge still unpaid; `recovered`,
all that `recover` has taken for the loan; and `returned`, the part of `recovered` credited to the backer. The default
sets `paid` to the `paid` of `BackerCharged` and `unpaid` to the principal less `paid`. For any other `loanId`,
`lossInfo` MUST return zeros.

`payLoss(loanId, amount)` pays a part of the charge the backer left unpaid. It:

- MUST revert unless the loan was drawn under a backer and is `Defaulted`, or if `taken`, the least of `amount` and
  `unpaid`, is zero.
- MUST take `taken` from `msg.sender` with the asset's `transferFrom`, add it to `paid`, subtract it from `unpaid`, emit
  `LossPaid(loanId, backer, msg.sender, taken)`, and return `taken`. What it takes counts as paid by the backer, whoever
  sends it.

`recover(loanId, amount)` pays toward the loan after its default. It:

- MUST revert unless the loan was drawn under a backer and is `Defaulted`, or if `taken`, the least of `amount` and the
  loan's principal and fee less `recovered`, is zero.
- MUST take `taken` from `msg.sender` with the asset's `transferFrom` and apply it in this order: to `unpaid`, which it
  lowers, the lender keeping that part; then to the backer, up to `paid` less `returned`, which it MUST add to
  `returned` and to `dueToBacker(backer)`, and MUST NOT transfer to the backer; then to the fee, the lender keeping that
  part.
- MUST add `taken` to `recovered`, emit `Recovered(loanId, backer, msg.sender, taken, toBacker)`, with `toBacker` the
  part credited to the backer, and return `taken`.

`dueToBacker(backer)` MUST return what recoveries have credited to `backer` and `payBacker` has not yet paid it. The
lender MUST keep that amount for the backer: it MUST NOT lend it, and `availableCredit` MUST NOT count it.

`payBacker(backer)` pays a backer what recoveries credited to it. Anyone may call it. It:

- MUST revert if `dueToBacker(backer)` is zero.
- MUST set `dueToBacker(backer)` to zero, transfer that amount to `backer`, and to no other address, with the asset's
  `transfer`, emit `BackerPaid(backer, amount)`, and return the amount.

None of `payLoss`, `recover` and `payBacker` calls the backer. `amountDue` and `repay` stay as the Agent Credit Lines
draft defines them: a defaulted loan is not repaid, and its status stays `Defaulted`.

### Releases

`onRelease(lender, agentId, amount, reason)` tells a backer that `amount` of the line it stood behind for the identity
is no longer backed by it. The lender MUST call it, as a notification, in exactly these cases, with these values, and
MUST NOT use any other value of `reason`:

| `reason` | Name | When | `amount` |
|---|---|---|---|
| `1` | Lowered | `setBacker` by the identity's backer set a lower line | The old line less the new one |
| `2` | Removed | `removeBacker` ended the backing | The whole line |
| `3` | Replaced | `setBacker` named another backer | The whole line of the backer replaced |

A line grows only through `setBacker`, which the backer calls itself. Every decrease of a line MUST be told to its
backer exactly once: through `onDefault` for the principal of a defaulted loan, or through `onRelease` for `amount`.
Over a backing, the principals passed to `onDefault`, the amounts passed to `onRelease` and the line left therefore add
up to the line the backer was first given plus every raise, so a backer can keep its own account of what it stands
behind.

### Notifications

`onDefault` and `onRelease` are notifications. For each, the lender:

- MUST call the backer with a gas limit it fixes, of at least 100,000, and MUST revert, rather than make the call with
  less, when it cannot give the call that limit.
- MUST NOT revert because of the call, whatever the backer does in it: revert, use all its gas, or return data of any
  size. When the call fails, the lender MUST emit `BackerHookFailed(agentId, backer, selector)`, with the selector of
  the function called, and MUST complete the action.

`canBorrow` and `onBorrow` are not notifications: a backer refuses a draw by refusing either.

### The backer

- `canBorrow` MUST NOT depend on `msg.sender`, so that anyone can ask a backer whether it would allow a draw at a
  given lender.
- `onBorrow`, `onDefault` and `onRelease` MUST revert unless `msg.sender` is `lender`.
- A backer SHOULD keep a balance of the asset, and an allowance to each lender, at least equal to the lines it stands
  behind there.

## Rationale

- **Hooks, not deposits.** A backer could deposit its stake with each lender, but it could then back only as many
  lenders as it splits its stake between, and every lender would hold capital it does not lend. With hooks, the backer
  keeps its stake and stands behind lines at any number of lenders, and a lender reaches the stake only when a loan the
  backer agreed to defaults.
- **The loss is taken before the backer is told.** The lender takes the principal from the backer's balance, up to its
  allowance, and only then calls `onDefault`. A default is paid without calling the backer (unless the token itself
  calls it, as the next point covers), and the backer cannot act on a default before paying for it. It also keeps a
  conversion of collateral out of a transaction someone else times: anyone may call `markDefault` once `defaultableAt`
  has passed, so a swap made inside the hook would run where its caller can build a sandwich around it. A backer whose
  collateral is another asset keeps enough of the lent asset at hand, has a contract that holds it give the allowance,
  or reads `dueAt` from `loanInfo` and converts during the grace period, in its own transaction.
- **Calls to the asset are bounded too.** With a token that calls the holder during a transfer, as
  [ERC-777](./eip-777.md) tokens call `tokensToSend`, the backer's own code runs inside the lender's `transferFrom`.
  If that call could use all the gas left, or return data the lender had to copy, a backer could make every default
  of its loans revert. A fixed gas limit and reading one word back keep the default going whatever the asset does. The
  rule against calling with less stops a caller from making the transfer fail on purpose, so that the backer pays
  nothing while the default goes through. Tokens that return no data from `transferFrom` are accepted, as they are by
  most lenders today.
- **The principal, not the fee.** The principal is what left the lender; the fee is income it expected. A lender that
  wants its fees covered too can price that into the line.
- **After a default: the unpaid part, then the backer, then the fee.** A loan opens once and closes once in the Agent
  Credit Lines draft, so money that arrives after a default goes through `recover`, not `repay`, and the loan stays
  `Defaulted`. The backer owed the whole principal, so a recovery first pays what it left unpaid, which also settles that
  part of its charge. The backer then gets back what it paid, since it bore that loss, and the fee comes last, since the
  backer never covered it. `payLoss` is the backer's side: what it pays late counts as paid at the default, so a later
  recovery returns it, and a backer that converts its collateral slowly can still settle its charge. `lossInfo` keeps
  all of it per loan, where a contract can read it; a contract cannot read `BackerCharged`. `recover` credits the
  backer's part instead of transferring it, and `payBacker` pays it out: a backer's address the asset will not pay, one
  on the token's freeze list or one whose transfer hook reverts, then holds up only its own payment, never a recovery or
  the fee behind its part. It is the next point's rule applied after a default.
- **A backer can stop money leaving, never money coming back.** `canBorrow` and `onBorrow` can refuse a draw: the
  backer carries the risk, and it has to know of every loan it carries. `repay` does not call the backer, and a
  default, a removal or a replacement goes ahead whatever the backer does. A repayment a backer could block would turn
  a repaid loan into a default; a default it could block would stop the lender from recovering; a removal it could
  block would hold the identity to a backer its owner no longer wants. [ERC-8183](./eip-8183.md) makes the same choice
  for its refund, which no hook can block.
- **A fixed gas limit for notifications.** Without a limit, a backer could use all the gas of a `markDefault` call.
  Without the rule against calling with less, a caller could send just enough gas for the notification to fail while
  the default goes through, and the backer would never hear of it. With both, a backer always gets its limit, and a
  notification that fails is the backer's own doing and is logged.
- **Both parties consent, and the lender may refuse.** The owner's signature stops anyone from putting a backer behind
  an identity: a backer decides which draws go through and may hold the owner to terms of its own. The backer submits
  the call itself, so no one can put a backer behind a line it did not choose. The signature names the lender, the
  identity, the backer and the line, and carries a nonce and a deadline, so it serves one backing at one lender, once.
  A removal moves the nonce too, so a consent signed before it, such as a raise not yet used, cannot bring the backer
  back, and `revokeConsents` lets an owner whose key cannot take back a signature void the consents it has not seen
  used, also while the identity has no backer.
- **A line, not a loan.** The backer stands behind a revolving line, so it is not called on repayment, and what it can
  lose is bounded by the line. Every decrease of the line is told to it exactly once, so it can keep its account from
  the calls it receives. A raise needs a new consent, which the backer submits itself.
- **One backer per identity, changed only when nothing is drawn.** The loss of a loan belongs to the backer that agreed
  to it. Changing backers only when nothing is outstanding keeps that rule without moving risk from one backer to
  another; `backerOfLoan` keeps the record per loan for readers.
- **The lender's address in every call.** One backer can serve many lenders, and tells them apart by `lender`, which it
  checks against `msg.sender`. In `canBorrow`, a view, it lets anyone ask a backer about a draw at a given lender before
  signing it.
- **Related work.** [ERC-7246](./eip-7246.md) pledges a token balance to a counterparty without saying when it is
  taken; here the backer's allowance is taken only for the principal of a defaulted loan it agreed to.
  [ERC-8320](./eip-8320.md) registries hold signed claims about assets, and its example schema for `BACKING` claims
  about credit-backed instruments has a `GUARANTEE` backing type. Such a claim can state that a backer guarantees an
  agent's loans; it does not make the backer pay. The hooks here are what make that guarantee hold: the backer agrees
  to each draw and the lender takes the principal of each default, so a claim and a backing can describe the same
  commitment, one as an attestation and one as its enforcement.

## Backwards Compatibility

No backward compatibility issues found. A lender of the Agent Credit Lines draft that does not implement this proposal
stays conforming to that draft. A backer hook keyed by a lender's internal identifier rather than by the lender's
address can be adapted by a contract that implements `ICreditBacker` and forwards to it.

## Test Cases

A conforming lender and backer pass these cases, each for an identity whose owner signs consents, a lender that charges
1% per 30 days with a grace period of 3 days, and a backer that holds 100 units and approved the lender for 50 units:

- The owner's consent lets the backer set a line of 50 units: `backerOf` returns the backer, `backedLine` returns 50
  units with nothing outstanding, `consentNonce` goes from 0 to 1, and `BackerSet` is emitted.
- `setBacker` reverts for a consent signed by another key; for a consent naming another line, backer, lender or
  deadline; for a consent signed for the same lender address on another chain, where a consent signed for that chain is
  accepted; for a consent already used; one second after the deadline (and succeeds at it); for the high-`s` twin of a
  valid signature; when called by anyone but the backer, the owner included; for a backer that does not report
  `ICreditBacker`, or an account with no code; and for a line of zero.
- An owner that is a contract consents through ERC-1271, and a signature its key did not make is refused.
- A draw of 10 units for 7 days by a delegate calls `canBorrow(lender, agentId, 10 units, 7 days, 23,334 base units,
  delegate, owner, to)` and then `onBorrow(lender, agentId, 1)`. A draw the backer refuses, or whose `canBorrow` or
  `onBorrow` reverts, reverts and sends nothing.
- With 30 units drawn on a line of 50, `availableCredit` is 20 units although the lender holds 970, and a draw of 20
  units and one base unit reverts.
- A repayment succeeds while every call to the backer would revert, and makes no call to it.
- The default of a 10-unit loan takes 10 units, not the fee, from the backer, lowers the line to 40 units, emits
  `BackerCharged(loanId, agentId, backer, 10 units, 10 units)` and calls
  `onDefault(lender, agentId, loanId, 10 units, 10 units)`.
- A backer holding 4 units pays 4 of a 10-unit default; with an allowance of 3 units it pays 3; with no allowance, or
  when the token refuses the transfer, it pays nothing, and each loan is still marked defaulted.
- When a backer holding 4 units pays 4 of a 10-unit default and its `onDefault` reverts, the line still goes down to 40
  units, `BackerHookFailed` is emitted, and `lossInfo` returns 4 units paid, 6 unpaid, nothing recovered and nothing
  returned. `lossInfo` returns zeros for an active loan, a repaid one and a `loanId` never issued.
- After a default that left 6 units unpaid, `payLoss` of 100 units takes 6, emits `LossPaid` and leaves 10 paid and
  nothing unpaid, and a second `payLoss` reverts. `payLoss` and `recover` revert for an active loan, a repaid one and a
  `loanId` never issued.
- After a default where the backer paid 4 of 10 units, recoveries of 5, 3 and 100 units take 5 units (to the unpaid
  part), 3 (1 to the unpaid part, 2 to the backer) and 2 units and 23,334 base units (2 to the backer, then the fee).
  The backer has 4 units due, which `payBacker` pays it, the lender keeps 6 units and the fee, and another `recover`
  reverts. A backer that paid all 10 units at the default gets the first 10 recovered; one that paid 4 and then 6
  through `payLoss` gets back 10 from a recovery of the whole amount due. None of `payLoss`, `recover` and `payBacker`
  makes any call to the backer.
- When the token freezes the backer's address after it paid all 10 units at the default, a recovery of the whole
  amount due takes 10 units and 23,334 base units, credits 10 units to the backer and reaches the fee. `payBacker`
  reverts while the address is frozen; once it is not, `payBacker` called by anyone pays the backer its 10 units and
  emits `BackerPaid`, and a second `payBacker` reverts. With 15 units of cash, 10 of them due to the backer,
  `availableCredit` is 5 units and a draw of 5 units and one base unit reverts.
- After any sequence of `payLoss` and `recover` calls, the backer never has back more than it paid, nothing is taken
  beyond the principal and the fee, and the fee is reached only once nothing is unpaid and the backer has all it paid
  back.
- When the token's `transferFrom` returns `false`, uses all its gas, or reverts or returns with as much data as its gas
  can pay for, or its `balanceOf` uses all its gas, a default sent with 1,000,000 gas still completes, with `paid`
  zero, the whole principal unpaid and the backer told. Such data costs the default less than one and a half times the
  asset's gas limit more than a transfer that just returns `false`.
- A backer whose `onDefault` or `onRelease` reverts, uses all its gas, or returns about 160 KB, cannot stop a default,
  a removal by the owner or a replacement; the lender emits `BackerHookFailed`, and the 160 KB costs the lender no more
  than the backer's own gas limit.
- A `markDefault` sent with any amount of gas, from too little upwards in steps of 1,000, either reverts and changes
  nothing or charges the backer in full and tells it: some amounts are refused because a call to the asset could not
  be given its gas limit, others because the backer's call could not. A `removeBacker` without gas for the backer's
  100,000 reverts and changes nothing. With plenty of gas, the backer is given 100,000 gas and no more.
- Lowering a line from 50 to 30 units calls `onRelease(lender, agentId, 20 units, 1)`, and a raise calls nothing.
  `removeBacker` by the backer or the owner calls `onRelease(lender, agentId, 50 units, 2)`. Another backer's
  `setBacker` calls `onRelease(lender, agentId, 50 units, 3)` on the one it replaces. Replacing or removing a backer,
  or lowering its line below what is drawn, reverts while a loan is active.
- After `removeBacker`, by the owner or by the backer, a consent signed before it for a raise of the line to 80 units
  reverts, and `consentNonce` has moved by one. `revokeConsents` by the owner moves the nonce by one, emits
  `ConsentsRevoked`, and voids a consent signed while the identity had no backer; called by anyone else, the backer and
  a delegate included, it reverts.
- After any sequence of line changes, draws, repayments, defaults and removals, the principals charged, the amounts
  released and the line left add up to every line and raise the backer was given, and every `reason` is 1, 2 or 3.
- The reference backer gives the same `canBorrow` answer to every caller, and reverts `onBorrow`, `onDefault` and
  `onRelease` called by anyone but the lender.
- In the reference lender, a backer whose `onBorrow` calls back into `borrow`, `repay`, `markDefault`, `setBacker` or
  `removeBacker` gets the lender's re-entry error and the draw reverts. Called back from `onDefault` or `onRelease`,
  the lender refuses the same way, and the default or the removal completes.

## Reference Implementation

Two contracts accompany this proposal with their tests. `BackedCreditLine` is a lender derived from the reference
lender of the Agent Credit Lines draft: it lends only behind a backer, gives each notification and each call to the
asset during a default 100,000 gas, refuses re-entry from any hook, and gives no new credit under a backer while part
of a loss it was charged is unpaid. `StakeBacker` is a backer that pays a defaulted principal
from its stake: its manager can withdraw only stake that no line holds, it approves each lender for exactly its lines
there, it refuses draws once the identity has changed hands or defaulted, and anyone can bring its records back in line
with a lender's after a notification that failed.

## Security Considerations

- **A backer's cover is its balance and its allowance.** The lender takes a loss from what the backer holds when the
  loan defaults, and a backer can move its funds or lower its allowance before then. Lenders should read the backer's
  balance and allowance before each draw, prefer backers whose stake cannot leave while their lines are open, and stop
  lending under a backer until it pays a loss it left unpaid.
- **A lender is trusted with the allowance.** A lender can take up to the allowance at any time, and holds what
  recoveries credit to a backer until `payBacker` pays it. Backers should approve only lenders they have reviewed, and
  only for the lines they stand behind there.
- **Consents.** A consent lets the backer it names act until its deadline. Owners should sign short deadlines. Using a
  consent moves the identity's nonce at that lender, which voids every other consent signed with the same nonce, and so
  do `removeBacker` and the owner's `revokeConsents`. An owner that no longer wants a consent it signed to be used
  should call `revokeConsents` rather than wait for the deadline. A consent stops working when its signer no longer
  owns the identity, and works again if the identity returns to it before the deadline.
- **Changes of owner.** A backing does not end when the identity changes hands. A backer that backs an owner rather
  than an identity should refuse draws whose `owner` is not the one that consented, and a buyer should read `backerOf`
  before buying.
- **Re-entry.** Every hook is a call into a contract the lender did not write. Lenders should make the calls after
  their own state changes and guard `borrow`, `repay`, `markDefault`, `setBacker` and `removeBacker` against re-entry.
- **Missed notifications.** A notification that fails is logged, not retried. A backer should be able to rebuild its
  records from `backerOf`, `backedLine`, `loanInfo` and `lossInfo`, which gives, for each defaulted loan, what the
  backer paid and what came back to it.
- **Which call pays what.** What `payLoss` takes counts as the backer's, and a later recovery returns it to the backer.
  A borrower or a collector paying toward a defaulted loan uses `recover`. A recovery credits the backer's part at the
  lender, and `payBacker` pays it, so a token that refuses transfers to the backer's address, as one with a freeze list
  does, stops only `payBacker`, and the backer's part waits at the lender until the backer can receive it.
  `payBacker` pays the backer's own address and no other, so a lender is never the way around a freeze.
- **Self-backing.** An owner can back its own identity through a contract of its own. A backer is worth what it holds
  and what it has approved; its existence tells a lender nothing by itself.
- **Tokens.** A token that takes a fee on transfer makes `paid` overstate what reached the lender. A token that calls
  the holder during a transfer lets the backer decide whether it pays, as a backer that lowers its allowance does.
  Lenders should lend tokens without transfer fees or holder hooks.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
