# ERC-8283 code migration: standalone Hardhat/Viem/TypeScript repo

## Context

ERC-8283 ("Clear Signing On-Chain Descriptors Registry") is being drafted in this
repo (`ERCS2`, branch `create-erc7730-onchain-registry`). Its full reference
implementation currently lives under `assets/erc-8283/`: the interface, the
reference contract, two libraries, vendored OpenZeppelin v5.0.0 sources, and a
dev-facing README walkthrough (ethers.js).

EIP convention — and this author's explicit preference — is that an ERC PR
should contain the ERC document text itself, at most an inline Solidity
interface code block, with any code in `assets/` being a stretch. The current
`assets/erc-8283/` folder holds a full working implementation plus a vendored
dependency tree, which is more than that.

A new repository, `onchain-clear-signing-erc7730-registry`
(`git@github.com:forshtat/onchain-clear-signing-erc7730-registry.git`, local
clone at `/Users/alexf/onchain-clear-signing-erc7730-registry`), is where real
development, testing, and iteration on the implementation will happen going
forward, using Hardhat, Viem, and TypeScript.

## Goals

1. Move the reference implementation, libraries, and vendored OZ dependency
   out of `ERCS2` into the new repo, replacing the vendored OZ copy with a real
   `@openzeppelin/contracts` npm dependency.
2. Stand up a working Hardhat 3 + `@nomicfoundation/hardhat-toolbox-viem` +
   TypeScript project in the new repo that compiles the contracts and runs a
   smoke test.
3. Trim `ERCS2`'s `assets/erc-8283/` down to just the normative interface
   file, and add a bare-declarations Solidity interface block directly into
   `ERCS/erc-8283.md` so the ERC document itself carries the interface without
   linking out for the essentials.
4. Push the new repo's initial commit(s) to its GitHub remote.

## Non-goals

- Full test coverage of `ClearSigningRegistry` (explicitly deferred — a
  minimal smoke test is enough for this pass).
- Any behavioral change to the contracts. This is a pure move + tooling setup;
  semantics are unchanged (only the OZ import paths change, from relative
  vendored paths to the npm package).
- Converting the ERC document's other existing inline code snippets (data
  model mapping block, individual function signature blocks in prose) — those
  stay as they are today.

## Design

### A. `ERCS2` changes

`assets/erc-8283/` after this change contains only:

- `IClearSigningRegistry.sol` (unchanged, byte-for-byte)

Deleted from `assets/erc-8283/`:

- `ClearSigningRegistry.sol`
- `ClearSigningRegistryConstants.sol`
- `RegistrationHashLib.sol`
- `UriFilterLib.sol`
- `openzeppelin/` (entire vendored tree)
- `README.md` (the ethers.js walkthrough — becomes the new repo's README)

`ERCS/erc-8283.md` changes:

- Under `### Interface`, immediately after the existing sentence "The full
  normative interface is provided in
  [IClearSigningRegistry.sol](../assets/erc-8283/IClearSigningRegistry.sol).",
  insert a fenced `solidity` code block containing only the bare function
  declarations of `IClearSigningRegistry` — no NatSpec comments, no struct/
  event/error definitions, no bodies. Struct types (`DescriptorInfo`,
  `RevocationEntry`, `ResolvedDescriptor`) are referenced by name only; they
  are already described elsewhere in the document (Data Model section and
  surrounding prose).
- Under `## Reference Implementation`, replace the bullet linking to the local
  `ClearSigningRegistry.sol` with a link to the new GitHub repo
  (`https://github.com/forshtat/onchain-clear-signing-erc7730-registry`) as
  the reference implementation's home. The `IClearSigningRegistry.sol` bullet
  stays, still pointing at the local file.

No other section of `ERCS/erc-8283.md` changes.

### B. New repo layout and tooling

```
onchain-clear-signing-erc7730-registry/
  contracts/
    IClearSigningRegistry.sol
    ClearSigningRegistry.sol
    ClearSigningRegistryConstants.sol
    RegistrationHashLib.sol
    UriFilterLib.sol
  test/
    ClearSigningRegistry.smoke.test.ts
  hardhat.config.ts
  package.json
  tsconfig.json
  .gitignore
  README.md
  LICENSE
```

- **Toolchain**: Hardhat 3.x (latest, currently 3.17.0) with
  `@nomicfoundation/hardhat-toolbox-viem` (currently 5.0.7, which pins
  `hardhat ^3.8.0` and `viem ^2.47.6`). This is Hardhat's current config
  shape: `hardhat.config.ts` exports a plain `HardhatUserConfig` object, and
  the toolbox wires up Viem clients and the native `node:test` runner.
- **Solidity version**: `0.8.24` (matching the existing `pragma solidity
  ^0.8.24;` across all contract files) — no reason to bump it as part of a
  pure move.
- **OpenZeppelin**: add `@openzeppelin/contracts` (^5.6.1) as a real npm
  dependency. Update the two imports in `ClearSigningRegistry.sol` from
  `./openzeppelin/contracts/utils/cryptography/SignatureChecker.sol` /
  `EIP712.sol` to `@openzeppelin/contracts/utils/cryptography/...`. The
  vendored files being replaced are stock OZ v5.0.0, and the installed
  version is a later 5.x, so this is an import-path change only — no API
  surface used by `ClearSigningRegistry.sol` changed across that range.
- **Package manager**: npm.
- **License**: `LICENSE` file at the repo root using CC0-1.0, matching every
  contract's `SPDX-License-Identifier: CC0-1.0` header.
- **README**: the walkthrough currently at `assets/erc-8283/README.md` moves
  here, with its code samples converted from ethers.js to Viem so the doc
  matches the toolchain actually used to develop and test the repo. Its
  content (roles, constants, call sequences) is otherwise preserved.

### C. Testing

One smoke test file, `test/ClearSigningRegistry.smoke.test.ts`, using
Hardhat's Viem test helpers (`hre.viem.deployContract`, a viem public/wallet
client) and the `node:test` runner:

- Deploy `ClearSigningRegistry`.
- As a self-attester (`msg.sender == attester`, so no EIP-712 signature
  needed), `publishMirrorLists` a URI list, then `createAttestations` for one
  descriptor referencing that MirrorList and one `AttestationIdentifier`.
- Call `resolveDescriptors` for that attester/context key ID/schema MAJOR and
  assert the returned `ResolvedDescriptor` matches (descriptor hash,
  attestation set ID, MirrorList URIs).

This proves the full toolchain — compile, deploy, call, assert — works
end-to-end. It is not meant to cover revocation, MirrorList updates, EIP-712
relayed signatures, or error paths; those are follow-up work.

### D. Git / push sequence

1. Initialize the new repo locally (`git init`, add the GitHub remote as
   `origin`) — confirmed the local folder is currently empty and not yet a
   git repository.
2. Commit the moved contracts, tooling, README, LICENSE with short, generic
   commit message(s) — no long explanatory bodies.
3. Verify `npm install && npm run compile && npm test` all succeed.
4. Push to `git@github.com:forshtat/onchain-clear-signing-erc7730-registry.git`.
5. Separately, commit the `ERCS2` changes (deletions under `assets/erc-8283/`
   + `ERCS/erc-8283.md` edits) on the current branch
   (`create-erc7730-onchain-registry`) with a short, conventional commit
   message. Do not push `ERCS2` unless asked.

## Open risks / things that could surprise us

- Hardhat 3's config/test-runner shape is a real departure from Hardhat 2
  (no more Mocha-by-default, ESM-flavored config). If toolbox defaults don't
  match some assumption made here, the implementation step may need small
  adjustments — that's expected and fine, this spec fixes intent/structure,
  not exact generated file contents.
- If `@openzeppelin/contracts` 5.6.1's `EIP712`/`SignatureChecker` API has
  drifted from 5.0.0 in some way relevant to `ClearSigningRegistry.sol`, the
  compile step will surface it immediately and it gets fixed as part of this
  same task (still just an import/compat fix, not a design change).
