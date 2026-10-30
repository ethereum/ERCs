---
title: ERC-20 Delayed Unlock
description: Holder-controlled outgoing transfer locks with a block-based unlock delay and an independent locking guardian.
author: Fernando Díaz Toledano (@shargon)
status: Draft
type: Standards Track
category: ERC
created: 2026-10-30
requires: 20
---

## Abstract

This proposal defines an opt-in [ERC-20](./erc-20.md) extension for locking a holder's outgoing token movements. A holder requests an unlock on-chain and waits a configured number of blocks before transfers become possible. The holder or a separately designated guardian can cancel the unlock by locking again. A common interface, events, and deterministic state transitions allow wallets and incident-response services to observe and enforce this policy without requiring a particular implementation.

## Motivation

Offline key storage does not establish whether a signed transaction expresses the holder's actual intent. A compromised signing interface, approval workflow, or withdrawal service may produce valid authorizations for unwanted movements. Custodians need an enforceable response interval between an unlock request and the ability to move protected funds.

The Binance incident reported on October 29, 2026 provides contemporary context for separating authorization from permission to move funds immediately. Its technical investigation was still preliminary when this working paper was prepared. This proposal does not claim that a particular attack path is established or that this mechanism would have prevented that incident.

The interoperability problem is a lack of shared semantics for discovering a holder's lock state, observing an unlock deadline, and cancelling that deadline. Storage layout, custody procedures, and signer hardware need not be standardized.

## Specification

The key words MUST, MUST NOT, REQUIRED, SHOULD, SHOULD NOT, MAY, and OPTIONAL are to be interpreted as described in RFC 2119 and RFC 8174.

### Scope and interface

An implementing token MUST implement ERC-20 and the following additional interface. The interface is the public contract; inheritance from any particular library is not required. Here, `account` means the token balance holder. Calls by a smart account are authorized as that smart account, not as its underlying signer. There is no administrator exemption.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IERC20DelayedUnlock {
    /// @dev For an enrolled account: Locked = locked; Cooling = !locked &&
    /// block.number < unlockBlock; Unlocked = !locked && block.number >= unlockBlock.
    /// Unenrolled accounts return the all-zero struct and are unrestricted.
    struct LockPolicy {
        bool enrolled;
        bool locked;
        uint256 cooldownBlocks;
        uint256 unlockBlock;
        address guardian;
    }
    event LockEnrolled(address indexed account, address indexed guardian, uint256 cooldownBlocks);
    event AccountLocked(address indexed account, address indexed actor);
    event UnlockRequested(address indexed account, uint256 unlockBlock);
    /// @notice Enroll msg.sender once, immediately locking positive outgoing amounts.
    /// @param cooldownBlocks Nonzero delay, measured in this chain's block.number.
    /// @param guardian Nonzero address distinct from msg.sender; can lock, never unlock.
    /// @dev Enrollment, guardian and cooldown are permanent in this minimal interface.
    function enrollLock(uint256 cooldownBlocks, address guardian) external;
    /// @notice Immediately lock account and cancel any pending unlock.
    /// @dev Only account or its guardian; also allowed when already locked.
    function lock(address account) external;
    /// @notice Start msg.sender's cooldown; does not transfer any tokens.
    /// @dev Only from Locked. Earliest outgoing transfer is at request block + cooldown.
    function requestUnlock() external;
    /// @notice Read configuration and stored state; maturity requires no transaction.
    function lockPolicy(address account) external view returns (LockPolicy memory);
    /// @notice Whether this policy currently rejects positive outgoing amounts.
    /// @dev Does not predict balance, allowance, or other independent restrictions.
    function isTransferBlocked(address account) external view returns (bool);
}
```

### Enrollment and roles

An account is initially unenrolled and unrestricted by this extension. Only the account itself MAY enroll it, by calling `enrollLock`. Enrollment MUST fail if already enrolled, if the cooldown is zero, or if the guardian is zero or equal to the holder. Successful enrollment MUST set `enrolled = true`, `locked = true`, `unlockBlock = 0`, record the supplied cooldown and guardian, and emit `LockEnrolled` followed by `AccountLocked`.

Enrollment MUST NOT be removed. The cooldown and guardian MUST NOT change after enrollment. Additional entry points MUST NOT bypass these requirements. Role rotation and policy relaxation are intentionally outside this minimal proposal; implementations claiming conformance cannot introduce an immediate override for them. A holder MAY use a separately governed smart account as guardian, but changes within that account are outside the token's guarantee.

The guardian can block movements but cannot request an unlock for the holder, grant allowances for the holder, or move the holder's tokens by virtue of that role. ERC-20 spenders are not policy administrators. An exchange can operate a guardian only when explicitly selected by the holder.

### State machine and exact block boundary

Let `b` be the current `block.number`, `D` the configured cooldown, and `U` the stored unlock block.

| State | Condition | Positive outgoing amounts |
| --- | --- | --- |
| Unenrolled | `enrolled == false` | Unrestricted by this extension |
| Locked | `enrolled && locked` | Revert |
| Cooling | `enrolled && !locked && b < U` | Revert |
| Unlocked | `enrolled && !locked && b >= U` | Allowed by this extension |

`requestUnlock()` MUST affect only its caller and MUST revert unless the caller is enrolled and Locked. It MUST set `locked = false` and `unlockBlock = b + D`, and emit `UnlockRequested`. Checked arithmetic MUST revert on overflow. Repeated requests during Cooling or Unlocked MUST revert. An unlock request MUST NOT transfer or reserve tokens, select recipients, or erase allowances.

`lock(account)` MUST succeed only when called by the enrolled account or its recorded guardian. It MUST set `locked = true`, set `unlockBlock = 0`, and emit `AccountLocked`, including when already Locked. It MUST cancel any previous countdown. A later unlock request MUST wait the full delay again.

Maturity is automatic: no transaction or event is required at `U`. The account remains Unlocked until locked again; there is no automatic expiry or one-transfer authorization. `lockPolicy` MUST return stored values, including an already-matured `unlockBlock`. For an unenrolled holder it MUST return an all-zero struct. `isTransferBlocked` MUST report the Locked or Cooling predicate above. It is a policy query, not a promise that another transfer restriction will pass.

### Enforcement across debit paths

All positive outgoing movements from an enrolled account MUST enforce its state at execution time, including `transfer`, `transferFrom`, self-transfers, burns, batch operations, and movements enabled by pre-existing or signature-based approvals. Policy MUST be keyed by the balance holder (`from`), not by operator, caller, recipient, or transaction origin. A noncompliant movement MUST revert atomically, including allowance and balance changes.

Inbound transfers and minting MUST NOT be blocked by the recipient's lock. The sender's policy still applies to inbound transfers from another holder. Zero-value transfers MUST NOT be rejected solely by this extension and retain ERC-20 event behavior. `approve` remains available, including revocation. Allowances MUST NOT be cleared or bypassed by a state transition; they become usable again after maturity if not revoked.

Additional debit APIs MUST apply the same checks. Implementations with rebasing, confiscation, fee debits, or alternative balance accounting MUST define and enforce equivalent protection on positive movements they expose; they MUST NOT advertise conformance while providing a privileged transfer bypass. Passive valuation changes are not transfers. This proposal standardizes plain token-unit transfers, not an asset-value guarantee.

### Discovery

Wallets MAY probe `lockPolicy` and `isTransferBlocked` by `eth_call`. A missing method or undecodable result indicates unsupported functionality, not an unlocked account. This proposal does not require an interface registry or ERC-165. Queries are snapshots and MUST NOT be treated as reservations against intervening transactions.

## Rationale

A token-side check covers both holder-initiated and delegated spending. Restricting only wallet UI or `transfer` leaves an allowance-based bypass. Block numbers specify a precise ordering boundary without promising a fixed wall-clock interval. A guardian with only restrictive powers gives an independent responder a veto without granting token custody.

Immutable enrollment parameters keep the delay meaningful even when a holder key is compromised: the attacker cannot first shorten the delay, remove the guardian, or unenroll. This trades convenience and recovery for a small, reviewable state machine. A future recovery design would require its own threat model.

[ERC-5753](./erc-5753.md) addresses NFT locking with an unlocker role; this proposal protects a fungible holder's outgoing balance and adds an unavoidable waiting interval. [ERC-7720](./erc-7720.md) concerns deferred token transfers; this proposal retains balances in the holder account and delays spending capability, rather than creating escrowed payments. The specific question for reviewers is whether this interface merits standardization beyond existing application-specific locks.

## Backwards Compatibility

ERC-20 selectors and successful transfer semantics are unchanged. However, an opted-in holder's transfer may revert despite sufficient balance and allowance. Applications that assume unconditional transferability, including lending protocols and automated liquidators, need explicit integration and SHOULD avoid accepting locked assets without compatible risk controls.

This cannot retrofit protection to an immutable existing ERC-20. Adoption requires implementation in a token, an appropriately governed token upgrade, or a separately designed custodial wrapper/vault. A wrapper does not protect underlying assets left outside it. Native ETH, Bitcoin, NFTs, and multi-token assets are not covered by this interface.

## Test Cases

| Setup and operation | Required result |
| --- | --- |
| Enroll with `D = 5` and a distinct guardian | Locked immediately |
| Request unlock in block 100 | `U = 105`, Cooling |
| Positive transfer in block 104 | Revert |
| Positive transfer in block 105 | Pass this policy |
| Guardian locks in block 103 | `U = 0`, Locked indefinitely |
| After that lock, request unlock in block 104 | New `U = 109` |
| Call request again while Cooling | Revert without changing `U` |
| Approved operator spends while Locked | Revert, allowance unchanged |
| Holder burns or transfers to self while Locked | Revert |
| Zero transfer while Locked | Policy permits; normal Transfer event |
| Transfer into a locked recipient | Recipient lock does not reject it |
| Guardian calls requestUnlock | Does not unlock another holder |
| Re-enroll to reduce cooldown | Revert |

## Security Considerations

The defense assumes protection was enrolled before the attack, the enforcing token cannot be replaced or bypassed, and a responder can get a lock transaction included before the first malicious outgoing movement. A guardian transaction submitted first is not necessarily executed first. At the maturity block, transaction ordering can determine the result. Reorganizations, censorship, congestion, and chain-specific block-number semantics affect the response margin.

The monitor SHOULD watch `UnlockRequested`, verify the canonical state, alert a separately secured response team, and fund its guardian with gas. A holder who leaves the account Unlocked loses the delay's protection until relocking. This does not reverse finalized transfers or identify malicious intent.

A compromised guardian can deny service indefinitely. Lost holder access cannot be recovered through the guardian. Immutable parameters can strand assets when governance or signing arrangements fail. These consequences MUST be disclosed before enrollment. A guardian using the same devices or operational access as the holder may not provide independence.

Changing code delegated by a holder account does not remove a correctly enforced token-side restriction. Conversely, wallet-only checks can disappear when the wallet's execution or upgrade path changes. Token upgrades, module installation, privileged transfer methods, and direct storage manipulation are potential bypasses and must not exist outside the stated protection boundary.

Pre-existing allowances remain live after unlock. Before reopening a suspected compromised account, operators SHOULD revoke dangerous allowances and restore signer control. This extension alone cannot safely recover an account under ongoing attacker control.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).

