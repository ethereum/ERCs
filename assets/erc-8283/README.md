# `IClearSigningRegistry` walkthrough

**Attester Signer Entity** (the attester)

**IPFS Mirror Operator** (an independent mirror operator)

**Relayer Service** (relays authorized actions on the attester's behalf)

**Wallet Client** (the user)

## Constants

```TypeScript
const REGISTRY_ADDRESS = "0xREGISTRY0000000000000000000000000000000";
const registry = new ethers.Contract(REGISTRY_ADDRESS, IClearSigningRegistryAbi);

const attesterSigner = new ethers.Wallet(ATTESTER_PRIVATE_KEY)
const relayerWallet = new ethers.Wallet(RELAYER_PRIVATE_KEY)
const ipfsPinner = new ethers.Wallet(PINNING_PRIVATE_KEY) // independent IPFS mirror operator

const mainnetChainId = 1
const optimismChainId = 10


const ATTESTATION_FORMAT_EAS_OFFCHAIN = ethers.keccak256("erc7730.attestation.eas.offchain");

const eip712domain = { name: "ClearSigningRegistry", version: "1", chainId: 1n, verifyingContract: REGISTRY_ADDRESS };
```


```TypeScript
function deriveContextKeyId(chainId: bigint, contractAddress: string): string {
  const CONTEXT_TAG_CONTRACT = ethers.keccak256("erc7730.context.contract")
  return ethers.keccak256(
    abiCoder.encode(["bytes32", "uint256", "address"], [CONTEXT_TAG_CONTRACT, chainId, contractAddress]),
  );
}

function deriveFactoryContextKeyId(chainId: bigint, factoryAddress: string, deployEventSignature: string): string {
  const CONTEXT_TAG_FACTORY = ethers.keccak256("erc7730.context.factory")
  const deployEventTopic = ethers.keccak256(deployEventSignature) // topic0 = hash of the event signature string
  return ethers.keccak256(
    abiCoder.encode(["bytes32", "uint256", "address", "bytes32"], [CONTEXT_TAG_FACTORY, chainId, factoryAddress, deployEventTopic]),
  );
}

function deriveEip712DeploymentContextKeyId(chainId: bigint, verifyingContract: string): string {
  const CONTEXT_TAG_EIP712_DEP = ethers.keccak256("erc7730.context.eip712.deployment")
  return ethers.keccak256(
    abiCoder.encode(["bytes32", "uint256", "address"], [CONTEXT_TAG_EIP712_DEP, chainId, verifyingContract]),
  );
}

function deriveDomainSeparatorContextKeyId(domainSeparator: string): string {
  const CONTEXT_TAG_EIP712_DS = ethers.keccak256("erc7730.context.eip712.domainseparator")
  return ethers.keccak256(
    abiCoder.encode(["bytes32", "bytes32"], [CONTEXT_TAG_EIP712_DS, domainSeparator]),
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

const receipt = await registry.connect(ipfsPinner).publishMirrorLists(/* uriLists */ [releaseDescriptorIndexUris, releaseAttestationIndexUris]);
const [
  { mirrorListId: descriptorMirrorListId },
  { mirrorListId: attestationMirrorListId },
] = receipt.logs["MirrorListPublished"];

console.log(descriptorMirrorListId); // keccak256(abi.encode(releaseDescriptorIndexUris)) — callers can precompute this offline
```

## 2. `createAttestations` — the first batched registration

Every field that accepts multiple elements as inputs is supplied with two elements. Let's say there are two contracts in the project: `Vault` and `Staking`. The `Vault` is deployed on Mainnet and Optimism.

```TypeScript
const vaultMainnetAddress = "0xAcmeVaultMainnet00000000000000000000000000";
const vaultOptimismAddress = "0xAcmeVaultOptimism0000000000000000000000000";
const stakingContractAddress = "0xAcmeStaking000000000000000000000000000000";

// The attester produces its off-chain EAS attestations following the ERC-8176 rules — out of scope
const descriptorHash = "0x7c3a1e2b...5d6e7f";
const attestationId = "0x4f0eaa11...8091a2";
const stakingDescriptorHash = "0x1a2b3c4d5e...d6e7f80";
const stakingEasAttestationId = "0x2233445566...889900aabb";
const stakingDeviceAttestationId = "0x334455667...9900aabbcc";
const VENDOR_FORMAT_CUSTOM = ethers.keccak256("erc7730.attestation.vendor.custom");

const descriptorSchemaMajor = 3; // MAJOR version of the descriptor's schema

// Contract #1 - Vault
const vaultDescriptor: DescriptorInfo = {
  descriptorHash,
  descriptorSchemaMajor,
  contextKeyIds: [
    deriveContextKeyId(mainnetChainId, vaultMainnetAddress),    // mainnet deployment
    deriveContextKeyId(optimismChainId, vaultOptimismAddress),  // an L2 deployment
  ],
  attestationIds: [{ attestationId, attestationFormatId: ATTESTATION_FORMAT_EAS_OFFCHAIN }],
};

// Contract #2 - Staking
const stakingDescriptor: DescriptorInfo = {
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
const receipt = await registry.connect(attesterSigner).createAttestations(
  /* attester */ attesterSigner.address,
  [vaultDescriptor, stakingDescriptor], // batched — one transaction, two descriptors, four contexts
  descriptorMirrorListId,
  attestationMirrorListId,
  /* signature */ "0x",
);

const [vaultRegistered, stakingRegistered] = receipt.logs["AttestationRegistered"];
const vaultAttestationSetId = vaultRegistered.attestationSetId; // === attestationId (single-member set)
const stakingSetId = stakingRegistered.attestationSetId; // content-derived (two members)
```

## 3. `resolveDescriptors` and `getRevocationTimestamp` — the wallet fetches registry data before rendering

Every parameter here is acts as a filter or a lookup key set.
A real wallet passes its whole trust list, every candidate context, and every schema MAJOR version, and the attestation format it supports in one call:

```ts
const trustedAttesterOne = "0xTrustedAttester1000000000000000000000000";
const trustedAttesterTwo = "0xTrustedAttester2000000000000000000000000";

const resolved = await registry.resolveDescriptors(
  /* this wallet's full list of trusted attesters */
  [trustedAttesterOne, trustedAttesterTwo],
  /* contracts the wallet is interacting with, as their contextKeyIds */
  [deriveContextKeyId(mainnetChainId, vaultMainnetAddress), deriveContextKeyId(optimismChainId, vaultOptimismAddress)],
  /* this wallet's firmware understands these schema major versions */
  [1, 2, 3],
  /* this wallet only verifies the EAS attestations */
  [ATTESTATION_FORMAT_EAS_OFFCHAIN],
  /* this wallet only supports these two protocols */
  ["ipfs:", "https:"]
);
```

Returned JSON — one entry per active `(attester, contextKeyId, descriptorSchemaMajor)` record, ordered `attesters` first, then `contextKeyIds`, then `descriptorSchemaMajors`. Both of the vault's deployments resolve here, sharing the same descriptor and mirrors but under different context key IDs:

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

```ts
for (const entry of resolved) {
  // A stale active record can still point at an already-revoked set
  const setRevokedAt = await registry.getRevocationTimestamp(/* attester */ attesterSigner.address, /* attestationId */ entry.attestationSetId);
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

```ts
await registry.connect(attesterSigner).revokeAttestations(
  /* attester */ attesterSigner.address,
  [
    { attestationId: vaultAttestationSetId, contextKeyIds: [deriveContextKeyId(mainnetChainId, vaultMainnetAddress), deriveContextKeyId(optimismChainId, vaultOptimismAddress)] },
    { attestationId: stakingDeviceAttestationId, contextKeyIds: [] },
  ],
  /* signature */ "0x",
);
```

The `revokeAttestations` function can also be invoked with an EIP-712 signature similar to `createAttestations`.

## 5. Using `createAttestations` for updates & relayed transactions

In this example we are issuing an update to the previously registered `Vault` contract.
This is a legitimate and common operation - the contract may be upgradeable and changed its behaviour.
The old attestation set (`vaultAttestationSetId`) was already revoked in the previous section — `createAttestations` requires that precondition to already hold and never revokes anything itself.
We will also use a relayer address instead of making the registry call directly from the attester's EOA address.

```ts
const nonce = await registry.getNonce(attesterSigner.address);

const newDescriptorHash = "0x99aa88b...44556677";
const newAttestationId = "0x55ee44...bccddee";
const mainnetContextKeyId = deriveContextKeyId(mainnetChainId, vaultMainnetAddress);
const optimismContextKeyId = deriveContextKeyId(optimismChainId, vaultOptimismAddress);

const newDescriptor: DescriptorInfo = {
  descriptorHash: newDescriptorHash,
  descriptorSchemaMajor,
  contextKeyIds: [mainnetContextKeyId, optimismContextKeyId], // assuming both deployments updated together
  attestationIds: [{ attestationId: newAttestationId, attestationFormatId: ATTESTATION_FORMAT_EAS_OFFCHAIN }],
};
const newAttestationSetId = newAttestationId; // a small quirk: single-member set can reuse its sole member's own id

// The new attestation blob lives at a new location, so its MirrorList has to be
// published (again, as its own prior step) before it can be referenced below.
const republishedV2 = await registry.connect(ipfsPinner).publishMirrorLists(/* uriLists */ [["ipfs://bafybeigd.../vault-attestation-v2.json"]]);
const [{ mirrorListId: newAttestationMirrorListId }] = republishedV2.logs["MirrorListPublished"];

const registrationTypes = { /* ... normal EIP-712 boilerplate types declaration */};

const signature = await attesterSigner.signTypedData(eip712domain, registrationTypes, {
  descriptors: [newDescriptor],
  descriptorMirrorListId, // URLs can remain unchanged
  attestationMirrorListId: newAttestationMirrorListId,
  nonce,
});

// a relayer is the address making the actual transaction
await registry.connect(relayerWallet).createAttestations(
  /* attester */ attesterSigner.address, [newDescriptor], descriptorMirrorListId, newAttestationMirrorListId, signature,
);
```

## 6. `updateDescriptorMirrorList` — rotating descriptor storage for several descriptors at once

Republishing both a **new descriptor** index and a **new attestation** index in one transaction.
Index files store mappings from ID to actual data.


```ts
const republished = await registry.connect(ipfsPinner).publishMirrorLists(/* uriLists */ [
  ["ipfs://bafybeiNEW.../release-descriptors-index-v2.json"],
  ["ipfs://bafybeiNEW.../release-attestations-index-v2.json", "ar://release-attestations-index-v2-mirror"],
]);
const [
  { mirrorListId: newDescriptorMirrorListId },
  { mirrorListId: rotatedAttestationMirrorListId },
] = republished.logs["MirrorListPublished"];

// Rotate both the current vault descriptor and the staking descriptor together:
const descriptorHashes = [newDescriptorHash, stakingDescriptorHash];

// self-submitted transaction
await registry.connect(attesterSigner).updateDescriptorMirrorList(
  /* attester */ attesterSigner.address, descriptorHashes, newDescriptorMirrorListId, /* signature */ "0x",
)
```

## 7. `updateAttestationMirrorList` — rotating attestation blob storage for several sets at once

Reuses the attestation index published in the previous section, rotating both attestation sets registered so far to point at it in one call:

```ts
const attestationSetIds = [newAttestationSetId, stakingSetId];

await registry.connect(attesterSigner).updateAttestationMirrorList(
  /* attester */ attesterSigner.address, attestationSetIds, rotatedAttestationMirrorListId, /* signature */ "0x",
);
```

## 8. `setAttesterProfileURI` and `getAttesterProfileURI`

```ts
// The profile JSON itself lives off-chain in the following format:
//   {
//     "version": 1,
//     "attesters": ["0xAttester0000000000000000000000000000000", "0xAttesterHotWallet00000000000000000000000"],
//     "name": "Example Attester Inc.",
//     "securityContact": "mailto:security@attester.example.com"
//   }

await registry.connect(attesterSigner).setAttesterProfileURI(
  /* attester */ attesterSigner.address, /* profileURI */ "ipfs://bafybeigd.../attester-profile.json", /* signature */ "0x",
);

const profileURI = await registry.getAttesterProfileURI(attesterSigner.address);
```

A consumer that already trusts `attesterSigner.address` renders the profile only after checking the back-reference:

```ts
const profile = await fetch(profileURI).then((r) => r.json());
if (profile.version !== 1) throw new Error("unsupported profile version");
if (!profile.attesters.some((a) => a.toLowerCase() === attesterSigner.address.toLowerCase())) {
  throw new Error("profile does not name the trusted attester — do not render it");
}
renderAttesterCard(profile.name);
```

## 9. Non-deployment context types — factory, EIP-712 deployments, and domain separators

`contextKeyIds` is a flat `bytes32[]` — nothing about an entry reveals which ERC-7730 binding type produced it. A single descriptor can mix every derivation rule freely:

```ts
const vaultFactoryAddress = "0xAcmeVaultFactory000000000000000000000000";
const deployEventSignature = "VaultCreated(address,address)"; // matches the descriptor's `context.contract.factory.deployEvent`
const permitRouterAddress = "0xAcmePermitRouter00000000000000000000000";
const legacyDomainSeparator = "0xdeadbeef00000000000000000000000000000000000000000000000000cafebabe"; // precomputed off-chain per EIP-712

const factoryDescriptorHash = "0xaa11bb22...ee33ff44";
const factoryAttestationId = "0xbb22cc33...ff445566";

const factoryDescriptor: DescriptorInfo = {
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
await registry.connect(attesterSigner).createAttestations(
  /* attester */ attesterSigner.address,
  [factoryDescriptor],
  descriptorMirrorListId,
  attestationMirrorListId,
  /* signature */ "0x",
);

const resolved = await registry.resolveDescriptors(
  /* attesters */ [attesterSigner.address],
  /* contextKeyIds */ factoryDescriptor.contextKeyIds,
  /* descriptorSchemaMajors */ [descriptorSchemaMajor],
  /* attestationFormatIds */ [ATTESTATION_FORMAT_EAS_OFFCHAIN],
  /* allowedPrefixes */ ["ipfs:", "https:"],
);
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
