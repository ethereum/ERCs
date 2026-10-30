---
title: ERC-20 Outgoing Window Limits
description: Holder-level per-transfer and aggregate fixed-window token limits with delayed cap changes and a restrictive guardian.
author: Fernando Díaz Toledano (@shargon)
status: Draft
type: Standards Track
category: ERC
created: 2026-10-30
requires: 20
---

## Abstract

This proposal defines an opt-in [ERC-20](./erc-20.md) extension combining a maximum positive outgoing amount per transfer with a maximum aggregate amount per fixed block window. All spending paths share the balance holder's counter. It standardizes policy queries, accounting, events, immediate tightening, and delayed cap replacement with an independent guardian veto. It does not require a particular implementation or depend on a delayed-unlock standard.

## Motivation

A compromised authorization or withdrawal workflow may divide a large outflow among many transactions and recipients. A per-transfer limit alone does not bound that aggregate. Custodians and individual holders need a common way to observe and enforce both limits independently of the client that submits the transfer.

The Binance incident reported on October 29, 2026 motivates controls that constrain the consequences of unauthorized withdrawals. The investigation was preliminary when this working paper was prepared; the proposal makes no claim about the precise exploit or the amount it would have saved. The engineering requirement is to bound token outflow even when a transfer satisfies normal signature and allowance checks.

## Specification

The key words MUST, MUST NOT, REQUIRED, SHOULD, SHOULD NOT, MAY, and OPTIONAL are to be interpreted as described in RFC 2119 and RFC 8174.

### Scope and interface

An implementing token MUST implement ERC-20 and the following interface. Amounts MUST be expressed in the token's smallest units, without price conversion. Every policy and counter belongs to one balance holder within one token contract and one chain.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IERC20WindowLimits {
    /// @dev Limits use raw token units. Window length, delay and guardian are immutable.
    struct LimitPolicy {
        bool enrolled;
        address guardian;
        uint256 windowBlocks;
        uint256 changeDelayBlocks;
        uint256 maxTransfer;
        uint256 maxWindow;
    }
    struct PendingLimits {
        bool exists;
        uint256 maxTransfer;
        uint256 maxWindow;
        uint256 activateBlock;
    }
    event LimitsEnrolled(address indexed account, address indexed guardian, uint256 windowBlocks, uint256 changeDelayBlocks, uint256 maxTransfer, uint256 maxWindow);
    event LimitsChanged(address indexed account, uint256 maxTransfer, uint256 maxWindow);
    event LimitsScheduled(address indexed account, uint256 maxTransfer, uint256 maxWindow, uint256 activateBlock);
    event LimitsCancelled(address indexed account, address indexed actor);
    event WindowSpent(address indexed account, uint256 indexed epoch, uint256 amount, uint256 totalSpent);
    /// @notice Enroll msg.sender once. Require maxTransfer <= maxWindow, positive
    /// windowBlocks/changeDelayBlocks and a nonzero guardian distinct from msg.sender.
    /// @dev Fixed epoch = floor(block.number / windowBlocks); NOT a sliding window.
    function enrollLimits(uint256 maxTransfer, uint256 maxWindow, uint256 windowBlocks, uint256 changeDelayBlocks, address guardian) external;
    /// @notice Holder or guardian may reduce either cap immediately (including zero).
    /// @dev Neither cap may increase. Cancels pending change, NEVER resets usage.
    function tightenLimits(address account, uint256 maxTransfer, uint256 maxWindow) external;
    /// @notice Holder schedules replacement caps after its immutable change delay.
    /// @dev Replaces pending change and restarts the full delay; usage is preserved.
    function scheduleLimits(uint256 maxTransfer, uint256 maxWindow) external;
    /// @notice Holder or guardian vetoes a pending change; no pending change is a no-op.
    function cancelLimits(address account) external;
    /// @notice Anyone may apply a matured change; no automatic activation.
    /// @dev MUST preserve usage. Reverts when absent or before activateBlock.
    function applyLimits(address account) external;
    /// @notice Current effective policy (pending changes are returned separately).
    function limitPolicy(address account) external view returns (LimitPolicy memory);
    /// @notice All-zero struct if no pending change exists.
    function pendingLimits(address account) external view returns (PendingLimits memory);
    /// @notice Current epoch usage; remaining is max(0, maxWindow - spent).
    /// @dev Unenrolled returns (0,0,type(uint256).max,0). Remaining ignores balance,
    /// per-transfer cap and independent restrictions. Expired usage reads as zero.
    function windowUsage(address account) external view returns (uint256 epoch, uint256 spent, uint256 remaining, uint256 nextResetBlock);
}
```

### Enrollment

An unenrolled holder is unrestricted by this extension. `enrollLimits(T, Q, W, D, guardian)` MUST enroll only its caller, exactly once. `T` is the maximum per transfer, `Q` the aggregate window cap, `W` the number of blocks per window, and `D` the cap-change delay in blocks. The call MUST revert unless `T <= Q`, `W > 0`, `D > 0`, and the guardian is nonzero and distinct from the holder.

Enrollment MUST immediately activate both caps and emit `LimitsEnrolled`. The initial current-window usage is zero; movements before enrollment are not retroactively counted. Zero caps are allowed and block all positive outgoing movements. Enrollment, window length, change delay, and guardian MUST NOT subsequently change or be removed, including through additional entry points. There is no privileged transfer exemption.

### Fixed-window accounting

For block `b`, the current epoch is `e = floor(b / W)`. Epoch `e` includes blocks `[e * W, (e + 1) * W - 1]`. The next reset is `(e + 1) * W`. All arithmetic MUST be checked; an unrepresentable result MUST revert.

Let `S` be the sum of previously successful positive outgoing movements in epoch `e` since enrollment. Before each outgoing movement of amount `a > 0`, an implementation MUST require both `a <= T` and `S + a <= Q`. On success it MUST increase `S` by `a` and emit `WindowSpent(account, e, a, S)`. It MUST reject excess amounts by reverting the transaction, without partial movement or deferred debt.

The counter MUST be shared across `transfer`, `transferFrom`, operators, recipients, burns, self-transfers, signature-authorized spending, and batch operations. It MUST use the debited holder (`from`), not `msg.sender` or `tx.origin`. A transaction containing several transfer operations MUST check each operation and their aggregate. The per-transfer cap applies to each individual movement, not the sum of all movements in an outer transaction; the window cap still applies to the sum.

Incoming transfers and mints MUST NOT consume or refill the recipient's quota. The sending holder's policy still applies. Self-transfers MUST consume the requested amount even though the net balance does not change. Burns MUST consume their amount. Zero transfers MUST NOT consume quota or emit `WindowSpent`, and MUST retain ERC-20 Transfer event semantics. Approval creation and revocation remain available and do not reserve quota.

Usage MUST reset logically to zero at an epoch boundary, independently of transaction activity. Lazy storage updates are permitted. No event at the boundary is required. If a transfer or any later enclosing operation reverts, counter increments, events, allowances and balances MUST all revert atomically. If external callbacks exist, usage MUST be recorded before yielding control to prevent reentrant overspending.

The standardized accounting is gross outgoing token units, not net portfolio change or fiat value. A fee charged as an additional outgoing movement MUST be included; splitting transfers across fee and recipient movements cannot evade the aggregate. Rebasing and nonstandard balance models require additional accounting analysis; a conforming implementation MUST NOT expose positive transfer/debit paths that skip the policy.

### Policy changes and authorization

Only the holder or guardian MAY call `tightenLimits(account, T2, Q2)` or `cancelLimits(account)`. Calls for an unenrolled account or from others MUST revert.

`tightenLimits` MUST require `T2 <= Q2`, `T2 <= T`, and `Q2 <= Q`. It MUST cancel any pending change, apply the caps immediately, preserve all usage, and emit `LimitsChanged`. Equal caps are permitted and still cancel a pending change. If usage already exceeds the new window cap, remaining capacity is zero; past transactions are not reversed. A guardian can freeze positive outgoing movements by tightening both caps to zero.

Only a holder MAY schedule its own replacement caps with `scheduleLimits(T2, Q2)`. It MUST be enrolled and satisfy `T2 <= Q2`. The method MUST set `activateBlock = b + D`, cancel any previous pending change, and emit `LimitsScheduled`. All replacements through this method wait the full delay, even if some caps decrease. Scheduling again MUST restart the full delay; it MUST NOT retain an earlier deadline.

`cancelLimits` MUST remove a pending change and emit `LimitsCancelled` if one exists; otherwise it MUST be a no-op. The actor is the caller. Replacement or tightening of an existing pending change MUST likewise emit `LimitsCancelled` before the corresponding schedule or change event.

`applyLimits(account)` MAY be called by anyone, but MUST revert if there is no pending change or if `b < activateBlock`. It MUST apply the pending caps, clear the pending change, preserve usage, and emit `LimitsChanged`. Application at the exact deadline is permitted. Maturity alone MUST NOT change the active caps. A guardian can still cancel a matured but unapplied change, subject to transaction ordering.

Policy operations MUST NOT reset the counter, advance its epoch artificially, shorten the window, or refund usage. Any additional administrative method MUST preserve these guarantees. Immutable guardian and timing parameters avoid a separate immediate relaxation path.

### Queries and discovery

`limitPolicy(account)` MUST return current active policy and an all-zero struct for unenrolled accounts. `pendingLimits(account)` MUST return the outstanding change or an all-zero struct if absent. An already-matured pending change remains pending until applied or cancelled.

`windowUsage(account)` MUST report the current epoch, the logical current usage, `max(0, Q - S)`, and the next reset block. For an unenrolled account it MUST return `(0, 0, type(uint256).max, 0)`. Remaining capacity is not a promise about balance, allowances, the per-transfer cap, or other restrictions. Queries do not reserve capacity.

Wallets MAY probe these methods by `eth_call`. Missing or undecodable methods indicate unsupported functionality, not unlimited policy. No ERC-165 registry is required.

## Rationale

Fixed windows provide constant-size state and an exact common interpretation of the requested counter. They are deliberately not rolling windows. A token bucket allows gradual refilling and different burst behavior; an exact sliding window requires historical accounting or a more complex bounded design. Those are different policies and should not be advertised with this interface's semantics.

The immutable window and delayed relaxation prevent the holder from changing configuration to reset a depleted counter. A restrictive guardian can stop further spending without gaining the right to transfer assets. Existing bridge volume caps and application-specific spending controls demonstrate the broader pattern; this proposal's interoperability target is a holder-level ERC-20 policy shared by all debit paths.

The delayed-unlock concept is orthogonal: one controls when outgoing movements are available, the other how much can move. A token may implement both, requiring both checks to succeed, without either standard depending on the other.

## Backwards Compatibility

The ERC-20 ABI is preserved, but opted-in holders may experience new reverts despite sufficient balance and allowance. Integrators must tolerate changing available quota. Transfer batching, exchange withdrawals, liquidation, and routers may require adaptation. A positive `remaining` query is not equivalent to an immediately transferable balance.

This does not modify existing immutable tokens or automatically constrain native ETH, other chains, other accounts, NFTs, or multi-token contracts. A custodial vault could provide analogous protection for existing ERC-20 balances, but its interface, approval paths, and escape routes require a separate specification. Multi-asset limits cannot simply add raw units from unrelated tokens.

## Test Cases

| Setup and operation | Required result |
| --- | --- |
| `T = 60`, `Q = 100`; transfer 61 | Revert |
| Transfer 60 then 40 in one epoch | Both pass; spent 100 |
| Transfer another 1 in that epoch | Revert |
| Different spenders transfer 60 then 40 from same holder | Shared spent 100 |
| Transfer to self 20, burn 30 | Spent increases by 50 |
| Receive 50 after spending 100 | Spent remains 100 |
| `W = 10`; spend 100 at block 109 then 100 at 110 | Permitted across different epochs |
| Window expires without any calls | Query reports spent 0 |
| Spent 60, tighten Q to 40 | Spent remains 60; remaining 0 |
| Schedule Q = 200 then tighten | Pending change cancelled |
| Schedule in block 100 with D = 5 | Cannot apply at 104; can at 105 |
| Apply cap change after spending 60 in same epoch | Spent remains 60 |
| Insufficient balance or enclosing batch reverts | No usage or allowance consumed |
| Zero transfer with zero caps | Policy permits, no usage increment |

## Security Considerations

Fixed windows permit a boundary burst: up to `Q` immediately before a boundary and another `Q` immediately after it, using multiple transfers if necessary. This is not a guarantee of at most `Q` in every rolling interval of `W` blocks. In one continuously protected account with unchanged caps, an interval intersecting `n` epochs admits at most `n * Q` gross units. This bound is per token and account, not per exchange or chain portfolio.

A compromised holder can keep spending available quota and request larger caps. Delayed changes require monitoring, independently secured guardian access, and timely inclusion of cancellation or tightening. A matured change may be applied in the same transaction as a transfer. There is no guaranteed transaction-order priority for the defender. Congestion, censorship, reorganizations, and chain-specific block numbers affect operational response.

A compromised guardian can cause indefinite denial of service through repeated tightening or cancellation. The guardian cannot recover a lost holder key. Immutable enrollment parameters make mistakes costly; wallet interfaces MUST explain their persistence. A smart-contract guardian's own governance and upgrades remain an external trust boundary.

Token upgrades, unauthorized debit paths, or unprotected balances elsewhere defeat the intended protection. Deposit refunds cannot restore spent quota. Once tokens have left the protected account, this policy cannot prevent recipients from moving them or recover the transfer. A stolen authorization remains dangerous across successive windows until signer or allowance control is restored.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).

