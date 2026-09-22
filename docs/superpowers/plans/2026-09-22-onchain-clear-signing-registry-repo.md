# ERC-8283 Code Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the ERC-8283 reference implementation out of `ERCS2` into a standalone Hardhat + Viem + TypeScript repo that compiles and has a passing smoke test, then trim `ERCS2` down to the normative interface plus a bare-declarations code block in the ERC document.

**Architecture:** A single new repo (`onchain-clear-signing-erc7730-registry`) holds the contracts, a real `@openzeppelin/contracts` dependency (replacing the vendored copy), Hardhat 3 tooling, and a Viem-based smoke test. `ERCS2` keeps only `IClearSigningRegistry.sol` under `assets/erc-8283/` and gains an inline bare interface block in `ERCS/erc-8283.md`; everything else under `assets/erc-8283/` is deleted.

**Tech Stack:** Hardhat 3.17.0, `@nomicfoundation/hardhat-toolbox-viem` 5.0.7 (bundles Viem 2.x, the `node:test` runner, Ignition, etc.), TypeScript ~6.0.3, Solidity 0.8.24 (evmVersion `cancun`), `@openzeppelin/contracts` ^5.6.1, npm.

**Spec:** `docs/superpowers/specs/2026-09-22-onchain-clear-signing-registry-repo-design.md`

## Global Constraints

- Package manager is npm (not pnpm/yarn), per the approved design.
- New repo's Solidity compiler is exactly `0.8.24` (matches every contract's `pragma solidity ^0.8.24;`) with `evmVersion: "cancun"` set on **every** solidity profile — OpenZeppelin 5.6.1's `Bytes.sol`/`SignatureChecker.sol` use the `mcopy` opcode (Cancun+); omitting `evmVersion` leaves solc's pre-Cancun default and compilation fails with `DeclarationError: Function "mcopy" not found.` (verified locally).
- `@openzeppelin/contracts` is added as a real npm dependency at `^5.6.1`; the two vendored imports in `ClearSigningRegistry.sol` change from `./openzeppelin/contracts/...` to `@openzeppelin/contracts/...` and nothing else in that file changes.
- New repo's `hardhat-toolbox-viem` peers must all be installed explicitly as devDependencies (the toolbox package itself declares zero hard `dependencies` — everything is a peer) at exactly these versions, confirmed to install and load together: `@nomicfoundation/hardhat-ignition@^3.1.8`, `@nomicfoundation/hardhat-ignition-viem@^3.1.6`, `@nomicfoundation/hardhat-keystore@^3.1.0`, `@nomicfoundation/hardhat-network-helpers@^3.0.11`, `@nomicfoundation/hardhat-node-test-runner@^3.1.0`, `@nomicfoundation/hardhat-viem@^3.0.9`, `@nomicfoundation/hardhat-viem-assertions@^3.1.3`, `@nomicfoundation/hardhat-verify@^3.1.0`, `@nomicfoundation/ignition-core@^3.1.9`.
- Test scope for this pass is a single smoke test (deploy + one happy-path registration + resolve) — not full coverage. Do not add more tests than that in this plan.
- Commit messages in the new repo: short and generic (e.g. "Project scaffold", "Add smoke test"), no long explanatory bodies. Push the new repo to `git@github.com:forshtat/onchain-clear-signing-erc7730-registry.git` on branch `main` once it compiles and tests pass.
- `ERCS2` changes are committed on the current branch (`create-erc7730-onchain-registry`) but **not pushed**.

## Review Focus

- `evmVersion: "cancun"` must be set on both the `default` and `production` solidity profiles in `hardhat.config.ts` — a profile missing it silently reverts to a pre-Cancun target and breaks the `mcopy`-dependent OpenZeppelin compile.
- The bare-declarations interface block added to `ERCS/erc-8283.md` must list exactly the same functions, in the same order, with the same signatures as `assets/erc-8283/IClearSigningRegistry.sol` — nothing enforces the two stay in sync going forward.
- Deleting `assets/erc-8283/{ClearSigningRegistry.sol,ClearSigningRegistryConstants.sol,RegistrationHashLib.sol,UriFilterLib.sol,openzeppelin/,README.md}` must not leave any remaining link to those paths anywhere in `ERCS/erc-8283.md` (or elsewhere in the repo).
- The new repo's smoke test only covers the happy path (self-attester, single descriptor, `publishMirrorLists` → `createAttestations` → `resolveDescriptors`) — a green `npm test` says nothing about revocation, relayed EIP-712 signatures, or any error/revert path.
- Only the new repo gets pushed to its GitHub remote. The `ERCS2` branch changes must stay local/committed-only.

---

### Task 1: New repo scaffold, contracts, and a clean compile

**Files:**
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/package.json`
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/tsconfig.json`
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/hardhat.config.ts`
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/.gitignore`
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/LICENSE`
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/contracts/IClearSigningRegistry.sol` (copied from `/Users/alexf/ERCS2/assets/erc-8283/IClearSigningRegistry.sol`, byte-for-byte)
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/contracts/ClearSigningRegistryConstants.sol` (copied as-is)
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/contracts/UriFilterLib.sol` (copied as-is)
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/contracts/RegistrationHashLib.sol` (copied as-is)
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/contracts/ClearSigningRegistry.sol` (copied, then two import lines edited)

**Interfaces:**
- Produces: a compiled Hardhat project at `/Users/alexf/onchain-clear-signing-erc7730-registry` whose `contracts/ClearSigningRegistry.sol` exposes the `ClearSigningRegistry` contract (constructor takes no arguments) implementing `IClearSigningRegistry`. Task 2 deploys it by name via `viem.deployContract("ClearSigningRegistry")`.

- [ ] **Step 1: Initialize git and the npm project**

```bash
mkdir -p /Users/alexf/onchain-clear-signing-erc7730-registry
cd /Users/alexf/onchain-clear-signing-erc7730-registry
git init -b main
git remote add origin git@github.com:forshtat/onchain-clear-signing-erc7730-registry.git
```

- [ ] **Step 2: Write `package.json`**

```json
{
  "name": "onchain-clear-signing-erc7730-registry",
  "private": true,
  "version": "0.0.1",
  "description": "On-chain registry for ERC-7730 Clear Signing descriptors (ERC-8283 reference implementation)",
  "license": "CC0-1.0",
  "type": "module",
  "scripts": {
    "compile": "hardhat compile",
    "test": "hardhat test",
    "clean": "hardhat clean"
  },
  "dependencies": {
    "@openzeppelin/contracts": "^5.6.1"
  },
  "devDependencies": {
    "hardhat": "^3.17.0",
    "@nomicfoundation/hardhat-toolbox-viem": "^5.0.7",
    "@nomicfoundation/hardhat-ignition": "^3.1.8",
    "@nomicfoundation/hardhat-ignition-viem": "^3.1.6",
    "@nomicfoundation/hardhat-keystore": "^3.1.0",
    "@nomicfoundation/hardhat-network-helpers": "^3.0.11",
    "@nomicfoundation/hardhat-node-test-runner": "^3.1.0",
    "@nomicfoundation/hardhat-viem": "^3.0.9",
    "@nomicfoundation/hardhat-viem-assertions": "^3.1.3",
    "@nomicfoundation/hardhat-verify": "^3.1.0",
    "@nomicfoundation/ignition-core": "^3.1.9",
    "@types/node": "^22.8.5",
    "typescript": "~6.0.3",
    "viem": "^2.47.6"
  }
}
```

- [ ] **Step 3: Write `tsconfig.json`**

```json
{
  "compilerOptions": {
    "lib": ["es2023"],
    "module": "node20",
    "target": "es2023",
    "skipLibCheck": true,
    "outDir": "dist",
    "types": ["node"],
    "verbatimModuleSyntax": true
  }
}
```

- [ ] **Step 4: Write `hardhat.config.ts`**

```typescript
import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { defineConfig } from "hardhat/config";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.24",
        settings: {
          evmVersion: "cancun",
        },
      },
      production: {
        version: "0.8.24",
        settings: {
          evmVersion: "cancun",
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
  },
});
```

- [ ] **Step 5: Write `.gitignore`**

```
# Node modules
/node_modules

# Compilation output
/dist

# Hardhat Build Artifacts
/artifacts

# Hardhat compilation (v2) support directory
/cache

# Typechain output
/types

# Environment files
.env
.env.*
!.env.example

# Hardhat coverage reports
/coverage
```

- [ ] **Step 6: Write `LICENSE`** (CC0-1.0, matching every contract's `SPDX-License-Identifier: CC0-1.0` header)

```
Creative Commons Legal Code

CC0 1.0 Universal

    CREATIVE COMMONS CORPORATION IS NOT A LAW FIRM AND DOES NOT PROVIDE
    LEGAL SERVICES. DISTRIBUTION OF THIS DOCUMENT DOES NOT CREATE AN
    ATTORNEY-CLIENT RELATIONSHIP. CREATIVE COMMONS PROVIDES THIS
    INFORMATION ON AN "AS-IS" BASIS. CREATIVE COMMONS MAKES NO WARRANTIES
    REGARDING THE USE OF THIS DOCUMENT OR THE INFORMATION OR WORKS
    PROVIDED HEREUNDER, AND DISCLAIMS LIABILITY FOR DAMAGES RESULTING FROM
    THE USE OF THIS DOCUMENT OR THE INFORMATION OR WORKS PROVIDED
    HEREUNDER.

Statement of Purpose

The laws of most jurisdictions throughout the world automatically confer
exclusive Copyright and Related Rights (defined below) upon the creator
and subsequent owner(s) (each and all, an "owner") of an original work of
authorship and/or a database (each, a "Work").

Certain owners wish to permanently relinquish those rights to a Work for
the purpose of contributing to a commons of creative, cultural and
scientific works ("Commons") that the public can reliably and without fear
of later claims of infringement build upon, modify, incorporate in other
works, reuse and redistribute as freely as possible in any form whatsoever
and for any purposes, including without limitation commercial purposes.
These owners may contribute to the Commons to promote the ideal of a free
culture and the further production of creative, cultural and scientific
works, or to gain reputation or greater distribution for their Work in
part through the use and efforts of others.

For these and/or other purposes and motivations, and without any
expectation of additional consideration or compensation, the person
associating CC0 with a Work (the "Affirmer"), to the extent that he or she
is an owner of Copyright and Related Rights in the Work, voluntarily
elects to apply CC0 to the Work and publicly distribute the Work under its
terms, with knowledge of his or her Copyright and Related Rights in the
Work and the meaning and intended legal effect of CC0 on those rights.

1. Copyright and Related Rights. A Work made available under CC0 may be
protected by copyright and related or neighboring rights ("Copyright and
Related Rights"). Copyright and Related Rights include, but are not
limited to, the following:

  i. the right to reproduce, adapt, distribute, perform, display,
     communicate, and translate a Work;
 ii. moral rights retained by the original author(s) and/or performer(s);
iii. publicity and privacy rights pertaining to a person's image or
     likeness depicted in a Work;
 iv. rights protecting against unfair competition in regards to a Work,
     subject to the limitations in paragraph 4(a), below;
  v. rights protecting the extraction, dissemination, use and reuse of
     data in a Work;
 vi. database rights (such as those arising under Directive 96/9/EC of the
     European Parliament and of the Council of 11 March 1996 on the legal
     protection of databases, and under any national implementation
     thereof, including any amended or successor version of such
     directive); and
vii. other similar, equivalent or corresponding rights throughout the
     world based on applicable law or treaty, and any national
     implementations thereof.

2. Waiver. To the greatest extent permitted by, but not in contravention
of, applicable law, Affirmer hereby overtly, fully, permanently,
irrevocably and unconditionally waives, abandons, and surrenders all of
Affirmer's Copyright and Related Rights and associated claims and causes
of action, whether now known or unknown (including existing as well as
future claims and causes of action), in the Work (i) in all territories
worldwide, (ii) for the maximum duration provided by applicable law or
treaty (including future time extensions), (iii) in any current or future
medium and for any number of copies, and (iv) for any purpose whatsoever,
including without limitation commercial, advertising or promotional
purposes (the "Waiver"). Affirmer makes the Waiver for the benefit of each
member of the public at large and to the detriment of Affirmer's heirs and
successors, fully intending that such Waiver shall not be subject to
revocation, rescission, cancellation, termination, or any other legal or
equitable action to disrupt the quiet enjoyment of the Work by the public
as contemplated by Affirmer's express Statement of Purpose.

3. Public License Fallback. Should any part of the Waiver for any reason
be judged legally invalid or ineffective under applicable law, then the
Waiver shall be preserved to the maximum extent permitted taking into
account Affirmer's express Statement of Purpose. In addition, to the
extent the Waiver is so judged Affirmer hereby grants to each affected
person a royalty-free, non transferable, non sublicensable, non exclusive,
irrevocable and unconditional license to exercise Affirmer's Copyright and
Related Rights in the Work (i) in all territories worldwide, (ii) for the
maximum duration provided by applicable law or treaty (including future
time extensions), (iii) in any current or future medium and for any number
of copies, and (iv) for any purpose whatsoever, including without
limitation commercial, advertising or promotional purposes (the
"License"). The License shall be deemed effective as of the date CC0 was
applied by Affirmer to the Work. Should any part of the License for any
reason be judged legally invalid or ineffective under applicable law, such
partial invalidity or ineffectiveness shall not invalidate the remainder
of the License, and in such case Affirmer hereby affirms that he or she
will not (i) exercise any of his or her remaining Copyright and Related
Rights in the Work or (ii) assert any associated claims and causes of
action with respect to the Work, in either case contrary to Affirmer's
express Statement of Purpose.

4. Limitations and Disclaimers.

 a. No trademark or patent rights held by Affirmer are waived, abandoned,
    surrendered, licensed or otherwise affected by this document.
 b. Affirmer offers the Work as-is and makes no representations or
    warranties of any kind concerning the Work, express, implied,
    statutory or otherwise, including without limitation warranties of
    title, merchantability, fitness for a particular purpose, non
    infringement, or the absence of latent or other defects, accuracy, or
    the present or absence of errors, whether or not discoverable, all to
    the greatest extent permissible under applicable law.
 c. Affirmer disclaims responsibility for clearing rights of other persons
    that may apply to the Work or any use thereof, including without
    limitation any person's Copyright and Related Rights in the Work.
    Further, Affirmer disclaims responsibility for obtaining any necessary
    consents, permissions or other rights required for any use of the
    Work.
 d. Affirmer understands and acknowledges that Creative Commons is not a
    party to this document and has no duty or obligation with respect to
    this CC0 or use of the Work.
```

- [ ] **Step 7: Install dependencies**

```bash
cd /Users/alexf/onchain-clear-signing-erc7730-registry
npm install
```

Expected: installs cleanly (no unmet peer dependency errors for `@nomicfoundation/hardhat-toolbox-viem`).

- [ ] **Step 8: Copy the four dependency-free contract files as-is**

```bash
cp /Users/alexf/ERCS2/assets/erc-8283/IClearSigningRegistry.sol \
   /Users/alexf/ERCS2/assets/erc-8283/ClearSigningRegistryConstants.sol \
   /Users/alexf/ERCS2/assets/erc-8283/UriFilterLib.sol \
   /Users/alexf/ERCS2/assets/erc-8283/RegistrationHashLib.sol \
   /Users/alexf/onchain-clear-signing-erc7730-registry/contracts/
```

- [ ] **Step 9: Copy `ClearSigningRegistry.sol` and repoint its OpenZeppelin imports**

```bash
cp /Users/alexf/ERCS2/assets/erc-8283/ClearSigningRegistry.sol \
   /Users/alexf/onchain-clear-signing-erc7730-registry/contracts/ClearSigningRegistry.sol
```

Then edit `/Users/alexf/onchain-clear-signing-erc7730-registry/contracts/ClearSigningRegistry.sol`, changing only these two lines:

```solidity
import "./openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "./openzeppelin/contracts/utils/cryptography/EIP712.sol";
```

to:

```solidity
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
```

No other line in the file changes.

- [ ] **Step 10: Compile and verify**

```bash
cd /Users/alexf/onchain-clear-signing-erc7730-registry
npx hardhat compile
```

Expected: `Compiled 5 Solidity files with solc 0.8.24 (evm target: cancun)` — no errors, no `mcopy` `DeclarationError`.

- [ ] **Step 11: Commit**

```bash
cd /Users/alexf/onchain-clear-signing-erc7730-registry
git add package.json tsconfig.json hardhat.config.ts .gitignore LICENSE contracts
git commit -m "Project scaffold"
```

---

### Task 2: Smoke test

**Files:**
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/test/ClearSigningRegistry.smoke.test.ts`

**Interfaces:**
- Consumes: `ClearSigningRegistry` from Task 1 — constructor `()`, and (from `IClearSigningRegistry`) `publishMirrorLists(string[][])`, `createAttestations(address,DescriptorInfo[],bytes32,bytes32,bytes)`, `resolveDescriptors(address[],bytes32[],uint256[],bytes32[],string[]) view returns (ResolvedDescriptor[])`, where `DescriptorInfo = { bytes32 descriptorHash, uint256 descriptorSchemaMajor, bytes32[] contextKeyIds, AttestationIdentifier[] attestationIds }`, `AttestationIdentifier = { bytes32 attestationId, bytes32 attestationFormatId }`, and `ResolvedDescriptor` includes `descriptorHash`, `attestationSetId`, `descriptorMirrorListUris`, `attestationMirrorListUris`, `attestations[]` (each with `attestationId`).

- [ ] **Step 1: Write the test**

```typescript
import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { encodeAbiParameters, keccak256 } from "viem";

describe("ClearSigningRegistry smoke test", async function () {
  const { viem } = await network.create();

  it("registers a descriptor as a self-attester and resolves it back", async function () {
    const [attester] = await viem.getWalletClients();
    const registry = await viem.deployContract("ClearSigningRegistry");

    const descriptorUris = ["ipfs://descriptor"];
    const attestationUris = ["ipfs://attestation"];
    await registry.write.publishMirrorLists([[descriptorUris, attestationUris]]);

    const descriptorMirrorListId = keccak256(
      encodeAbiParameters([{ type: "string[]" }], [descriptorUris]),
    );
    const attestationMirrorListId = keccak256(
      encodeAbiParameters([{ type: "string[]" }], [attestationUris]),
    );

    const contextKeyId = keccak256(encodeAbiParameters([{ type: "string" }], ["ctx"]));
    const attestationId = keccak256(encodeAbiParameters([{ type: "string" }], ["att"]));
    const attestationFormatId = keccak256(
      encodeAbiParameters([{ type: "string" }], ["erc7730.attestation.eas.offchain"]),
    );
    const descriptorHash = keccak256(encodeAbiParameters([{ type: "string" }], ["descriptor"]));

    await registry.write.createAttestations([
      attester.account.address,
      [
        {
          descriptorHash,
          descriptorSchemaMajor: 1n,
          contextKeyIds: [contextKeyId],
          attestationIds: [{ attestationId, attestationFormatId }],
        },
      ],
      descriptorMirrorListId,
      attestationMirrorListId,
      "0x",
    ]);

    const [resolved] = await registry.read.resolveDescriptors([
      [attester.account.address],
      [contextKeyId],
      [1n],
      [],
      [],
    ]);

    assert.equal(resolved.descriptorHash, descriptorHash);
    assert.equal(resolved.attestationSetId, attestationId);
    assert.deepEqual(resolved.descriptorMirrorListUris, descriptorUris);
    assert.deepEqual(resolved.attestationMirrorListUris, attestationUris);
    assert.equal(resolved.attestations.length, 1);
    assert.equal(resolved.attestations[0].attestationId, attestationId);
  });
});
```

- [ ] **Step 2: Run it**

```bash
cd /Users/alexf/onchain-clear-signing-erc7730-registry
npx hardhat test
```

Expected: `1 passing` — `ClearSigningRegistry smoke test ✔ registers a descriptor as a self-attester and resolves it back`.

- [ ] **Step 3: Commit**

```bash
cd /Users/alexf/onchain-clear-signing-erc7730-registry
git add test
git commit -m "Add smoke test"
```

---

### Task 3: README walkthrough (Viem)

**Files:**
- Create: `/Users/alexf/onchain-clear-signing-erc7730-registry/README.md`

**Interfaces:**
- Consumes: nothing programmatically (documentation only); illustrates calls against the same `IClearSigningRegistry` surface as Task 2.

- [ ] **Step 1: Write `README.md`**

```markdown
# `IClearSigningRegistry` walkthrough

**Attester Signer Entity** (the attester)

**IPFS Mirror Operator** (an independent mirror operator)

**Relayer Service** (relays authorized actions on the attester's behalf)

**Wallet Client** (the user)

## Constants

```TypeScript
import {
  createPublicClient,
  createWalletClient,
  http,
  getContract,
  keccak256,
  toHex,
  encodeAbiParameters,
  parseEventLogs,
  type Address,
  type Hex,
} from "viem";
import { mainnet } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { IClearSigningRegistryAbi } from "./abi"; // the compiled contract's ABI JSON

const REGISTRY_ADDRESS: Address = "0xREGISTRY0000000000000000000000000000000";

const publicClient = createPublicClient({ chain: mainnet, transport: http() });

const attesterAccount = privateKeyToAccount(ATTESTER_PRIVATE_KEY);
const relayerAccount = privateKeyToAccount(RELAYER_PRIVATE_KEY);
const ipfsPinnerAccount = privateKeyToAccount(PINNING_PRIVATE_KEY); // independent IPFS mirror operator

const attesterClient = createWalletClient({ account: attesterAccount, chain: mainnet, transport: http() });
const relayerClient = createWalletClient({ account: relayerAccount, chain: mainnet, transport: http() });
const ipfsPinnerClient = createWalletClient({ account: ipfsPinnerAccount, chain: mainnet, transport: http() });

// Binds the registry ABI to a given wallet client, so every call below reads
// as "<role> calls <function>" the same way `registry.connect(signer)` did.
function registryAs(walletClient: typeof attesterClient) {
  return getContract({ address: REGISTRY_ADDRESS, abi: IClearSigningRegistryAbi, client: { public: publicClient, wallet: walletClient } });
}
const registryRead = getContract({ address: REGISTRY_ADDRESS, abi: IClearSigningRegistryAbi, client: publicClient });

const mainnetChainId = 1n;
const optimismChainId = 10n;

const ATTESTATION_FORMAT_EAS_OFFCHAIN = keccak256(toHex("erc7730.attestation.eas.offchain"));

const eip712Domain = { name: "ClearSigningRegistry", version: "1", chainId: 1, verifyingContract: REGISTRY_ADDRESS } as const;
```


```TypeScript
function deriveContextKeyId(chainId: bigint, contractAddress: Address): Hex {
  const CONTEXT_TAG_CONTRACT = keccak256(toHex("erc7730.context.contract"));
  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "uint256" }, { type: "address" }],
      [CONTEXT_TAG_CONTRACT, chainId, contractAddress],
    ),
  );
}

function deriveFactoryContextKeyId(chainId: bigint, factoryAddress: Address, deployEventSignature: string): Hex {
  const CONTEXT_TAG_FACTORY = keccak256(toHex("erc7730.context.factory"));
  const deployEventTopic = keccak256(toHex(deployEventSignature)); // topic0 = hash of the event signature string
  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "uint256" }, { type: "address" }, { type: "bytes32" }],
      [CONTEXT_TAG_FACTORY, chainId, factoryAddress, deployEventTopic],
    ),
  );
}

function deriveEip712DeploymentContextKeyId(chainId: bigint, verifyingContract: Address): Hex {
  const CONTEXT_TAG_EIP712_DEP = keccak256(toHex("erc7730.context.eip712.deployment"));
  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "uint256" }, { type: "address" }],
      [CONTEXT_TAG_EIP712_DEP, chainId, verifyingContract],
    ),
  );
}

function deriveDomainSeparatorContextKeyId(domainSeparator: Hex): Hex {
  const CONTEXT_TAG_EIP712_DS = keccak256(toHex("erc7730.context.eip712.domainseparator"));
  return keccak256(
    encodeAbiParameters([{ type: "bytes32" }, { type: "bytes32" }], [CONTEXT_TAG_EIP712_DS, domainSeparator]),
  );
}
```

## 1. `publishMirrorLists` — **IPFS Mirror Operator** publishes retrieval URIs

Descriptor JSON and signed attestation blobs are published the same way — the registry never distinguishes the two, only the caller's later references do. A single list itself may carry several URIs — redundant mirrors of the exact same content. `createAttestations` below only ever takes an *already-published* MirrorList id — it has no way to publish one itself — so both lists it will need are published here first, in one batch:

```TypeScript
const releaseDescriptorIndexUris = [
  "ipfs://bafybeigd.../vault-and-staking-descriptors-index.json",
  "ar://vault-and-staking-descriptors-index-mirror",
];
const releaseAttestationIndexUris = ["ipfs://bafybeigd.../release-attestations-index.json"];

const publishHash = await registryAs(ipfsPinnerClient).write.publishMirrorLists([[releaseDescriptorIndexUris, releaseAttestationIndexUris]]);
const publishReceipt = await publicClient.waitForTransactionReceipt({ hash: publishHash });
const [
  { args: { mirrorListId: descriptorMirrorListId } },
  { args: { mirrorListId: attestationMirrorListId } },
] = parseEventLogs({ abi: IClearSigningRegistryAbi, eventName: "MirrorListPublished", logs: publishReceipt.logs });

console.log(descriptorMirrorListId); // keccak256(abi.encode(releaseDescriptorIndexUris)) — callers can precompute this offline
```

## 2. `createAttestations` — the first batched registration

Every field that accepts multiple elements as inputs is supplied with two elements. Let's say there are two contracts in the project: `Vault` and `Staking`. The `Vault` is deployed on Mainnet and Optimism.

```TypeScript
const vaultMainnetAddress: Address = "0xAcmeVaultMainnet00000000000000000000000000";
const vaultOptimismAddress: Address = "0xAcmeVaultOptimism0000000000000000000000000";
const stakingContractAddress: Address = "0xAcmeStaking000000000000000000000000000000";

// The attester produces its off-chain EAS attestations following the ERC-8176 rules — out of scope
const descriptorHash: Hex = "0x7c3a1e2b...5d6e7f";
const attestationId: Hex = "0x4f0eaa11...8091a2";
const stakingDescriptorHash: Hex = "0x1a2b3c4d5e...d6e7f80";
const stakingEasAttestationId: Hex = "0x2233445566...889900aabb";
const stakingDeviceAttestationId: Hex = "0x334455667...9900aabbcc";
const VENDOR_FORMAT_CUSTOM = keccak256(toHex("erc7730.attestation.vendor.custom"));

const descriptorSchemaMajor = 3n; // MAJOR version of the descriptor's schema

// Contract #1 - Vault
const vaultDescriptor = {
  descriptorHash,
  descriptorSchemaMajor,
  contextKeyIds: [
    deriveContextKeyId(mainnetChainId, vaultMainnetAddress),    // mainnet deployment
    deriveContextKeyId(optimismChainId, vaultOptimismAddress),  // an L2 deployment
  ],
  attestationIds: [{ attestationId, attestationFormatId: ATTESTATION_FORMAT_EAS_OFFCHAIN }],
};

// Contract #2 - Staking
const stakingDescriptor = {
  descriptorHash: stakingDescriptorHash,
  descriptorSchemaMajor,
  contextKeyIds: [deriveContextKeyId(mainnetChainId, stakingContractAddress)],
  attestationIds: [
    // There is no canonical attestation ID or file format;
    // An attester can issue different attestations for the same contract:
    { attestationId: stakingEasAttestationId, attestationFormatId: ATTESTATION_FORMAT_EAS_OFFCHAIN },
    { attestationId: stakingDeviceAttestationId, attestationFormatId: VENDOR_FORMAT_CUSTOM },
  ],
};

// Both MirrorLists (published together in step 1) resolve to an index.json file —
// 'descriptorMirrorListId' keyed by 'descriptorHash', 'attestationMirrorListId' by 'attestationSetId'.

// The attester submits directly without a relay
const createHash = await registryAs(attesterClient).write.createAttestations([
  attesterAccount.address,
  [vaultDescriptor, stakingDescriptor], // batched — one transaction, two descriptors, four contexts
  descriptorMirrorListId,
  attestationMirrorListId,
  "0x", // signature — not needed, the attester is msg.sender
]);
const createReceipt = await publicClient.waitForTransactionReceipt({ hash: createHash });
const [{ args: vaultRegistered }, { args: stakingRegistered }] = parseEventLogs({
  abi: IClearSigningRegistryAbi, eventName: "AttestationRegistered", logs: createReceipt.logs,
});
const vaultAttestationSetId = vaultRegistered.attestationSetId; // === attestationId (single-member set)
const stakingSetId = stakingRegistered.attestationSetId; // content-derived (two members)
```

## 3. `resolveDescriptors` and `getRevocationTimestamp` — the wallet fetches registry data before rendering

Every parameter here acts as a filter or a lookup key set.
A real wallet passes its whole trust list, every candidate context, and every schema MAJOR version, and the attestation format it supports in one call:

```TypeScript
const trustedAttesterOne: Address = "0xTrustedAttester1000000000000000000000000";
const trustedAttesterTwo: Address = "0xTrustedAttester2000000000000000000000000";

const resolved = await registryRead.read.resolveDescriptors([
  /* this wallet's full list of trusted attesters */
  [trustedAttesterOne, trustedAttesterTwo],
  /* contracts the wallet is interacting with, as their contextKeyIds */
  [deriveContextKeyId(mainnetChainId, vaultMainnetAddress), deriveContextKeyId(optimismChainId, vaultOptimismAddress)],
  /* this wallet's firmware understands these schema major versions */
  [1n, 2n, 3n],
  /* this wallet only verifies the EAS attestations */
  [ATTESTATION_FORMAT_EAS_OFFCHAIN],
  /* this wallet only supports these two protocols */
  ["ipfs:", "https:"],
]);
```

Returned array — one entry per active `(attester, contextKeyId, descriptorSchemaMajor)` record, ordered `attesters` first, then `contextKeyIds`, then `descriptorSchemaMajors`. Both of the vault's deployments resolve here, sharing the same descriptor and mirrors but under different context key IDs:

```json
[
  {
    "descriptorHash": "0x7c3a...d6e7f",
    "contextKeyId": "0x8b41...c209",
    "descriptorSchemaMajor": "1",
    "attestationSetId": "0x4f0e...d6e7f",
    "descriptorMirrorListUris": ["ipfs://bafybeigd.../vault-and-staking-descriptors-index.json", "ar://vault-and-staking-descriptors-index-mirror"],
    "attestationMirrorListUris": ["ipfs://bafybeigd.../release-attestations-index.json"],
    "attestations": [
      { "attester": "0xAttester0000000000000000000000000000000", "attestationId": "0x4f0e...d6e7f", "attestationFormatId": "0x9b2c...eas0f", "revokedAt": "0" }
    ]
  },
  {
    "descriptorHash": "0x7c3a...d6e7f",
    "contextKeyId": "0x2f19...ab77",
    "descriptorSchemaMajor": "1",
    "attestationSetId": "0x4f0e...d6e7f",
    "descriptorMirrorListUris": ["ipfs://bafybeigd.../vault-and-staking-descriptors-index.json", "ar://vault-and-staking-descriptors-index-mirror"],
    "attestationMirrorListUris": ["ipfs://bafybeigd.../release-attestations-index.json"],
    "attestations": [
      { "attester": "0xAttester0000000000000000000000000000000", "attestationId": "0x4f0e...d6e7f", "attestationFormatId": "0x9b2c...eas0f", "revokedAt": "0" }
    ]
  }
]
```

The wallet validates every candidate entry, checking for availability, validity, and revocations (pseudocode):

```TypeScript
for (const entry of resolved) {
  // A stale active record can still point at an already-revoked set
  const setRevokedAt = await registryRead.read.getRevocationTimestamp([attesterAccount.address, entry.attestationSetId]);
  if (setRevokedAt !== 0n) continue;

  const descriptorBytes = await fetch(entry.descriptorMirrorListUris[0]).then((r) => r.arrayBuffer());
  if (!isValidDescriptor(descriptorBytes)) continue;

  const easAttestationEntry = entry.attestations.find((a) => a.attestationFormatId === ATTESTATION_FORMAT_EAS_OFFCHAIN);
  if (!isValidEasAttesation(easAttestationEntry)) continue;

  renderClearSigningPrompt(JSON.parse(new TextDecoder().decode(descriptorBytes)));
  break; // no need to check the rest - this candidate matched - we can render the transaction signing request
}
throw new Error("Valid entry not found")
```

## 4. `revokeAttestations` — batching a whole set with an individual member

`createAttestations` never revokes anything itself, so retiring the Vault's v1 attestation set — ahead of registering v2 in the next section — has to happen here, as its own call. The same call also batches in an unrelated cleanup: dropping just the Staking descriptor's vendor rendition. Two different `RevocationEntry` shapes side by side:
* a set id withdraws the whole release
* a single attestation id flags only that one rendition while the rest of the set stays active

```TypeScript
await registryAs(attesterClient).write.revokeAttestations([
  attesterAccount.address,
  [
    { attestationId: vaultAttestationSetId, contextKeyIds: [deriveContextKeyId(mainnetChainId, vaultMainnetAddress), deriveContextKeyId(optimismChainId, vaultOptimismAddress)] },
    { attestationId: stakingDeviceAttestationId, contextKeyIds: [] },
  ],
  "0x", // signature
]);
```

The `revokeAttestations` function can also be invoked with an EIP-712 signature similar to `createAttestations`.

## 5. Using `createAttestations` for updates & relayed transactions

In this example we are issuing an update to the previously registered `Vault` contract.
This is a legitimate and common operation - the contract may be upgradeable and changed its behaviour.
The old attestation set (`vaultAttestationSetId`) was already revoked in the previous section — `createAttestations` requires that precondition to already hold and never revokes anything itself.
We will also use a relayer address instead of making the registry call directly from the attester's EOA address.

```TypeScript
const nonce = await registryRead.read.getNonce([attesterAccount.address]);

const newDescriptorHash: Hex = "0x99aa88b...44556677";
const newAttestationId: Hex = "0x55ee44...bccddee";
const mainnetContextKeyId = deriveContextKeyId(mainnetChainId, vaultMainnetAddress);
const optimismContextKeyId = deriveContextKeyId(optimismChainId, vaultOptimismAddress);

const newDescriptor = {
  descriptorHash: newDescriptorHash,
  descriptorSchemaMajor,
  contextKeyIds: [mainnetContextKeyId, optimismContextKeyId], // assuming both deployments updated together
  attestationIds: [{ attestationId: newAttestationId, attestationFormatId: ATTESTATION_FORMAT_EAS_OFFCHAIN }],
};
const newAttestationSetId = newAttestationId; // a small quirk: single-member set can reuse its sole member's own id

// The new attestation blob lives at a new location, so its MirrorList has to be
// published (again, as its own prior step) before it can be referenced below.
const republishHash = await registryAs(ipfsPinnerClient).write.publishMirrorLists([[["ipfs://bafybeigd.../vault-attestation-v2.json"]]]);
const republishReceipt = await publicClient.waitForTransactionReceipt({ hash: republishHash });
const [{ args: { mirrorListId: newAttestationMirrorListId } }] = parseEventLogs({
  abi: IClearSigningRegistryAbi, eventName: "MirrorListPublished", logs: republishReceipt.logs,
});

const registrationTypes = { /* ... normal EIP-712 boilerplate types declaration, matching the typehashes in the ERC */ } as const;

const signature = await attesterClient.signTypedData({
  account: attesterAccount,
  domain: eip712Domain,
  types: registrationTypes,
  primaryType: "ClearSigningRegistrationBatch",
  message: {
    descriptors: [newDescriptor],
    descriptorMirrorListId, // URLs can remain unchanged
    attestationMirrorListId: newAttestationMirrorListId,
    nonce,
  },
});

// a relayer is the address making the actual transaction
await registryAs(relayerClient).write.createAttestations([
  attesterAccount.address, [newDescriptor], descriptorMirrorListId, newAttestationMirrorListId, signature,
]);
```

## 6. `updateDescriptorMirrorList` — rotating descriptor storage for several descriptors at once

Republishing both a **new descriptor** index and a **new attestation** index in one transaction.
Index files store mappings from ID to actual data.

```TypeScript
const republished2Hash = await registryAs(ipfsPinnerClient).write.publishMirrorLists([[
  ["ipfs://bafybeiNEW.../release-descriptors-index-v2.json"],
  ["ipfs://bafybeiNEW.../release-attestations-index-v2.json", "ar://release-attestations-index-v2-mirror"],
]]);
const republished2Receipt = await publicClient.waitForTransactionReceipt({ hash: republished2Hash });
const [
  { args: { mirrorListId: newDescriptorMirrorListId } },
  { args: { mirrorListId: rotatedAttestationMirrorListId } },
] = parseEventLogs({ abi: IClearSigningRegistryAbi, eventName: "MirrorListPublished", logs: republished2Receipt.logs });

// Rotate both the current vault descriptor and the staking descriptor together:
const descriptorHashes = [newDescriptorHash, stakingDescriptorHash];

// self-submitted transaction
await registryAs(attesterClient).write.updateDescriptorMirrorList([
  attesterAccount.address, descriptorHashes, newDescriptorMirrorListId, "0x",
]);
```

## 7. `updateAttestationMirrorList` — rotating attestation blob storage for several sets at once

Reuses the attestation index published in the previous section, rotating both attestation sets registered so far to point at it in one call:

```TypeScript
const attestationSetIds = [newAttestationSetId, stakingSetId];

await registryAs(attesterClient).write.updateAttestationMirrorList([
  attesterAccount.address, attestationSetIds, rotatedAttestationMirrorListId, "0x",
]);
```

## 8. `setAttesterProfileURI` and `getAttesterProfileURI`

```TypeScript
// The profile JSON itself lives off-chain in the following format:
//   {
//     "version": 1,
//     "attesters": ["0xAttester0000000000000000000000000000000", "0xAttesterHotWallet00000000000000000000000"],
//     "name": "Example Attester Inc.",
//     "securityContact": "mailto:security@attester.example.com"
//   }

await registryAs(attesterClient).write.setAttesterProfileURI([
  attesterAccount.address, "ipfs://bafybeigd.../attester-profile.json", "0x",
]);

const profileURI = await registryRead.read.getAttesterProfileURI([attesterAccount.address]);
```

A consumer that already trusts `attesterAccount.address` renders the profile only after checking the back-reference:

```TypeScript
const profile = await fetch(profileURI).then((r) => r.json());
if (profile.version !== 1) throw new Error("unsupported profile version");
if (!profile.attesters.some((a: string) => a.toLowerCase() === attesterAccount.address.toLowerCase())) {
  throw new Error("profile does not name the trusted attester — do not render it");
}
renderAttesterCard(profile.name);
```

## 9. Non-deployment context types — factory, EIP-712 deployments, and domain separators

`contextKeyIds` is a flat `bytes32[]` — nothing about an entry reveals which ERC-7730 binding type produced it. A single descriptor can mix every derivation rule freely:

```TypeScript
const vaultFactoryAddress: Address = "0xAcmeVaultFactory000000000000000000000000";
const deployEventSignature = "VaultCreated(address,address)"; // matches the descriptor's `context.contract.factory.deployEvent`
const permitRouterAddress: Address = "0xAcmePermitRouter00000000000000000000000";
const legacyDomainSeparator: Hex = "0xdeadbeef00000000000000000000000000000000000000000000000000cafebabe"; // precomputed off-chain per EIP-712

const factoryDescriptorHash: Hex = "0xaa11bb22...ee33ff44";
const factoryAttestationId: Hex = "0xbb22cc33...ff445566";

const factoryDescriptor = {
  descriptorHash: factoryDescriptorHash,
  descriptorSchemaMajor,
  contextKeyIds: [
    deriveFactoryContextKeyId(mainnetChainId, vaultFactoryAddress, deployEventSignature),   // any contract this factory deploys
    deriveEip712DeploymentContextKeyId(mainnetChainId, permitRouterAddress),                // an EIP-712 verifyingContract
    deriveDomainSeparatorContextKeyId(legacyDomainSeparator),                                // a precomputed domain separator
  ],
  attestationIds: [{ attestationId: factoryAttestationId, attestationFormatId: ATTESTATION_FORMAT_EAS_OFFCHAIN }],
};

// Reuses the release indexes already published in step 1 — no new MirrorList needed.
await registryAs(attesterClient).write.createAttestations([
  attesterAccount.address,
  [factoryDescriptor],
  descriptorMirrorListId,
  attestationMirrorListId,
  "0x", // signature
]);

const resolvedFactory = await registryRead.read.resolveDescriptors([
  [attesterAccount.address],
  factoryDescriptor.contextKeyIds,
  [descriptorSchemaMajor],
  [ATTESTATION_FORMAT_EAS_OFFCHAIN],
  ["ipfs:", "https:"],
]);
// shape identical to §3's output — one entry per contextKeyId, same fields
```

## Errors at a glance

| Error | Raised when | See |
|---|---|---|
| `EmptyDescriptors` | `descriptors` is empty in `createAttestations` | §2 |
| `ZeroDescriptorHash` | a descriptor's `descriptorHash` is `bytes32(0)` | §2 |
| `ZeroDescriptorSchemaMajor` | a descriptor's `descriptorSchemaMajor` is `0` | §2 |
| `EmptyContextKeyIds` | a descriptor's `contextKeyIds` is empty | §2 |
| `EmptyAttestationIds` | a descriptor's `attestationIds` is empty | §2 |
| `ZeroAttestationId` | an `attestationIds`/`RevocationEntry` entry's `attestationId` is `bytes32(0)` | §2, §4 |
| `ZeroAttestationFormat` | an `attestationIds` entry's `attestationFormatId` is `bytes32(0)` | §2 |
| `DuplicateAttestationFormat` | two entries in the same descriptor share an `attestationFormatId` | §2 |
| `AttestationIdAlreadyUsed` | an attestation or set id was already revoked, or a reused set id doesn't match the stored record | §2 |
| `EmptyMirrorList` | `publishMirrorLists` is given an empty URI list | §1 |
| `UnknownMirrorList` | a `descriptorMirrorListId`/`attestationMirrorListId` was never published via `publishMirrorLists` | §2 |
| `UnknownDescriptor` | `updateDescriptorMirrorList` names a descriptor hash the attester never registered | §6 |
| `UnknownAttestationSet` | `updateAttestationMirrorList` names a set id the attester never registered | §7 |
| `EmptyRevocations` | `revokeAttestations` is called with an empty `revocations` array | §4 |
| `EmptyKeys` | `updateDescriptorMirrorList`/`updateAttestationMirrorList` is given an empty key array | §6 |
| `MissingRevocation` | a descriptor in `createAttestations` displaces an active record whose set id isn't recorded as revoked yet — see §4/§5 for the required revoke-then-register order | §5 |
| `InvalidRegistrationSignature` | any relayed `signature` fails to verify for the named attester | §5 |
```

- [ ] **Step 2: Commit**

```bash
cd /Users/alexf/onchain-clear-signing-erc7730-registry
git add README.md
git commit -m "Add README walkthrough"
```

---

### Task 4: Push the new repo

**Files:** none (git operations only)

**Interfaces:** none

- [ ] **Step 1: Final sanity check**

```bash
cd /Users/alexf/onchain-clear-signing-erc7730-registry
npm install && npm run compile && npm test
```

Expected: install clean, compile succeeds (`evm target: cancun`), `1 passing`.

- [ ] **Step 2: Push**

```bash
cd /Users/alexf/onchain-clear-signing-erc7730-registry
git push -u origin main
```

Expected: pushes 3 commits ("Project scaffold", "Add smoke test", "Add README walkthrough") to `git@github.com:forshtat/onchain-clear-signing-erc7730-registry.git`, branch `main`.

---

### Task 5: Trim `ERCS2`'s `assets/erc-8283/` and update `erc-8283.md`

**Files:**
- Delete: `/Users/alexf/ERCS2/assets/erc-8283/ClearSigningRegistry.sol`
- Delete: `/Users/alexf/ERCS2/assets/erc-8283/ClearSigningRegistryConstants.sol`
- Delete: `/Users/alexf/ERCS2/assets/erc-8283/RegistrationHashLib.sol`
- Delete: `/Users/alexf/ERCS2/assets/erc-8283/UriFilterLib.sol`
- Delete: `/Users/alexf/ERCS2/assets/erc-8283/README.md`
- Delete: `/Users/alexf/ERCS2/assets/erc-8283/openzeppelin/` (entire directory)
- Modify: `/Users/alexf/ERCS2/ERCS/erc-8283.md`

**Interfaces:** none (documentation-only change)

- [ ] **Step 1: Delete the moved files**

```bash
cd /Users/alexf/ERCS2
git rm -r \
  assets/erc-8283/ClearSigningRegistry.sol \
  assets/erc-8283/ClearSigningRegistryConstants.sol \
  assets/erc-8283/RegistrationHashLib.sol \
  assets/erc-8283/UriFilterLib.sol \
  assets/erc-8283/README.md \
  assets/erc-8283/openzeppelin
```

Expected: `assets/erc-8283/` now contains only `IClearSigningRegistry.sol`.

- [ ] **Step 2: Insert the bare-declarations interface block into `ERCS/erc-8283.md`**

Find this existing line (currently followed by a blank line and then `#### \`createAttestations\``):

```
The full normative interface is provided in [IClearSigningRegistry.sol](../assets/erc-8283/IClearSigningRegistry.sol).
```

Replace it with that same sentence plus a fenced code block immediately after it:

```markdown
The full normative interface is provided in [IClearSigningRegistry.sol](../assets/erc-8283/IClearSigningRegistry.sol).

```solidity
interface IClearSigningRegistry {
    function createAttestations(address attester, DescriptorInfo[] calldata descriptors, bytes32 descriptorMirrorListId, bytes32 attestationMirrorListId, bytes calldata signature) external;
    function publishMirrorLists(string[][] calldata uriLists) external;
    function revokeAttestations(address attester, RevocationEntry[] calldata revocations, bytes calldata signature) external;
    function getRevocationTimestamp(address attester, bytes32 attestationId) external view returns (uint64 timestamp);
    function resolveDescriptors(address[] calldata attesters, bytes32[] calldata contextKeyIds, uint256[] calldata descriptorSchemaMajors, bytes32[] calldata attestationFormatIds, string[] calldata allowedPrefixes) external view returns (ResolvedDescriptor[] memory resolved);
    function getMirrorListById(bytes32 mirrorListId, string[] calldata allowedPrefixes) external view returns (string[] memory uris);
    function getNonce(address attester) external view returns (uint256 nonce);
    function invalidateNonce() external;
    function updateDescriptorMirrorList(address attester, bytes32[] calldata descriptorHashes, bytes32 descriptorMirrorListId, bytes calldata signature) external;
    function updateAttestationMirrorList(address attester, bytes32[] calldata attestationSetIds, bytes32 attestationMirrorListId, bytes calldata signature) external;
    function setAttesterProfileURI(address attester, string calldata profileURI, bytes calldata signature) external;
    function getAttesterProfileURI(address attester) external view returns (string memory profileURI);
}
```
```

(That is: the sentence, a blank line, then the ` ```solidity ` fenced block shown above, verbatim — 12 function declarations, no comments, no struct/event/error bodies.)

- [ ] **Step 3: Update the `## Reference Implementation` section**

Find:

```markdown
## Reference Implementation

The reference implementation is provided in two files:

- [IClearSigningRegistry.sol](../assets/erc-8283/IClearSigningRegistry.sol) — the normative interface
- [ClearSigningRegistry.sol](../assets/erc-8283/ClearSigningRegistry.sol) — the reference implementation

The current reference implementation is not audited and is intended for specification clarity only.
Production contracts will undergo an independent security review before deployment.
```

Replace with:

```markdown
## Reference Implementation

- [IClearSigningRegistry.sol](../assets/erc-8283/IClearSigningRegistry.sol) — the normative interface
- [onchain-clear-signing-erc7730-registry](https://github.com/forshtat/onchain-clear-signing-erc7730-registry) — the reference implementation, with its Hardhat test suite

The current reference implementation is not audited and is intended for specification clarity only.
Production contracts will undergo an independent security review before deployment.
```

- [ ] **Step 4: Verify no dangling references remain**

```bash
cd /Users/alexf/ERCS2
grep -rn "assets/erc-8283/ClearSigningRegistry\.sol\|assets/erc-8283/openzeppelin\|assets/erc-8283/README" ERCS/erc-8283.md
```

Expected: no output (empty match) — confirms the only remaining local link under `assets/erc-8283/` is to `IClearSigningRegistry.sol`.

- [ ] **Step 5: Commit (do not push)**

```bash
cd /Users/alexf/ERCS2
git add assets/erc-8283 ERCS/erc-8283.md
git commit -m "Move ERC-8283 reference implementation to its own repo"
```
