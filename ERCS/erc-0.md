---
eip: 0
title: Wallet Pass Extension for NFTs
description: Lets tokens advertise and deliver native mobile wallet passes, such as Apple Wallet and Google Wallet passes
author: Hunt (@huntclubhero) <hunt@halldon.com>
discussions-to: https://ethereum-magicians.org/t/wallet-pass-extension-for-nfts-surfacing-tokens-as-apple-wallet-google-wallet-passes/29358
status: Draft
type: Standards Track
category: ERC
created: 2026-08-07
requires: 165, 721, 1271, 4361, 4907
---

## Abstract

This proposal extends [ERC-721](./eip-721.md) so that a token contract can advertise that its tokens are available as native mobile wallet passes, such as Apple Wallet passes and Google Wallet objects. It defines a `passURI` view function, a pass manifest that tells clients how to acquire the pass on each platform, events that signal when pass content has changed, and the authorization required before a pass can trigger a state-changing action. How an issuer generates, signs, and pushes passes is out of scope.

## Motivation

Native wallet passes are a programmable surface that ships by default on nearly every smartphone. A pass can display live state, link into web experiences, and receive platform push updates, all without the holder installing an application. Production systems already bind NFTs to wallet passes (memberships, tickets, loyalty balances, and interactive experiences whose state lives on chain), but each one builds a proprietary bridge. The same seam serves any token whose state a holder would want on a card they already carry, from tickets and memberships today to tokenized real-world assets and credentials. As a result:

- Wallets, marketplaces, and indexers cannot discover that a token has a pass representation, so the capability stays invisible outside the issuer's own site.
- Pass distributors have no shared signal that a token's pass content is stale.
- Each integration re-derives the same security decisions (how pass links relate to ownership, what happens on transfer), with uneven results.

A small shared discovery interface lets any client (a marketplace, a wallet app, an email service, a point of sale) offer "Add to Apple Wallet" or "Save to Google Wallet" for any compliant token, the way `tokenURI` made metadata portable.

## Specification

This specification has three parts: a discovery interface and pass manifest, a freshness signal, and the authorization a pass-reachable action requires. Only the first two touch the chain; the third exists because a pass is a bearer artifact and any action it can trigger must be authorized independently of it.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Contract interface

Compliant contracts MUST implement the `IERC721WalletPass` interface and the [ERC-165](./eip-165.md) `supportsInterface` function, and MUST return `true` for the interface identifier `0xef5f1e71`.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title ERC-721 Wallet Pass Extension
/// @dev The ERC-165 identifier for this interface is 0xef5f1e71.
interface IERC721WalletPass {
    /// @notice Emitted when the wallet pass content bound to a token has
    ///  changed. Pass distributors SHOULD regenerate the pass and, where the
    ///  platform supports it, push the update to installed passes.
    event PassUpdate(uint256 indexed tokenId);

    /// @notice Emitted when the wallet pass content for a consecutive range
    ///  of tokens has changed.
    event BatchPassUpdate(uint256 fromTokenId, uint256 toTokenId);

    /// @notice Get the pass endpoint URI for a token.
    /// @dev Throws if `tokenId` is not a valid token. The returned URI MUST
    ///  resolve to a pass manifest as defined in this standard.
    /// @param tokenId The token whose pass endpoint is requested.
    /// @return The pass endpoint URI.
    function passURI(uint256 tokenId) external view returns (string memory);
}
```

The range in `BatchPassUpdate` is inclusive of both `fromTokenId` and `toTokenId`.

`passURI` parallels `tokenURI`: a level of indirection to an off-chain document, because wallet passes are signed platform artifacts that cannot be produced on chain.

### Pass manifest

The URI returned by `passURI` MUST resolve to a JSON document (the pass manifest) with the following shape. In the gated configuration defined under Acquisition URLs, the manifest is returned only to a request that carries a control proof; the response to any other request is defined under Gated acquisition.

```json
{
  "formats": {
    "apple": "https://issuer.example/passes/c3f1.../card.pkpass",
    "google": "https://pay.google.com/gp/v/save/eyJhbGciOi..."
  },
  "updatedAt": 1754500000
}
```

- `formats` is REQUIRED and MUST contain at least one entry. Each key names a pass platform; each value is an acquisition URL for that platform.
- The key `apple` identifies an Apple Wallet pass. Its URL MUST resolve to a resource served with the media type `application/vnd.apple.pkpass`.
- The key `google` identifies a Google Wallet pass. Its URL MUST be a Save to Google Wallet link.
- Additional format keys MAY be present. Clients MUST ignore format keys they do not recognize.
- `updatedAt` is OPTIONAL. When present it MUST be a Unix timestamp (integer seconds) of the last content change, and SHOULD change whenever `PassUpdate` is emitted for the token. It reflects content freshness only and says nothing about whether the acquisition URLs in `formats` are still valid.

### Metadata mirror (OPTIONAL)

The JSON returned by `tokenURI` MAY include a top-level `wallet_pass` property whose value is the pass manifest object defined above. This lets metadata-only consumers surface an add-to-wallet action without an extra fetch. When both are present, the manifest reachable through `passURI` is authoritative. Because `tokenURI` is public, the mirror is appropriate only in the public configuration defined under Acquisition URLs; an implementation in the gated configuration MUST NOT mirror acquisition URLs into metadata.

### Acquisition URLs

Acquisition URLs SHOULD be capability URLs: unguessable, high-entropy, and not derivable from public data such as `tokenId`, pass serial numbers, or metadata fields. When an installed pass exposes links that can trigger state-changing actions, acquisition URLs MUST be capability URLs. Action links embedded in an installed pass are capability URLs in this sense and follow the same rules.

An implementation operates in one of two configurations, and a client learns which from the manifest response: a manifest returned to a request without a control proof is the public configuration, and the 401 response defined under Gated acquisition is the gated configuration.

- **Public configuration.** The manifest is served without access control. Because `passURI` is a public view function, its acquisition URLs are public data, one chain read away from anyone able to enumerate token ids: unguessability does not survive publication. A capability URL here is hygiene (it limits scraping and accidental sharing) and MUST NOT be treated as a proof of possession or ownership.
- **Gated configuration.** Manifest resolution or pass acquisition is gated behind proof of control of the owning account. Only in this configuration may possession of an acquisition URL serve as a possession proof, and acquisition URLs MUST rotate upon the implementation observing a transfer or upon the new owner's first claim, whichever comes first.

Where passes expose state-changing links, implementations in the public configuration SHOULD also rotate acquisition URLs on transfer, so that a pass held by a previous owner stops granting the new owner's links. Implementations SHOULD rotate acquisition URLs on explicit owner request.

Rotation is not synchronous with the on-chain transfer. An implementation observes a transfer through indexing or at the new owner's first claim, so between the transfer and rotation the previous owner's acquisition URLs remain cryptographically valid. The fresh entitlement read required under Authorization of pass-reachable actions is the control that refuses them in that interval; rotation closes the residual window rather than providing the boundary.

Acquisition URLs MAY be short-lived. A Save to Google Wallet link, for example, is a signed JWT that issuers commonly mint on demand and allow to expire. The durable handle for a token's pass is the URI returned by `passURI`; the acquisition URLs inside the manifest are not durable.

#### Gated acquisition

So that a client can acquire a pass from a gated manifest without out-of-band knowledge, an implementation in the gated configuration MUST behave as follows.

- A request for the manifest that carries no control proof MUST be answered with HTTP status 401 and a JSON body whose `error` member is `"proof_required"` and whose `challenge` member is the URI of the challenge endpoint for that token. The body MUST NOT contain acquisition URLs.
- The challenge endpoint MUST accept a GET request carrying the claimed account in the `address` query parameter, and MUST return a JSON body whose `message` member is a challenge for that account that meets the floor defined under Authorization of pass-reachable actions, with the action identified as `urn:wallet-pass:action:acquire`. Because the nonce is single-use, every request MUST issue a fresh challenge.
- To resolve the manifest, the client repeats the manifest request with two headers: `X-Wallet-Pass-Proof`, the signed message encoded as base64url, and `X-Wallet-Pass-Signature`, the signature as a hex string. Encoding the message keeps the multi-line challenge inside a header and keeps manifest resolution a GET.
- The verifier MUST check the proof against the floor and MUST take the fresh entitlement read of check (2). An `acquire` proof MUST NOT authorize any other action, and a proof for any other action MUST NOT resolve the manifest. A proof from an account that is not entitled MUST be refused with HTTP status 403. A verified request MUST be answered with the manifest and the header `Cache-Control: no-store`.
- Acquisition by a proven account that is not the account the implementation last issued passes to is that account's first claim: acquisition URLs MUST rotate before the manifest is returned, per the rotation requirement above.

### Authorization of pass-reachable actions

Every artifact this standard describes (the pass file, the acquisition URL, the manifest) is a bearer artifact, and authorization never lives in the artifact. An action that mutates chain state and is reachable from a pass is authorized by two checks, each closing a hole the other cannot reach:

1. **Proof of control of the owning account**: a signature over a server-issued challenge. The challenge MUST name the token (chain id, contract address, and token id), the requested action, a single-use nonce issued by the verifier, an expiration time, and the identity of the verifier, and the verifier MUST check every one of these fields before acting. Where the signature alone does not identify the signing account, as with contract account signatures verified per [ERC-1271](./eip-1271.md), the challenge MUST also name the claimed account. Challenges SHOULD be serialized as Sign-In with Ethereum messages per [ERC-4361](./eip-4361.md): a conforming challenge already carries every field in which that format's security lives, and wallets and signing libraries already parse the format, for externally owned accounts and contract accounts alike. Accounts created from an email address can satisfy this check without exposing key material to the user, through an embedded signer or a contract account.
2. **A fresh on-chain read of ownership** (for [ERC-721](./eip-721.md), `ownerOf`) at the time of the request, not at pass issuance and not at URL minting. Implementations SHOULD take this read against their best view of the latest safe chain head.

The fresh read MUST be performed for every state-changing action: it closes the transfer window, so a sold token stops acting immediately regardless of how many valid-looking passes remain installed. The control proof MUST be required wherever the pass user experience can carry a signature: it closes forwarding, the case rotation cannot reach, in which a pass or URL leaks while ownership is unchanged. Where the pass user experience cannot carry a signature, check (1) is instead met by the capability configuration described below, sound only under the conditions stated there.

Each challenge field closes its own hole. The token and action scope the proof, so a proof obtained for one action cannot be presented for another. The single-use nonce makes a captured proof worthless a second time. The expiration makes a leaked proof go stale. The verifier identity keeps a challenge signed for one issuer from being presented to another that gates the same token. Because the nonce is single-use and issued by the verifier, every conforming flow includes a server round trip; a flow that does not adopt the RECOMMENDED serialization avoids parsing a message format, not the round trip.

#### Extended entitlement

Implementations MAY extend entitlement to accounts other than the owner, for example a rental user designated per [ERC-4907](./eip-4907.md) `userOf`, or a delegate authorized through an on-chain delegation registry, provided the entitlement policy is documented and every extended entitlement is read with the same request-time freshness required of `ownerOf`, never cached from pass issuance or URL minting. The claimed account named in the challenge is then tested against the documented entitlement rather than bare `ownerOf` equality.

Extension raises a question the single-owner model never had to answer: during an active rental both the owner and the rental user are live accounts, so a policy that merely adds accounts lets both act at once. A documented policy MUST therefore define precedence. A rental entitlement (an active ERC-4907 `userOf`) SHOULD be exclusive of the owner for the actions it covers, while a delegation is additive by intent. Absent a documented extension, `ownerOf` is the entitlement and the fresh read of it is the default requirement.

#### Example challenge

The following is a conforming Sign-In with Ethereum challenge for the feed action on token id 412 of an example ERC-721 contract on chain id 1, issued by `issuer.example`.

```text
issuer.example wants you to sign in with your Ethereum account:
0x2B7E9A4c1F0d8e63A5b2C4D6E8F0A1b3C5d7E9F2

Authorize the feed action for wallet pass token 412 on issuer.example.

URI: https://issuer.example/wallet-pass/actions
Version: 1
Chain ID: 1
Nonce: Xq3F9kP2mR7tW1Zb
Issued At: 2026-08-07T15:04:05Z
Expiration Time: 2026-08-07T15:09:05Z
Resources:
- eip155:1/erc721:0x5F9B5a1cdED9d6B3f5E8a2C47B0e13d6A8F4c2e1/412
- urn:wallet-pass:action:feed
```

Each floor field has a fixed place in the message:

- The token is the first resource, a CAIP-19 asset identifier carrying chain id, contract address, and token id together.
- The action is the second resource, `urn:wallet-pass:action:feed`, and is restated in plain language in the statement line.
- The single-use nonce is the `Nonce` field and the expiration is the `Expiration Time` field.
- The verifier identity is the `domain` on the first line.
- The claimed account is the `address` line. A contract account verified per ERC-1271 uses the same message, with the claimed account in that same line.

Both resource entries are valid RFC 3986 URIs, as ERC-4361 requires of the resources list. The example timestamps omit fractional seconds; RFC 3339 permits them, and a message whose timestamps carry them (for example `2026-08-07T15:04:05.000Z`, the form common signing libraries emit) conforms identically.

#### The capability configuration

An installed pass is a static artifact. Its fields are fixed at issuance and change only through platform push, so a pass cannot carry a single-use nonce or a short expiration. In an email-onboarded custodial or relayer product the signing key is typically held by the server or an embedded signer rather than prompted per action, so no per-action user signature exists when a pass link is followed. A challenge, when one is used, is therefore fetched from the verifier at action time; the link embedded in the pass only reaches the flow and never carries the proof. The capability configuration is not a third configuration beside public and gated: it is the gated configuration operated so that the capability URL carries the possession role.

In such a deployment the capability URL MAY stand in for check (1). The substitution is explicitly weaker than a per-action signature and is permitted only when all of the following hold:

- the deployment operates the gated configuration defined under Acquisition URLs;
- the URL is an unguessable, high-entropy capability;
- the URL is bound to the specific token and action it reaches;
- the URL rotates on transfer per Acquisition URLs (upon observation of the transfer or the new owner's first claim, not synchronously); and
- check (2), the fresh entitlement read, remains in force unconditionally.

Check (2) is never substitutable. No configuration, capability or signed, may omit or defer the fresh entitlement read.

What the substitution gives up: with no per-action signature, forwarding is not closed. Any party holding the capability URL can trigger the bound action while ownership is unchanged. Unguessability does not help once the URL has leaked, rotation does not fire absent a transfer, and the fresh entitlement read refuses a sold token, not a forwarded URL under an unchanged owner. The configuration accepts this residual, so the substitution is sound only for actions whose worst-case impact under forwarding the implementation can tolerate. Actions above that tolerance require the signed challenge.

The verifier-identity field of a signed challenge and the issuer binding of a capability URL are different properties. The verifier-identity field stops a captured signature from being presented to a different verifier that gates the same token. A server-held capability URL has no user signature to lift; its binding to the issuer is structural (the URL resolves only at the issuer's endpoint), not signed.

The identifier a capability URL binds MAY be a server-resolved identifier, such as a pass serial, provided it maps deterministically and uniquely to a single on-chain token and cannot be re-bound to another token. The explicit chain id, contract address, and token id triple is RECOMMENDED for capability bindings, and remains REQUIRED in a signed challenge.

### Issuer requirements

- Implementations SHOULD emit `PassUpdate` whenever on-chain state rendered on the pass changes, and SHOULD push updated content to installed passes through the platform update mechanism where available.
- On transfer of a token, implementations SHOULD update, invalidate, or visibly mark as superseded the passes issued to the previous owner, so that an installed pass does not continue to present itself as current.
- A wallet pass is a projection of the token, not the token. Implementations MUST NOT treat possession of a pass file, or the ability to add it to a device wallet, as proof of ownership of the underlying token, and MUST NOT authorize a state-changing action by pass possession alone.
- Pass endpoints SHOULD be served from an origin consistent with the collection's published web presence.
- Pass identifiers and pass-visible fields SHOULD NOT embed holder personal information. Platform object identifiers SHOULD be random rather than derived from email addresses or account identifiers.

### Client requirements

- Clients SHOULD fetch the manifest at the moment of the user's add-to-wallet action, and MUST NOT durably cache acquisition URLs.
- Clients that offer add-to-wallet actions for arbitrary compliant tokens SHOULD present the issuing contract address alongside the action.

## Rationale

**URI indirection instead of on-chain pass data.** Apple Wallet passes are signed bundles produced with issuer certificates; Google Wallet passes are objects registered through an issuer account. Neither can be constructed on chain, and both change far more often than token metadata (countdowns, balances, standings). A `tokenURI`-style endpoint is the only shape that fits every platform.

**A manifest instead of format query parameters.** One JSON manifest tells the client everything available for the token in a single request and extends to future platforms by adding keys. Query-parameter negotiation was rejected because it makes capabilities undiscoverable without probing.

**A dedicated `PassUpdate` event instead of reusing [ERC-4906](./eip-4906.md).** `MetadataUpdate` signals that `tokenURI` content changed and is consumed by NFT indexers. Pass content routinely changes when metadata does not (for example a countdown rendered on the pass), and its consumers are pass distributors rather than indexers. Implementations that mirror the manifest into metadata can emit both events.

**Two checks, not one.** Rotation feels like leak coverage but is only transfer coverage: a URL forwarded under an unchanged owner never triggers it. A fresh read alone refuses a sold token but not a forwarded one. Requiring both, and naming what each closes, keeps implementations from mistaking either for the whole boundary.

**A mandated challenge floor with ERC-4361 as the recommended serialization.** The security of the control proof lives in the challenge fields, so this proposal mandates the fields rather than a message format. Sign-In with Ethereum is the serialization of exactly those fields that wallets and libraries already emit and parse, so recommending it buys interoperability at near zero cost, while a flow that cannot parse the format still meets the same floor.

**A disclosed capability configuration instead of silence.** Consumer pass products commonly onboard by email and hold keys server-side, so a per-action user signature does not exist on the pass path. Without a defined substitute, every such product would be non-conforming by construction, or would claim a signature-equivalent guarantee it does not have. The capability configuration permits the substitution under stated conditions and states its cost.

**Delivery pipeline out of scope.** Device registration, platform push (APNs and the Google Wallet API), construction of action links, and pass art are platform- and vendor-specific. Standardizing them would freeze implementation detail without improving interoperability; discovery and authorization are the interoperable seams.

## Backwards Compatibility

This proposal is a pure extension of ERC-721 and changes no existing behavior. Contracts that do not implement it are unaffected, and the metadata mirror is ignored by clients that do not understand it. The interface can be implemented alongside other extensions (enumerable, royalty, token-bound accounts) without interaction.

Application to [ERC-1155](./eip-1155.md) is out of scope: fungible balances and multi-holder semantics require a different binding between holder and pass. A future extension would bind a specific account alongside the token id and test `balanceOf(account, id)` against a minimum holding, which defaults to 1, in the authorization check, keeping multi-holder semantics out of the pass artifact.

## Test Cases

The reference implementation carries executable tests. The [contract suite](../assets/eip-0/reference/contracts/test/ERC721WalletPass.t.sol) asserts that `type(IERC721WalletPass).interfaceId` equals `0xef5f1e71` and covers `passURI` and both events. The [action suite](../assets/eip-0/reference/server/test/action.test.ts) and the [manifest suite](../assets/eip-0/reference/server/test/manifest.test.ts) exercise the authorization floor one property at a time: a replayed nonce, an expired challenge, a different verifier, a proof for another action or token, a signature from the wrong account, and an ownership change between challenge and action are each rejected; a gated manifest is refused without a control proof and its response points at the challenge endpoint, whose acquire challenge then resolves the manifest; and a rotated capability URL stops resolving.

## Reference Implementation

A [reference implementation](../assets/eip-0/README.md) is included in the assets directory under CC0. It consists of a minimal ERC-721 implementing the interface ([`ERC721WalletPass.sol`](../assets/eip-0/reference/contracts/src/ERC721WalletPass.sol)) and an off-chain server that issues and verifies ERC-4361 challenges against the floor ([`authorize.ts`](../assets/eip-0/reference/server/src/authorize.ts)), serves the manifest in the public and gated configurations, and rotates capability URLs on transfer ([`passStore.ts`](../assets/eip-0/reference/server/src/passStore.ts)).

Non-normative [deployment notes](../assets/eip-0/implementation-notes.md) describe a production deployment whose token contract implements this interface and whose server resolves `passURI` in the gated configuration, how it delivers passes on Apple Wallet and Google Wallet and applies the authorization requirements above, and the platform constraints that shaped it.

## Security Considerations

**Passes are bearer artifacts.** A pass file can be forwarded and installed on any number of devices, and platforms do not enforce uniqueness. Treating possession as ownership creates a confused deputy in which anyone holding a shared pass exercises the owner's privileges. The two checks under Authorization of pass-reachable actions are not redundant: the fresh read closes the transfer window, the control proof closes forwarding, and the challenge fields close replay and cross-verifier reuse. An implementation that skips either check reopens the hole only that check closes. The capability configuration gives up forwarding protection by design, as the specification states.

**Freshness is bounded, not absolute.** The fresh read narrows the transfer window to the interval between the read and the action, and a read is only as fresh as the chain head it reflects: a lagging node or a reorganization can make it stale. This residual window is accepted risk of the design.

**Derivable links.** A pass link or download URL keyed only by public data, such as a token id or pass serial, lets anyone who can read the chain obtain the pass or trigger its actions. The requirement that such URLs be capability URLs exists to rule this out, and it applies to pass download URLs as much as to action links.

**Capability URL leakage.** Acquisition URLs and action links appear in emails, chat messages, and device backups. Entropy limits guessing and rotation limits the damage window of a leak, but a URL published in a public-configuration manifest is public data regardless of entropy. Durable client caching would widen exposure and surface URLs that have expired or rotated.

**Stale passes after transfer.** Without invalidation or push, a previous owner's installed pass keeps displaying state and may still render action links. Until the implementation observes the transfer, that owner's capability URLs also remain valid; the fresh read, not rotation, refuses them in that interval.

**Phishing surface.** Pass fields carry arbitrary links and text under issuer branding. Presenting the issuing contract address in clients and serving pass endpoints from an origin consistent with the collection are the mitigations this proposal specifies.

**The manifest is issuer-asserted.** The only chain-asserted fact is that the token contract designated the endpoint through `passURI`. Pass files are signed under the issuer's Apple or Google platform credentials, but nothing in the manifest JSON is bound to chain state, so a client can verify only that the manifest was reached through the contract's `passURI`.

**Privacy.** Pass delivery involves device push registrations and often email addresses. Identifiers derived from them would leak through forwarded passes and backups, which is why the issuer requirements call for random identifiers free of personal information.

**Endpoint availability.** The manifest endpoint is off-chain infrastructure. Its failure affects pass delivery and freshness only; ownership and transferability of the token never depend on it.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
