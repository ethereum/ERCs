# Deployment Notes (non-normative)

These notes describe how one production deployment delivered NFT-bound wallet passes on Apple Wallet and Google Wallet, and how it applied the authorization requirements of this proposal. Nothing here is normative. The specification defines discovery and authorization; everything below sits in the delivery pipeline the specification leaves out of scope, and is recorded because every implementer meets the same platform constraints.

## Deployment profile

- ERC-721 tokens on a public test network, live since July 2026. Holders onboard with an email address; their accounts use an embedded signer, and state-changing transactions are gas-sponsored.
- Each token carries one Apple Wallet pass and one Google Wallet pass. Pass content (status, countdown, balances) reflects on-chain state and changes several times a day.
- Acquisition URLs are delivered in the mint response, the post-transfer claim response, and a receipt email. The deployment predates the on-chain interface: its token contract does not implement `passURI`, and push updates are driven by server-observed state changes rather than `PassUpdate` events. The [reference implementation](./reference/README.md) covers the on-chain half.
- It operates the gated configuration. Pass action links run in the capability configuration, bounded as described under [Authorization](#authorization-as-deployed).

## Apple Wallet

**Signing.** Passes are signed with an Apple-issued Pass Type ID certificate chained to the Apple WWDR G4 intermediate. Apple has no review step for passes; possession of the signing certificate is the only gate.

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

- **Fresh read.** Every state-changing request reads `ownerOf` at request time, bypassing the ownership cache that read-only views use. If the RPC read fails, the guard falls back to the last successful read, and fails closed when no read is available while real value is at stake.
- **Pass action links.** Holders onboard by email and are never prompted per action, so no per-action signature exists at tap time: the capability configuration. Each link is a capability URL bound to the pass and the action. A tap resolves the link, performs the fresh read, and submits the action with a session key the owner authorized once with a signature. The session key's authority is scoped on chain to the single state-changing function the pass exposes. The forwarding residual the specification discloses therefore stays bounded: a forwarded link can repeat that action for the owner, and cannot transfer the token or reach any other function.
- **Fallback.** When no usable session key exists, the link redirects to a page where the owner signs the action directly.
- **Transfer.** A new owner claims with a signature over a server-issued single-use nonce. The claim rotates the per-pass secret, which invalidates every action link and pass download URL derived from it and triggers the keepsake behavior described above.

## Lessons

1. **Pass download URLs must be capability URLs too.** An early build served the pass file at a path keyed only by the pass serial, and the serial was public through token metadata. Because the pass embeds already-signed action links, anyone could download any holder's pass and replay its links. This was found in internal review before real value was at stake, and there is no evidence it was exploited. The fix derives a download capability from the per-pass secret with an HMAC, verifies it in constant time, returns `404` on mismatch, rotates it with the secret on transfer, and makes serial-only routes fail closed.
2. **GET must be side-effect free.** Mail scanners, chat previews, and wallets prefetch links. An action link that acts on GET gets triggered by a crawler. The deployment answers GET with a page that submits the action by POST, and acts only on POST.
3. **Browser storage opened from a pass is ephemeral.** Links open in an in-app browser whose storage does not survive from one tap to the next, so a browser-local session key re-prompted on every action. Holding the scoped session key server-side fixed it.
4. **Numeric issuer id, not merchant id,** for the Google Wallet REST API.
5. **Respect field-count limits** on Apple passes, and put every Google link in `linksModuleData`.
6. **Treat a Google `409` as "exists, now PATCH".**
7. **Keep WWDR out of the runtime CA store** when connecting to APNs.
8. **Notification throttling must not swallow time-critical warnings.** Quiet-hour suppression is fine for routine updates and wrong for warnings whose deadline falls inside the quiet window.

## Screenshots

Screenshots from the current test network season are tracked in [`screenshots/`](./screenshots/README.md).
