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
| Public vs gated configurations | `server/src/config.ts` (`ManifestMode`), gated proof check in `server/src/app.ts` |
| Authorization of pass-reachable actions (challenge floor) | `server/src/siwe.ts` (ERC-4361 message construction), `server/src/nonceStore.ts` (single-use nonces with expiry), `server/src/authorize.ts` (field-by-field verification plus the fresh `ownerOf` read), `POST /challenge` and `POST /action` |
| Fresh ownership read | `server/src/chainReader.ts` (injectable `ChainReader`; tests inject a fake, production uses viem against any RPC) |
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

The server suite exercises the floor property by property: replayed nonce rejected, expired challenge rejected, wrong verifier domain rejected, proof for one action or token refused for another, ownership transfer between challenge and action refused by the fresh read, gated manifest refused without a control proof, rotated capability URLs stop resolving, and a full happy path in which a runtime-generated key signs a real challenge.

## Reference simplifications

This is a single-process reference. The nonce store, pass store, and capability mappings are in memory; a production deployment swaps in persistent storage.

Pass generation itself (PKPass signing with Apple certificates, Google Wallet object and JWT minting, platform push) is out of the specification's scope, so acquisition URLs here resolve to JSON stubs that demonstrate the capability mapping and its rotation, not `application/vnd.apple.pkpass` content. The [deployment notes](../implementation-notes.md) cover what a production deployment adds.

Capability rotation is exposed as a function (`rotateOnTransfer`) and exercised in tests, but nothing triggers it operationally; production wires it to a transfer watcher or a claim flow. Key management for user accounts is out of scope; tests generate throwaway keys at runtime.

## License

CC0 1.0 Universal. See `LICENSE`.
