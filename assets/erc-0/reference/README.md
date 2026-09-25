# Wallet Pass Extension for NFTs: Reference Implementation

Reference implementation for the draft ERC "Wallet Pass Extension for NFTs". The proposal lets an ERC-721 token advertise that it can be represented as a native mobile wallet pass (Apple Wallet, Google Wallet), defines the pass manifest clients fetch to acquire those passes, and specifies how state-changing actions reachable from a pass are authorized.

This code exists to teach the specification, not to ship a product. Everything is deliberately small and readable.

## Layout

| Spec section | Where it lives here |
| --- | --- |
| Contract interface (`IERC721WalletPass`, `0xef5f1e71`) | `contracts/src/IERC721WalletPass.sol` (interface verbatim), `contracts/src/ERC721WalletPass.sol` (minimal ERC-721 implementation) |
| `PassUpdate` / `BatchPassUpdate` events | `contracts/src/ERC721WalletPass.sol` (a mutable per-token level emits `PassUpdate`; `refreshPasses` emits an inclusive `BatchPassUpdate`), tests in `contracts/test/ERC721WalletPass.t.sol` |
| Pass manifest | `server/src/passStore.ts` (manifest shape and capability mapping), `GET /manifest/:tokenId` in `server/src/app.ts` |
| Acquisition URLs (capability URLs, rotation) | `server/src/passStore.ts` (`rotateOnTransfer`), `GET /passes/:format/:token` |
| Acquisition URLs (the public and gated configurations) and Gated acquisition | `server/src/config.ts` (`ManifestMode`), gated proof check and first-claim rotation in `server/src/app.ts` |
| Authorization of pass-reachable actions (challenge floor) | `server/src/siwe.ts` (ERC-4361 message construction), `server/src/nonceStore.ts` (single-use nonces with expiry), `server/src/authorize.ts` (field-by-field verification plus the fresh `ownerOf` read), `POST /challenge` and `POST /action` |
| Authorization of pass-reachable actions, check (2) (the fresh ownership read) | `server/src/chainReader.ts` (injectable `ChainReader`; tests inject a fake, production uses viem against any RPC) |
| The capability configuration (action links standing in for check (1)) | `server/src/capability.ts` (link resolution and the unconditional fresh read, condition by condition), `server/src/passStore.ts` (`actionLinks`, `resolveActionCapability`, `rotateOnOwnerRequest`), `GET` and `POST /links/:capability` and `POST /manifest/:tokenId/rotate` in `server/src/app.ts`, tests in `server/test/capability.test.ts` |
| Example challenge (the specification's worked example) | asserted shape in `server/test/challenge.test.ts` |

## Running the tests

Contracts (Foundry). The two library dependencies are not vendored here; install them at the tested versions first:

```shell
cd contracts
forge install foundry-rs/forge-std@v1.9.4 --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-git
forge test
```

Server (Node.js 22 or later, vitest):

```shell
cd server
npm install
npx vitest run
```

The server suite exercises the floor property by property: replayed nonce rejected, expired challenge rejected, wrong verifier domain rejected, proof for one action or token refused for another, a proof for a chain or contract other than the configured one refused, an acquire proof refused as an action, a malformed signature refused without a crash, ownership transfer between challenge and action refused by the fresh read, a token with no owner refused as not the owner while a failed read is answered as retryable (503 with Retry-After) and never from a cached owner, gated manifest refused without a control proof (and every gated 401 points at the challenge endpoint), acquisition URLs rotated on a new owner's first claim and left alone on a repeat claim, rotated capability URLs stop resolving, and a full happy path in which a runtime-generated key signs a real challenge. The capability suite puts the weaker configuration on the same footing, one test per condition the standard states: a link bound to one action refused for another, a rotated link refused (rotation on transfer, and on the owner's signed request through the rotate route), a sold token behind a still-live link refused by the fresh read, a failed read answered as retryable, GET on a link side-effect free, no action links in the public configuration, and, asserted on purpose as the disclosed residual, a forwarded link acting under an unchanged owner.

## Reference simplifications

This is a single-process reference. The nonce store, pass store, and capability mappings are in memory; a production deployment swaps in persistent storage.

Pass generation itself (PKPass signing with Apple certificates, Google Wallet object and JWT minting, platform push) is out of the specification's scope, so acquisition URLs here resolve to JSON stubs that demonstrate the capability mapping and its rotation, not `application/vnd.apple.pkpass` content. The [deployment notes](../implementation-notes.md) cover what a production deployment adds.

Capability rotation has two operational triggers here: the gated manifest path rotates on a new owner's first claim (`rotateOnTransfer`), as Gated acquisition requires, and the rotate route rotates on the owner's signed request (`rotateOnOwnerRequest`). A production deployment adds the third, a transfer watcher, so that rotation also happens when the implementation observes the transfer before the new owner claims. Action links are opaque capabilities that resolve to a stub action here; a production pass generator embeds them in the signed pass. Key management for user accounts is out of scope; tests generate throwaway keys at runtime.

## License

CC0 1.0 Universal. See `LICENSE`.
