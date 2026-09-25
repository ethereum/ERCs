# Deployment Notes (non-normative)

These notes describe how one production deployment implements this proposal: its on-chain interface, its gated manifest endpoint, how it delivers NFT-bound passes on Apple Wallet and Google Wallet, and how it applies the authorization requirements. Nothing here is normative. Much of what follows sits in the delivery pipeline the specification leaves out of scope, and is recorded because every implementer meets the same platform constraints.

## Technology stack

| Layer | Standard or mechanism | Role |
| --- | --- | --- |
| Token | ERC-721 with this extension (`passURI`, `PassUpdate`, `BatchPassUpdate`, ERC-165 id `0xef5f1e71`) | The token advertises its pass endpoint and signals pass staleness on chain. |
| Token | ERC-6551 token-bound accounts | Each token owns an account that holds its balance; actions spend from the token's own account. |
| Token | ERC-2981 | Royalty information for secondary sales. |
| Token | ERC-721C creator-token transfer validator | A creator-definable transfer validation hook, discoverable by marketplaces. |
| Account | EIP-7702 delegation to Alchemy SemiModularAccount7702 | Email-onboarded embedded-signer EOAs become smart accounts at their existing address, so `ownerOf` never changes. |
| Account | ERC-4337 user operations with a paymaster policy and a server-side approval webhook | Holders pay no gas; the webhook approves only the calls the application expects. |
| Account | Scoped session keys (`wallet_createSession` permission grant) | One owner signature authorizes a key limited on chain to the single function pass links invoke, enabling one-tap actions. |
| Authorization | ERC-4361 challenge floor with a CAIP-19 token binding | Proof of control naming token, action, single-use nonce, expiration, verifier, and account. |
| Authorization | ERC-1271 | Signature verification for contract accounts. |
| Authorization | Fresh `ownerOf` read, fail closed | Entitlement checked at request time on every state-changing request; never a cached owner. |
| Apple delivery | Signed PKPass bundles (Pass Type ID certificate issued by Apple, WWDR G4 chain) | The pass artifact. |
| Apple delivery | PassKit web service protocol (device registration, serials since tag, latest pass, log) | Installed passes fetch updated content. |
| Apple delivery | APNs background push | Tells devices a pass changed. |
| Apple delivery | Relative date fields | Live countdowns rendered on device between pushes. |
| Google delivery | Google Wallet REST API (loyalty class and objects) | The pass class and one object per token, upserted by the server. |
| Google delivery | Thin Save to Google Wallet JWTs referencing upserted objects | Short, reliable save links. |
| Google delivery | Object PATCH, `addMessage`, `linksModuleData` | Content updates, notifications, and tappable action links. |
| Discovery and freshness | Gated manifest behind `passURI` | Acquisition URLs only for a proven owner. |
| Discovery and freshness | Capability URL rotation on transfer | Previous owners' links and downloads stop working. |
| Discovery and freshness | On-chain `PassUpdate` and `BatchPassUpdate` | Staleness signal for any pass distributor or indexer. |

## Deployment profile

- ERC-721 tokens on a public test network, live since July 2026. Holders onboard with an email address; their accounts use an embedded signer, and state-changing transactions are gas-sponsored.
- Each token carries one Apple Wallet pass and one Google Wallet pass. Pass content (status, countdown, balances) reflects on-chain state and changes several times a day.
- Its token contract, deployed on chain id 46630 at `0x96100112afec4a034270d96a133c8952e8c63f45`, implements `IERC721WalletPass`: `supportsInterface(0xef5f1e71)` returns `true`, and `passURI` reverts for unminted ids. Its server resolves `passURI` to a manifest. Earlier releases delivered the same passes without the on-chain interface.
- Acquisition URLs are also delivered in the mint response, the post-transfer claim response, and a receipt email.
- It documents itself as operating the gated configuration. Pass action links run in the capability configuration, bounded as described under [Authorization](#authorization-as-deployed).

## On-chain interface

**`passURI`.** Reverts for a nonexistent token, otherwise returns an owner-settable base followed by the decimal token id. The base encodes the chain and contract, in the form `<origin>/wallet-pass/eip155/<chainId>/<contract>/`, so one server can serve several collections and networks without ambiguity. `supportsInterface` returns `true` for `0xef5f1e71`.

**`PassUpdate`.** Emitted from the token's transfer hook, so mint, transfer, and burn are all covered without separate call sites. Most pass-rendered state lives in a separate application contract. Because the specification places the events on the token contract, the application contract asks the token contract to emit them through an emit-only signal function, callable only by the application contract, the owner, and registered signalers. Each action taken from a pass, and each prize or residual payment to a single token, emits `PassUpdate` for that token.

**`BatchPassUpdate`.** Emitted for collection-wide changes (the start or end of a round) over the full minted range, and once per reward distribution over the inclusive range from the lowest to the highest paid token id. Unpaid ids inside that range receive a redundant refresh, which is cheaper than one event per token.

**Signals never block state changes.** Every signal call is wrapped so that a failure to emit cannot revert the action or settlement that caused it.

**Passive state has no event.** State that changes with time rather than by transaction (a deadline lapsing) emits nothing. The pass covers it with a relative date field that the device counts down on its own.

**Gas.** Signaling adds about 4,100 gas per state-changing action and about 1,200 per mint.

**Push remains server-driven.** The server still triggers APNs pushes and Google Wallet updates from the state changes it observes. The events serve other pass distributors and indexers, which have no access to that server.

## Manifest endpoint

**Gated resolution.** An unauthenticated request to the `passURI` address returns `401` with a JSON body whose `error` is `proof_required` and whose `challenge` is the URI of the challenge endpoint for that token, and no acquisition URL. A request that proves control of the owning account returns `200` with the manifest (`formats.apple` a capability `.pkpass` URL, `formats.google` a Save to Google Wallet link, and `updatedAt`), sent with `Cache-Control: no-store`.

**Proof of control.** Either of two proofs is accepted. The first is an ERC-4361 challenge fetched from a `challenge` endpoint beneath the `passURI` address, signed, and returned in request headers. It follows the recommended serialization: the first resource is the CAIP-19 identifier of the token, the second is `urn:wallet-pass:action:acquire`, and the statement names the acquire action, with a single-use nonce, an expiration, the domain line, and the claimed account in the address line. The second is a session token from the embedded signer used by email-onboarded holders.

**Rotation at first claim.** When a proven owner is not the owner of record, the server rotates the per-pass secret before minting any acquisition URL. This is the gated configuration's rotation upon the new owner's first claim.

**No metadata mirror.** The optional `wallet_pass` property in token metadata is deliberately not served. `tokenURI` is public, so mirroring a gated manifest there would publish its capability URLs.

## Apple Wallet

**Signing.** Passes are signed with a Pass Type ID certificate issued by Apple, chained to the Apple WWDR G4 intermediate. The certificate is issued to an enrolled developer organization; Apple does not review individual passes or pass designs.

**PassKit web service.** The deployment serves the standard pass web service endpoints: device registration and unregistration, the list of serials updated since a tag, the latest pass for a serial (honoring `If-Modified-Since` with `304`), and the device log endpoint. Each pass carries its own authentication token, compared in constant time.

**Push.** When rendered state changes, the server sends an empty-payload APNs push (`apns-push-type: background`, priority 5, topic set to the Pass Type ID) over HTTP/2, authenticating with the pass certificate as the client certificate. The device then fetches the new pass from the web service. Replacing the runtime's default CA store with the WWDR certificate breaks the APNs TLS connection; add WWDR to the pass signing chain only.

**Live countdown without push.** Date fields with `isRelative` set are redrawn by the device as a live countdown, so a timer on the pass stays correct between pushes. `relevantDate` surfaces the pass on the lock screen at a chosen time.

**Back-of-pass action links.** Each state-changing action is a link on the back of the pass, and each link is a capability URL bound to the pass and the action. Field text can change between pushes, but the link set is stable for a given owner.

**`sharingProhibited`.** Setting it hides the share control in Wallet. It does not stop the `.pkpass` file from being forwarded by other means, so it does not change the bearer-artifact analysis.

**Superseded passes on transfer.** After a transfer is claimed, the previous owner's device is still registered with the old authentication token. The web service answers it with a keepsake pass marked as transferred, carrying no action links, instead of the current pass. The new owner receives a fresh pass under a rotated token. This is how the deployment meets the requirement that superseded passes not present themselves as current.

**Field limits.** Wallet renders at most four secondary and auxiliary fields combined and truncates long header labels. Layouts that exceed this lose fields without an error.

**Other surfaces.** On macOS, passes open and their links work, but push updates were not observed. A pass added on one device mirrors to the holder's other devices.

## Google Wallet

**Issuer and class approval.** The issuer account was approved, and the loyalty pass class was reviewed and approved by Google (`reviewStatus` of `approved` through the Wallet REST API). Until approval, saved passes carry a test-only marker.

**Issuer id.** The Wallet REST API requires the numeric issuer id. The alphanumeric merchant id shown elsewhere in the console is rejected, which surfaced as silently failing object writes.

**Thin save links.** A save link is a signed JWT (`typ: savetowallet`) with an `origins` list naming every origin that hosts the save button; a page origin outside that list is refused. Embedding the full class and object in the JWT produced links of about 2,400 characters, past the roughly 1,800-character practical limit, and adds failed intermittently with generic errors. The deployment instead upserts the object through the REST API and issues a thin JWT that references the object by id.

**Upsert and updates.** Objects are created with GET, then POST on 404, then PATCH when present. A `409` on POST means another request created the object concurrently; the correct response is to PATCH, not to skip, because the content being written may include rotated capability URLs. Later updates are PATCH writes guarded by a content hash. A change to structure alone (for example adding a module) must still force a write.

**Notifications.** `addMessage` on the object surfaces a notification for high-signal events. Routine updates are silent PATCH writes.

**Tappable links.** Google Wallet does not linkify text fields. The only tappable surface is `linksModuleData`, so action links live there.

**Images.** Image URLs are cached aggressively; changing the image requires a new URL. Hero images are wide, and a square image placed there is stretched.

## Authorization as deployed

- **Fresh read.** Every state-changing request (action taps, session key installation and revocation, pass link issuance, claims, challenge verification, and manifest resolution) reads `ownerOf` at request time. On failure it retries once after 250 ms, then refuses with a retryable `503` (`Retry-After: 5`). It never falls back to a cached or last-known-good owner; only read-only views use the cache. Making this strict also closed a path where a claim could proceed on the owner of record when the chain read failed.
- **Pass action links.** Holders onboard by email and are never prompted per action, so no per-action signature exists at tap time: the capability configuration. Each link is a capability URL bound to the pass and the action. A tap resolves the link, performs the fresh read, and submits the action with a session key the owner authorized once with a signature. The session key's authority is scoped on chain to the single state-changing function the pass exposes. The forwarding residual the specification discloses therefore stays bounded: a forwarded link can repeat that action for the owner, and cannot transfer, burn, or approve the token, change who may act for it, or reach any other function. The repetition is bounded on chain as well. Each care spends the care cost from the token's own account, and that account enforces a daily spend cap (20 cares per 24 hour window at the shipped configuration), so the most a forwarded link can do before the owner rotates it is spend that allowance on care, the one thing the account exists to spend on. "Cannot touch the token" therefore holds for ownership and entitlement; what the token's account holds is exposed only up to that cap.
- **Fallback.** When no usable session key exists, the link redirects to a page where the owner signs the action directly.
- **Rotation on request.** The owner can reset the pass links at any time from the account page. It is the transfer rotation with the owner unchanged: the per-pass secret rotates, every action link and pass download URL derived from it stops verifying, the previous Apple registration refreshes into a keepsake marked as reset, the Google object is patched with the rotated links, and fresh acquisition URLs are returned. Limited to one reset per pet per ten minutes. This is the remedy for a leaked link under an unchanged owner, which no transfer-driven rotation can provide.
- **Transfer.** A new owner claims with a signature over a server-issued single-use nonce. The claim, like a proven manifest request from a new owner, rotates the per-pass secret, which invalidates every action link and pass download URL derived from it and triggers the keepsake behavior described above.

## Lessons

1. **Pass download URLs must be capability URLs too.** An early build served the pass file at a path keyed only by the pass serial, and the serial was public through token metadata. Because the pass embeds already-signed action links, anyone could download any holder's pass and replay its links. This was found in internal review before real value was at stake, and there is no evidence it was exploited. The fix derives a download capability from the per-pass secret with an HMAC, verifies it in constant time, returns `404` on mismatch, rotates it with the secret on transfer, and makes serial-only routes fail closed.
2. **GET must be side-effect free.** Mail scanners, chat previews, and wallets prefetch links. An action link that acts on GET gets triggered by a crawler. The deployment answers GET with a page that submits the action by POST, and acts only on POST.
3. **Browser storage opened from a pass is ephemeral.** Links open in an in-app browser whose storage does not survive from one tap to the next, so a browser-local session key re-prompted on every action. Holding the scoped session key server-side fixed it.
4. **Numeric issuer id, not merchant id,** for the Google Wallet REST API.
5. **Respect field-count limits** on Apple passes, and put every Google link in `linksModuleData`.
6. **Treat a Google `409` as "exists, now PATCH".**
7. **Keep WWDR out of the runtime CA store** when connecting to APNs.
8. **Notification throttling must not swallow time-critical warnings.** Quiet-hour suppression is fine for routine updates and wrong for warnings whose deadline falls inside the quiet window.
