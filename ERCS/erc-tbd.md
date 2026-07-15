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

The lifecycle is specified in two conforming embodiments:

- **Standalone escrow (`ITwoPhaseEscrow`)**: a deployable contract that retrofits two-phase
  settlement onto assets that cannot be modified: **native ETH** and **any already-deployed
  [ERC-20](./erc-20.md), [ERC-721](./erc-721.md), or [ERC-1155](./erc-1155.md)**.
- **Token-native extensions (`IERC20TwoPhase`, `IERC721TwoPhase`)**: opt-in interfaces for
  newly deployed tokens that build the lifecycle into the token itself, with no external
  contract or approval step.

Two acceptance modes are specified:

1. **Plain mode**: accepting takes only a transaction signed by the named receiver.
2. **Committed mode (optional)**: the sender also creates a throwaway secret key and hands it
   to the receiver off-chain. Accepting then takes the receiver's own key **and** a signature
   made with the secret key. The secret never appears on-chain, not in successful transactions
   and not in reverted ones, and neither factor works without the other.

Plain `transfer()` / `transferFrom()` / `safeTransferFrom()` semantics are **preserved unchanged**
so existing DeFi and marketplace integrations are not broken. The token-native interfaces are
discoverable via [ERC-165](./erc-165.md).

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
- **Transfer ID**: a `uint256` uniquely identifying a pending transfer within an implementing
  contract (escrow or token).
- **Secret**: a throwaway secp256k1 private key, generated fresh per transfer by the sender and
  delivered to the receiver out-of-band. It is used only to sign the accept digest and MUST never
  appear on-chain.
- **Commit**: the Ethereum address derived from the secret key. A commit of `address(0)` denotes
  plain mode.
- **Accept digest**: `keccak256(abi.encode(block.chainid, implementingContract, id, caller))`,
  the message the secret key signs to authorize acceptance by `caller`.

### Deployment models

The lifecycle MUST be implemented in one of two embodiments; both are conforming:

1. **Standalone escrow (`ITwoPhaseEscrow`)**: a separate contract that takes custody of the
   asset while pending. This is the universal retrofit path: it works for **native ETH** (sent
   as `msg.value` at initiation) and **any deployed ERC-20, ERC-721, or ERC-1155** (pulled via
   the asset's own approval + `transferFrom` mechanics). Assets are described by an `Asset`
   struct (`kind`, `token`, `tokenId`, `amount`) so one contract and one wallet integration
   cover every asset class.
2. **Token-native extension (`IERC20TwoPhase` / `IERC721TwoPhase`)**: for newly deployed
   tokens, the lifecycle lives inside the token: no external contract, no approval step, and
   pending state is enforced by the token's own accounting (escrow-in-own-balance for ERC-20,
   transfer lock for ERC-721). Discoverable via ERC-165.

In short: the escrow works with everything but needs an approval step; the native extension is
smoother but only exists on tokens that adopt it. Wallets SHOULD support both.

### Common lifecycle rules (all embodiments, both modes)

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
- In the token-native embodiment, the standard ERC-20 / ERC-721 `Transfer` event MUST be
  emitted on acceptance so downstream indexers observe settlement identically to a plain
  transfer. (In the escrow embodiment the underlying asset contract emits its own transfer
  events as custody moves.)
- Transfer ids MUST never be reused.

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
9. **The custodian is the contract.** While pending, the escrow or token contract holds the
   asset. Users trust that it upholds the accounting invariant below and has no path that moves
   escrowed assets outside accept / revoke / reclaim.

### ITwoPhaseEscrow (standalone escrow: native ETH and any asset)

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
- All state-changing functions SHOULD be reentrancy-guarded: unlike the token-native
  embodiment, settlement calls out to arbitrary asset contracts and (for native ETH) to the
  recipient.
- Fee-on-transfer or rebasing ERC-20s MAY cause the escrowed amount to differ from
  `asset.amount`; handling such tokens is implementation-defined and senders SHOULD NOT use
  the escrow with them.

### IERC20TwoPhase (token-native extension)

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IERC20TwoPhase {
    enum Status { None, Pending, Accepted, Revoked, Reclaimed }

    struct PendingTransfer {
        address from;
        address to;
        uint256 amount;
        uint64  expiry;  // unix seconds
        Status  status;
        address commit;  // address of the secret key; address(0) => plain mode
    }

    /// commit is address(0) for plain-mode transfers; non-zero for committed ones.
    event TransferInitiated(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint64  expiry,
        address commit
    );
    event TransferAccepted(uint256 indexed id);
    event TransferRevoked(uint256 indexed id);
    event TransferReclaimed(uint256 indexed id);

    error BadExpiry();
    error BadAmount();
    error BadReceiver();
    error NotReceiver();
    error NotSender();
    error NotPending();
    error NotExpired();
    error BadCommit();       // commit == address(0) on initiateTransferWithCommit
    error SecretRequired();  // plain accept on a committed transfer
    error BadSecret();       // signature doesn't recover to the committed address

    /// Escrow `amount` from the caller into a pending transfer bound to `to`.
    /// Caller's spendable balance MUST decrease immediately; `to`'s MUST NOT
    /// increase until acceptance.
    function initiateTransfer(address to, uint256 amount, uint64 expiry)
        external returns (uint256 id);

    /// Like initiateTransfer, but additionally commits to a throwaway secret key
    /// (commit = its address). Settlement then requires the receiver's account key
    /// AND a signature by the secret key.
    function initiateTransferWithCommit(address to, uint256 amount, uint64 expiry, address commit)
        external returns (uint256 id);

    /// Bound receiver accepts a plain transfer. Reverts SecretRequired if committed.
    function acceptTransfer(uint256 id) external;

    /// Bound receiver accepts a committed transfer by proving knowledge of the
    /// secret key: secretSig is its ECDSA signature over
    /// keccak256(abi.encode(block.chainid, address(this), id, msg.sender)).
    /// Receiver check MUST run before signature verification.
    function acceptTransfer(uint256 id, bytes calldata secretSig) external;

    /// The digest the secret key must sign for `caller` to accept transfer `id`.
    function acceptDigest(uint256 id, address caller) external view returns (bytes32);

    /// Sender revokes a still-pending transfer, refunding themselves.
    function revokeTransfer(uint256 id) external;

    /// Sender reclaims an unaccepted transfer after expiry.
    function reclaimExpired(uint256 id) external;

    function pendingTransfer(uint256 id) external view returns (PendingTransfer memory);

    /// Bounds enforced on `expiry` relative to block.timestamp at initiation.
    /// RECOMMENDED: MIN_EXPIRY >= 600 (10 minutes), MAX_EXPIRY <= 604800 (7 days).
    function MIN_EXPIRY() external view returns (uint64);
    function MAX_EXPIRY() external view returns (uint64);
}
```

### IERC721TwoPhase (token-native extension)

Identical lifecycle keyed by `tokenId` instead of `amount`, with these additional rules:

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IERC721TwoPhase {
    enum Status { None, Pending, Accepted, Revoked, Reclaimed }

    struct PendingTransfer {
        address from;
        address to;
        uint256 tokenId;
        uint64  expiry;
        Status  status;
        address commit;
    }

    event TransferInitiated(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        uint256 tokenId,
        uint64  expiry,
        address commit
    );
    event TransferAccepted(uint256 indexed id);
    event TransferRevoked(uint256 indexed id);
    event TransferReclaimed(uint256 indexed id);

    error BadExpiry();
    error BadReceiver();
    error NotOwner();
    error NotReceiver();
    error NotSender();
    error NotPending();
    error NotExpired();
    error AlreadyPending();
    error TokenLocked();
    error BadCommit();
    error SecretRequired();
    error BadSecret();

    function initiateTransfer(address to, uint256 tokenId, uint64 expiry)
        external returns (uint256 id);
    function initiateTransferWithCommit(address to, uint256 tokenId, uint64 expiry, address commit)
        external returns (uint256 id);
    function acceptTransfer(uint256 id) external;
    function acceptTransfer(uint256 id, bytes calldata secretSig) external;
    function revokeTransfer(uint256 id) external;
    function reclaimExpired(uint256 id) external;

    function pendingTransfer(uint256 id) external view returns (PendingTransfer memory);
    function acceptDigest(uint256 id, address caller) external view returns (bytes32);
    function isLocked(uint256 tokenId) external view returns (bool);
    function MIN_EXPIRY() external view returns (uint64);
    function MAX_EXPIRY() external view returns (uint64);
}
```

- While pending, recorded ownership MUST remain with the sender (`ownerOf` unchanged) and the
  token MUST be locked: `transferFrom`, `safeTransferFrom`, and any other ownership-changing
  path MUST revert (`TokenLocked`) until settled. `acceptTransfer` performs the actual move.
- A `tokenId` MUST NOT have more than one simultaneous pending transfer (`AlreadyPending`).

### Compatibility with base asset standards

Token-native implementations MUST preserve existing `transfer`, `transferFrom`, and
`safeTransferFrom` semantics for non-pending assets. The two-phase lifecycle is entered only by
explicit calls to `initiateTransfer` / `initiateTransferWithCommit` (opt-in per call). Routing
all plain transfers through two-phase is explicitly NOT specified (see Rationale). The escrow
embodiment by construction changes nothing about the underlying assets; it is an ordinary
holder from their perspective.

### ERC-165 detection

Token-native implementations MUST return `true` from `supportsInterface` for
`type(IERC20TwoPhase).interfaceId` or `type(IERC721TwoPhase).interfaceId` respectively.
Standalone escrows SHOULD support ERC-165 and return `true` for
`type(ITwoPhaseEscrow).interfaceId`. Wallets and dapps MUST use these checks (not bytecode
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
contract and one wallet integration cover ETH and every deployed token today, (2) an opt-in feature for
new tokens built for person-to-person payments, and (3) a common wallet UX. It does not replace
normal transfers anywhere.

### Why two embodiments instead of one

An escrow-only standard would already cover every asset, including future ones, with no token
cooperation needed. But the escrow flow costs an approval transaction and puts a third-party
contract between the user and their funds; a token that builds the lifecycle in natively skips
both. A native-only standard fails harder: it can never cover ETH or the tokens already
deployed, which is where today's losses actually happen. So both embodiments stay, sharing one
lifecycle, one commit model, and one set of assumptions; wallets only differ in where they read
custody from.

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

### ERC-721 lock model

Moving custody to the contract while pending (making `ownerOf` return the contract) breaks
marketplace metadata and ownership queries. Instead, ownership stays with the sender and the
token is locked; implementations SHOULD enforce the lock in the internal transfer hook (e.g.,
OpenZeppelin v5's `_update`).

### Expiry bounds

- **Lower bound (RECOMMENDED 10 minutes):** a genuine hand-off (communicating out-of-band,
  entering the acceptance) must not race the clock. The sender can revoke throughout, so this
  is purely a receiver guarantee.
- **Upper bound (RECOMMENDED 7 days):** prevents accidental long lockups from expiry-field
  typos (e.g., milliseconds passed as seconds) while allowing slow cross-timezone workflows.

## Backwards Compatibility

The escrow embodiment is a new standalone contract and touches no existing standard. The
token-native embodiment only adds functions, events, and errors on top of ERC-20 / ERC-721; no
existing signature, return type, or event changes. Contracts, aggregators, DEXs, and
marketplaces calling only the base interfaces are unaffected. Note that ERC-20 implementations
using the escrow-in-own-balance pattern will show pending amounts in `balanceOf(token)`, which
analytics treating the token's own address as anomalous should account for.

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
- **No bypass path.** The contract holds custody while pending, ids are never reused, and after
  expiry the only path is back to the sender. Reentrancy can't drain it: the token-native
  embodiment makes no external calls during settlement at all, and the escrow embodiment (which
  does call out to asset contracts and ETH recipients) is reentrancy-guarded with state
  finalized before any external call.

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

### Accounting invariants

Token-native ERC-20 implementations MUST maintain, at all times:

```
totalSupply() == sum(all balances) + sum(all pending amounts)
```

Pending amounts MUST be excluded from the sender's spendable `balanceOf` and MUST NOT appear in
the receiver's until acceptance; otherwise a sender could double-spend escrowed funds. The
reference implementation satisfies the invariant by construction, escrowing pending amounts in
the token contract's own balance.

Escrow implementations MUST maintain the analogous invariant per asset: the escrow's holdings
of each asset equal the sum of that asset's pending amounts (for native ETH,
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

- `TwoPhaseEscrow.sol` (with `ITwoPhaseEscrow.sol`): standalone escrow embodiment for native
  ETH and any ERC-20 / ERC-721 / ERC-1155; reentrancy-guarded, no owner, no upgradability.
- `ERC20TwoPhase.sol` / `ERC721TwoPhase.sol` (with their interfaces): token-native extensions;
  escrow-in-own-balance model for ERC-20, `_update`-enforced lock model for ERC-721.
- Tests. Every suite includes the two key negative tests: a valid signature replayed by a
  different caller reverts, and a signature mistakenly produced for the wrong account is
  unusable by everyone including the bound receiver. Together they show that no on-chain
  observation ever yields transferable secret material.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
