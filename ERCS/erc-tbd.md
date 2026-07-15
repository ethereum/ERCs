---
eip: TBD
title: Two-Phase Asset Transfers
description: Revocable transfers of ETH and tokens that settle only when the named receiver accepts, optionally gated by an off-chain secret key.
author: muhammadaus <aushijree@gmail.com>
discussions-to: https://ethereum-magicians.org/t/two-phase-asset-transfers/TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-07-12
requires: 20, 165, 721, 1155
---

## Abstract

This ERC specifies a **two-phase transfer** for any on-chain asset: the sender *initiates* (the
asset is locked, bound to a named receiver), the receiver *accepts*, and only then does the
transfer settle. Until someone accepts, the sender can take the asset back at any time; after a
deadline passes, the sender can reclaim it.

The lifecycle is provided by a standalone escrow contract (`ITwoPhaseEscrow`) that works with
assets exactly as they are deployed today: **native ETH** and **any [ERC-20](./erc-20.md),
[ERC-721](./erc-721.md), or [ERC-1155](./erc-1155.md)**. No asset contract needs to change;
the escrow uses only the approval and transfer mechanics every token already has.

Two acceptance modes are specified:

1. **Plain mode**: accepting takes only a transaction signed by the named receiver.
2. **Committed mode (optional)**: the sender also creates a throwaway secret key and hands it
   to the receiver off-chain. Accepting then takes the receiver's own key **and** a signature
   made with the secret key. The secret never appears on-chain, not in successful transactions
   and not in reverted ones, and neither factor works without the other.

Plain `transfer()` / `transferFrom()` / `safeTransferFrom()` semantics are **preserved
unchanged**: to the underlying assets the escrow is an ordinary holder, so existing DeFi and
marketplace integrations are not affected. The escrow is discoverable via
[ERC-165](./erc-165.md).

## Motivation

On Ethereum, a transfer cannot be undone. Send ETH or tokens to the wrong address (one
mistyped character, a poisoned clipboard, a swapped QR code, a contact who lost that key) and
the assets are gone. Analytics firms report hundreds of millions of dollars locked in
unreachable addresses every year. This is not a flaw of any one token standard; it is how
push-based sending works everywhere. That is why this ERC covers native ETH and all major
asset standards, not just one token interface.

Existing mitigations do not address the root cause:

- **Smart wallets / address books**: operate off-chain and protect only opted-in users.
- **Ad-hoc escrow contracts**: retrofit two-phase behavior but without a standard interface,
  every wallet must integrate each escrow individually.
- **Multi-sig and social recovery**: solve key loss, not wrong-address loss.

### The receiver should have a say

In a normal transfer, only the sender acts. The receiver does nothing, and a wrong address
owns the funds the instant the transaction lands. Two-phase transfers flip this: the funds go
into a pending state, and nothing settles until the named receiver signs an accept. Until they
do, the sender can take the funds back. A stranger at a mistyped address never receives
anything without acting for it.

### Why an optional second factor

Requiring the receiver to accept already stops funds from landing on a wrong address by
accident. But it does not stop one case: the wrong address belongs to someone active, they see
the pending transfer, and they accept it before the sender notices the mistake.

Committed mode closes this. The sender creates a secret and shares it with the intended
receiver directly (chat, in person, a claim link), and only after the receiver has confirmed
"yes, this is my address". Nobody can accept without the secret. An active stranger at a wrong
address gets nothing.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in
RFC 2119 and RFC 8174.

### Definitions

- **Pending transfer**: initiated but not yet accepted, revoked, or reclaimed.
- **Expiry**: absolute Unix timestamp after which the receiver can no longer accept; the sender
  MAY reclaim at or after expiry via `reclaimExpired`.
- **Transfer ID**: a `uint256` uniquely identifying a pending transfer within an escrow
  contract.
- **Secret**: a throwaway secp256k1 private key, generated fresh per transfer by the sender and
  delivered to the receiver out-of-band. It is used only to sign the accept digest and MUST never
  appear on-chain.
- **Commit**: the Ethereum address derived from the secret key. A commit of `address(0)` denotes
  plain mode.
- **Accept digest**: `keccak256(abi.encode(block.chainid, escrowContract, id, caller))`,
  the message the secret key signs to authorize acceptance by `caller`.

### Deployment model

The lifecycle is implemented by a standalone escrow contract that takes custody of the asset
while pending. It works for **native ETH** (sent as `msg.value` at initiation) and **any
deployed ERC-20, ERC-721, or ERC-1155** (pulled via the asset's own approval + `transferFrom`
mechanics). Assets are described by an `Asset` struct (`kind`, `token`, `tokenId`, `amount`)
so one contract and one wallet integration cover every asset class. Nothing in this ERC
requires any change to any asset contract.

### Common lifecycle rules (both modes)

- `initiateTransfer` / `initiateTransferWithCommit` MUST bind the pending asset to exactly one
  receiver `to` (non-zero, not the sender) and one expiry in
  `[block.timestamp + MIN_EXPIRY, block.timestamp + MAX_EXPIRY]`; otherwise MUST revert.
- While pending, the escrowed asset MUST NOT be movable by any function other than
  `acceptTransfer`, `revokeTransfer`, or `reclaimExpired` for that transfer id.
- `acceptTransfer` (either overload) MUST require `msg.sender == pending.to` and MUST revert if
  the transfer is not pending. Implementations MAY additionally reject acceptance after expiry;
  the reference implementation lets the sender's `revokeTransfer` / `reclaimExpired` be the
  post-expiry authority instead.
- `revokeTransfer` MUST require `msg.sender == pending.from` and MAY be called any time while
  pending (including after expiry).
- `reclaimExpired` MUST require `msg.sender == pending.from` AND `block.timestamp > expiry`.
  It MUST NOT be callable by third parties (see Rationale).
- Transfer ids MUST never be reused.

The underlying asset contract emits its own standard transfer events as custody moves in and
out of the escrow, so downstream indexers observe settlement through the events they already
handle.

### Committed-mode rules

- `initiateTransferWithCommit` MUST revert if `commit == address(0)` (`BadCommit`).
- The single-argument `acceptTransfer(id)` MUST revert with `SecretRequired` if the transfer
  carries a non-zero commit.
- `acceptTransfer(id, secretSig)` MUST perform the receiver check (`msg.sender == pending.to`,
  reverting `NotReceiver`) **before** any signature verification, so a non-receiver caller
  learns nothing about signature validity. It MUST then verify that `secretSig` is a valid ECDSA
  signature over the accept digest `keccak256(abi.encode(block.chainid, address(this), id,
  msg.sender))` recovering to `pending.commit`, reverting `BadSecret` otherwise (including on
  malformed signatures and plain-mode transfers).
- The raw secret key MUST NOT be a parameter of any function of this interface. Proof of the
  secret is only ever a signature bound to `msg.sender`, so calldata (including calldata of
  reverted transactions and mempool-visible transactions) never contains transferable secret
  material.
- Implementations SHOULD expose `acceptDigest(uint256 id, address caller) → bytes32` so clients
  can construct the exact signing preimage without replicating the encoding.
- Revocation and reclaim MUST NOT require the secret. The sender's key is always a sufficient
  recovery path.

### Assumptions (normative)

Conforming implementations, wallets, and users operate under the following assumptions. They are
part of the security contract of this ERC; violating them voids the protections the standard
provides.

1. **The secret never touches the chain.** The secret key is only ever used to sign, locally.
   What goes into the transaction is the signature, and that signature names the account it
   was made for. So even if someone submits an accept from the wrong account by mistake, the
   leaked signature works for nobody: not for the submitter (wrong receiver), not for anyone
   who copies it (wrong account named inside it). The secret key itself stays private. This is
   enforced by design, not by asking wallets to be careful. A scheme that put the raw secret in
   calldata would leak it the moment any transaction was broadcast, even one that reverts,
   because calldata is public. If the receiver address turns out to be wrong or unowned, keep
   the key private and just revoke or reclaim.
2. **Both factors, always.** Settling a committed transfer takes the receiver's own key AND a
   signature from the secret key. One without the other moves nothing. Front-running an accept
   transaction is useless twice over: the attacker is not the receiver, and the signature they
   copied does not verify for their account.
3. **The secret travels off-chain, and only after the address is confirmed.** Chat, in person,
   QR, claim link. The sender MUST NOT deliver the secret until the receiver has confirmed,
   over that same channel, that the address is really theirs. Delivering the secret on the mere
   assumption that `to` is correct hands both factors to whoever actually controls that
   address: they can sign the accept, broadcast it, and once mined the funds are lost for good
   (see Security Considerations). On-chain, only the derived address appears.
4. **Fresh secret every time.** Secret keys MUST be randomly generated per transfer (full
   256-bit entropy) and MUST NOT be reused across transfers or chains. Words and PINs are
   forbidden as key material; anyone can grind guesses against the published commit address
   off-chain.
5. **Wrong address? Revoke.** When the sender discovers `to` is wrong or unclaimed, the ONLY
   correct actions are `revokeTransfer` (any time while pending) or `reclaimExpired` (after
   expiry). Wallets MUST steer users there and MUST NOT prompt for the secret key or sign with
   it in that situation.
6. **The sender still needs their key.** Revoke and reclaim require the sender's key. Lose it
   while a transfer is pending and there is no recovery once the receiver window lapses.
   Pending transfers are not a substitute for key custody.
7. **Timestamps and finality.** Expiry uses `block.timestamp`. Validators can shift it by
   seconds; `MIN_EXPIRY` is minutes, so it doesn't matter. A settled accept is assumed final;
   this ERC does not defend against chain reorganizations.
8. **Wallet duties.** Check ERC-165 before showing two-phase UX. Sign the accept digest
   locally; never send the secret key to any service. Never log or store it unencrypted. Sign
   for the account the user is actually accepting from. Show senders their pending outbound
   transfers, so an unexpected acceptance race gets noticed and revoked.
9. **The custodian is the contract.** While pending, the escrow contract holds the asset.
   Users trust that it upholds the accounting invariant below and has no path that moves
   escrowed assets outside accept / revoke / reclaim.

### ITwoPhaseEscrow

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface ITwoPhaseEscrow {
    enum Status { None, Pending, Accepted, Revoked, Reclaimed }
    enum AssetType { Native, ERC20, ERC721, ERC1155 }

    struct Asset {
        AssetType kind;
        address   token;   // asset contract; MUST be address(0) for Native
        uint256   tokenId; // ERC-721 / ERC-1155 id; MUST be 0 otherwise
        uint256   amount;  // wei / token units / ERC-1155 units; MUST be 1 for ERC-721
    }

    struct PendingTransfer {
        address from;
        address to;
        Asset   asset;
        uint64  expiry;
        Status  status;
        address commit;  // address of the secret key; address(0) => plain mode
    }

    event TransferInitiated(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        Asset   asset,
        uint64  expiry,
        address commit
    );
    event TransferAccepted(uint256 indexed id);
    event TransferRevoked(uint256 indexed id);
    event TransferReclaimed(uint256 indexed id);

    error BadExpiry();
    error BadAmount();
    error BadReceiver();
    error BadAsset();             // asset fields inconsistent with kind
    error NotReceiver();
    error NotSender();
    error NotPending();
    error NotExpired();
    error BadCommit();
    error SecretRequired();
    error BadSecret();
    error NativeTransferFailed();

    /// Escrow `asset` from the caller into a pending transfer bound to `to`.
    /// Native: send the amount as msg.value. Tokens: approve the escrow first;
    /// msg.value MUST be zero.
    function initiateTransfer(Asset calldata asset, address to, uint64 expiry)
        external payable returns (uint256 id);

    function initiateTransferWithCommit(Asset calldata asset, address to, uint64 expiry, address commit)
        external payable returns (uint256 id);

    function acceptTransfer(uint256 id) external;
    function acceptTransfer(uint256 id, bytes calldata secretSig) external;
    function revokeTransfer(uint256 id) external;
    function reclaimExpired(uint256 id) external;

    function pendingTransfer(uint256 id) external view returns (PendingTransfer memory);
    function acceptDigest(uint256 id, address caller) external view returns (bytes32);
    function MIN_EXPIRY() external view returns (uint64);
    function MAX_EXPIRY() external view returns (uint64);
}
```

Escrow-specific rules:

- The escrow MUST take full custody of the asset at initiation (native value via `msg.value ==
  asset.amount`; tokens pulled via the asset contract's `transferFrom` / `safeTransferFrom`)
  and MUST validate `Asset` field consistency per kind (`BadAsset` / `BadAmount` otherwise).
- `msg.value` MUST be zero for non-native kinds, and MUST equal `asset.amount` for native, so
  the escrow can never hold ETH that no transfer record owns. Implementations SHOULD NOT expose
  a `receive()` / `fallback()` path for the same reason.
- ERC-721 escrows MUST enforce `amount == 1`. ERC-1155 escrows MUST implement the
  `onERC1155Received` hook to take custody.
- All state-changing functions SHOULD be reentrancy-guarded: settlement calls out to
  arbitrary asset contracts and (for native ETH) to the recipient.
- Fee-on-transfer or rebasing ERC-20s MAY cause the escrowed amount to differ from
  `asset.amount`; handling such tokens is implementation-defined and senders SHOULD NOT use
  the escrow with them.

### Compatibility with base asset standards

The two-phase lifecycle is entered only by explicit calls to `initiateTransfer` /
`initiateTransferWithCommit` (opt-in per call). The escrow by construction changes nothing
about the underlying assets; it is an ordinary holder from their perspective. Routing all
plain transfers through two-phase is explicitly NOT specified.

### ERC-165 detection

Escrows MUST support ERC-165 and return `true` from `supportsInterface` for
`type(ITwoPhaseEscrow).interfaceId`. Wallets and dapps MUST use this check (not bytecode
inspection or off-chain registries) to decide whether to render two-phase UX.

## Rationale

### Is this worth an ERC?

**For:** money lost to wrong addresses is real, large, and permanent, and grows with adoption;
giving the receiver a say fixes the one-sidedness of plain transfers; and a standard interface
means wallets build the "you have a pending transfer" screen once, not once per escrow.

**Against:** DeFi assumes transfers settle instantly, and a two-phase asset in pending state
doesn't (mitigated here: plain transfers stay untouched); the second transaction doubles gas and
steps for the vast majority of transfers that were fine; wallet-level fixes (address books,
smart wallets) already help; and earlier attempts like [ERC-1996](./erc-1996.md) (Holdable
Token), [ERC-2020](./erc-2020.md) (E-Money Standard Token), and [ERC-5528](./erc-5528.md)
(Refundable Token) never took off.

**Conclusion:** this standard earns its place as (1) a universal retrofit, where one escrow
contract and one wallet integration cover ETH and every deployed token today, and (2) a common
wallet UX. It does not replace normal transfers anywhere.

### Why the escrow comes first

Newly deployed tokens can build the same lifecycle directly into the token contract, which is
smoother for their users: no approval step and no external contract. That option is left to a
separate follow-up ERC. This ERC standardizes the escrow first because it works immediately
with native ETH and every asset already deployed, needing only the approval and transfer
mechanics they expose today. The costs are accepted knowingly: ERC-20/1155 flows need an
approval step, and a third-party contract holds custody while pending (see Security
Considerations).

### Committed mode is optional, not mandatory

Requiring the secret on every transfer was rejected. Between people who transact regularly, the
receiver-accept step alone already prevents accidental mis-delivery, and forcing a secret
exchange every time just doubles the friction. The sender chooses per transfer: plain mode for
a known counterparty, committed mode for a new address or a large amount.

### Signature proof instead of preimage reveal

The obvious design (store `keccak256(secret)`, have the receiver submit the raw reveal code)
was rejected. It has a fatal flaw: the reveal code sits in calldata, and calldata is public the
moment the transaction is broadcast. Every mempool watcher reads the
reveal code out of the pending transaction BEFORE it is mined, and it stays public even if the
transaction reverts. From that moment the code is not a secret anymore; the only thing standing
between mempool observers and the funds is the receiver-binding check. A receiver who submits
from the wrong account by mistake broadcasts the code to the whole network, gets nothing back
(`NotReceiver`), and has burned the second factor. No on-chain check can prevent any of this:
by the time the contract compares hashes, everyone has already seen the code.

So instead: the secret is a throwaway private key, and the receiver proves they have it by
signing. The signed message names the chain, the contract, the transfer id, and the caller's
account, so a copied signature works nowhere else: not for another caller, another transfer,
another contract, or another chain. Submit from the wrong account by mistake and all you leak
is a signature for that wrong account, which is useless to everyone; the key stays private and
still works for the real receiver. The price is one `ecrecover` (~3k gas) and a local signing
step. For the user nothing changes: the secret is still a single 32-byte blob, same as
claim-link protocols use in production today.

One detail: the sender can't know the transfer id before the initiation is mined (ids are a
counter), so the commit itself binds no transfer parameters. That's fine: the commit is stored
inside the transfer record, and the id gets bound at accept time inside the signed message.

### `reclaimExpired` is sender-only

Letting anyone push expired transfers back to the sender was rejected. It gives third parties a
way to interfere with a sender who is still deciding what to do, and it adds nothing, since the
sender can always reclaim themselves.

### Expiry bounds

- **Lower bound (RECOMMENDED 10 minutes):** a genuine hand-off (communicating out-of-band,
  entering the acceptance) must not race the clock. The sender can revoke throughout, so this
  is purely a receiver guarantee.
- **Upper bound (RECOMMENDED 7 days):** prevents accidental long lockups from expiry-field
  typos (e.g., milliseconds passed as seconds) while allowing slow cross-timezone workflows.

## Backwards Compatibility

The escrow is a new standalone contract and changes no existing standard. Underlying assets
see it as an ordinary holder, so contracts, aggregators, DEXs, and marketplaces are
unaffected. Analytics should note that pending value shows up as the escrow contract's
balance until settlement.

## Security Considerations

### No loophole for an accidental third party

Each factor on its own is enough to stop an accidental recipient:

- **Receiver key.** After initiation the funds sit in the contract, not at the target address.
  Settling takes a transaction signed by exactly the named receiver. A stranger at a mistyped
  address gets nothing unless they actively accept, and until anyone accepts, the sender can
  revoke.
- **Secret key (committed mode).** Even a stranger who races to accept fails without the
  secret. And the secret can't be picked up from the chain: the mempool only ever shows
  signatures, each one locked to a specific account (Assumption 1). Watch a valid accept: the
  signature only works for the real receiver. Watch a botched accept from a wrong account: the
  signature only works for that wrong account, where the receiver check rejects it. Nothing
  observed on-chain can be reused by anyone.
- **No bypass path.** The escrow holds custody while pending, ids are never reused, and after
  expiry the only path is back to the sender. Reentrancy can't drain it: settlement does call
  out to asset contracts and ETH recipients, so it is reentrancy-guarded with state finalized
  before any external call.

### Explicit out-of-scope: social engineering

This ERC protects against *mistakes*. It does not protect someone who is tricked into naming
the attacker's address as the receiver and then handing them the secret too; at that point the
victim has given away both factors voluntarily. Wallets SHOULD warn; no contract can prevent
it.

### Secret-handling failure modes

- **On-chain leaks: designed out.** Transactions only ever carry account-bound signatures, so
  no transaction, mined or reverted, can expose the secret key. Accepting from the wrong
  account by mistake, the failure that kills raw-secret schemes, leaks nothing usable here (see
  Rationale).
- **What mempool watchers actually see.** The moment the receiver broadcasts an
  accept, every mempool observer sees the full calldata: the transfer id and the 65-byte
  signature. That is a signature BY the secret key, not the secret key itself. Nobody can
  compute a private key from one ECDSA signature (that is the discrete-log problem; if they
  could, every signed Ethereum transaction would leak its account key). Nobody can replay the
  signature either: the signed digest contains the broadcaster's account, so submitted from
  any other address it fails verification, and the receiver check rejects the caller first
  anyway. And nobody can redirect the payout, because the destination is read from the stored
  transfer record, not from calldata. A builder with a full view of the mempool can delay or
  censor the accept, but cannot take the funds. One cryptographic caveat: two signatures from
  the same secret key with a repeated nonce would expose the key. This cannot arise when
  secrets are single-use (Assumption 4, one signature ever exists per key) and clients sign
  with deterministic nonces (RFC 6979), which standard libraries do.
- **Off-chain leaks: still possible.** The key can leak through the chat it was sent over, a
  compromised device, or a counterparty who wasn't who they claimed. As long as the leak goes
  to someone who is NOT the bound receiver, the funds stay safe (the receiver check still
  holds), but the second factor is gone. On any suspected leak, the sender SHOULD revoke and
  re-initiate with a fresh key.
- **Wrong address plus revealed secret: funds are lost.** This is the one way to lose funds
  under this standard. The sender assumes `to` is correct, skips the confirmation step
  (Assumption 3), and delivers the secret. Whoever actually controls that address now holds
  BOTH factors: they are the bound receiver, and they have the secret key. They sign the
  accept digest with it and broadcast the accept transaction from the receiver address. That
  transaction now sits in the public mempool, carrying the receiver address as its sender and
  the signature proving the secret in its calldata, and it passes every contract check,
  because to the contract this IS the legitimate receiver accepting with the correct secret.
  The sender sees it in the mempool only after it is already broadcast; the only counter is to
  race it with a revoke and hope theirs is mined first. Once the accept is mined, settlement
  is final and irreversible. Both protections were defeated by the same wrong assumption
  before anything touched the chain, and no contract can detect it. This is exactly why
  Assumption 3 makes address confirmation come BEFORE secret delivery, and why wallets MUST
  NOT release the secret until the receiver has confirmed the address over the same channel.
- **Weak secrets are crackable.** A word or PIN as key material can be brute-forced off-chain
  against the published commit address (Assumption 4). Always random, always 256-bit.
- **Plaintext storage spreads the risk.** A wallet that logs or cloud-syncs secret keys extends
  the attack surface to the user's backups (Assumption 8).

### Griefing via dust pending-spam

An attacker can initiate many small pending transfers to a victim to create UI noise. Pending
state costs the attacker gas and locked capital, self-expires within `MAX_EXPIRY`, and wallets
SHOULD let users hide sub-threshold pending inbounds.

### Accounting invariant

Escrow implementations MUST maintain, per asset, at all times: the escrow's holdings of each
asset equal the sum of that asset's pending amounts (for native ETH,
`address(escrow).balance == sum(pending native amounts)`, hence the rule that ETH may enter
only through initiation). Fee-on-transfer and rebasing ERC-20s violate this invariant by
construction and are out of scope (see escrow-specific rules).

### Escrow-specific risks

- **Asset-contract callbacks.** ERC-1155 (and safe ERC-721) transfers invoke recipient hooks;
  malicious or reentrant asset contracts are the reason escrow settlement MUST be
  reentrancy-guarded and state finalized before any external call.
- **Non-paying native recipients.** A receiver or sender that is a contract rejecting ETH will
  make its own payout revert (`NativeTransferFailed`); funds stay escrowed and the counterparty
  path (revoke / reclaim, or accept) remains available. Senders SHOULD NOT initiate native
  transfers from contracts that cannot receive ETH back.
- **Escrow as honeypot.** A shared escrow pools everyone's pending value in one contract, which
  makes that one contract a bigger target. Audit it accordingly. The reference implementation
  keeps the attack surface small on purpose: no owner, no upgradability, no fee logic.

### Timestamp manipulation

Validator timestamp drift (~seconds) is negligible against the minute-scale `MIN_EXPIRY`
(Assumption 7) and cannot be used to deny a legitimate acceptance window.

## Reference Implementation

Reference implementations and a full Foundry test suite are provided in
[`../assets/erc-tbd/`](../assets/erc-tbd/):

- `TwoPhaseEscrow.sol` (with `ITwoPhaseEscrow.sol`): the escrow for native ETH and any
  ERC-20 / ERC-721 / ERC-1155; reentrancy-guarded, no owner, no upgradability.
- Tests. The suite includes the two key negative tests: a valid signature replayed by a
  different caller reverts, and a signature mistakenly produced for the wrong account is
  unusable by everyone including the bound receiver. Together they show that no on-chain
  observation ever yields transferable secret material.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
