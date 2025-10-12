---
eip: 7999
title: CrediNet Verifiable Credit SBT
description: ERC-721–compatible, non-transferable credit credential with verifiable snapshot anchoring, revoke/replace lifecycle, optional expiry, and DID/VC hooks for privacy-preserving verification.
author: CrediNet Core Team <zc040809@gmail.com>
discussions-to: <PASTE-YOUR-MAGICIANS-THREAD-URL-HERE>
status: Draft
type: ERC
created: 2025-10-13
requires: ERC-165, ERC-721
optional: EIP-5192, EIP-5484
license: CC0-1.0
---

## Abstract

This ERC standardizes an ERC-721–compatible, **non-transferable (“soulbound”) credit credential**. It binds a **verifiable credit snapshot** (hash/Merkle-root of a scoring JSON including version and data-source consent) to a token and defines lifecycle semantics: **revoke**, **replace (atomic)**, and **expiry**. It also exposes **DID/VC hooks** via hashed references for off-chain privacy with on-chain verifiability. Each `(holder, schemaId)` has **at most one active** token. All transfer/approval calls MUST revert; `locked()` per EIP-5192 MAY be implemented to signal non-transferability.

## Motivation

Credit use-cases require more than minimal SBT signaling:
- **Verifiable snapshot anchoring**: attest *what was scored, when, under which model and consent*.
- **Lifecycle management**: revoke (with reason/evidence), **replace** to reflect updated scores/models, and **expiry** to avoid stale credit.
- **Privacy and interoperability**: hashed hooks to DID/VC artifacts; optional ZK proof interfaces.

Existing proposals (EIP-5192 minimal lock signaling; EIP-5484 burn authorization; EIP-4973 account-bound tokens; ERC-5114 badges bound to NFTs) do not standardize snapshot anchoring, consent binding, versioned replacement, and expiry semantics required for credit.

## Specification

### Terms
- **Issuer** — authorized to mint (and possibly revoke) credit tokens.
- **Holder** — receiving account.
- **Schema** — a credit model/version identified by `schemaId`.
- **Snapshot** — hash/Merkle-root of a scoring JSON with issuance time, optional expiry, and consent/VC hashes.
- **BurnAuth** — revocation authority code (compatible with EIP-5484, optional).

### Storage
- **Schema** (`schemaId → name, version, paramsHash, uri`) (optional registry).
- **Token fields** (per `tokenId`):
  - `schemaId (uint32)`
  - `snapshotHash (bytes32)` — hash/root of scoring JSON
  - `consentsHash (bytes32)` — hash of user-granted data sources at scoring time
  - `vcHash (bytes32)` — optional DID/VC hash (0x0 if unused)
  - `issuedAt (uint64)`, `expiry (uint64)` (0 => no expiry)
  - `status (uint8)` — `0=Active, 1=Revoked, 2=Expired`
  - `burnAuth (uint8)` — optional EIP-5484-compatible code
  - optional `evidenceURI (string)` — pointer to public evidence (IPFS/HTTPS)

**Uniqueness.** A contract MUST enforce **≤ 1 Active** token for each `(holder, schemaId)`.

### Interface (ERC-165)

Contracts MUST support `IERC7xxx` (interface id TBD) and ERC-721; they MAY support EIP-5192 `locked()`.

```solidity
interface IERC7xxx /* is IERC165, IERC721 */ {
  event SchemaRegistered(uint32 indexed schemaId, string name, string version, bytes32 paramsHash, string uri);

  event CreditMinted(
    address indexed to,
    uint256 indexed tokenId,
    uint32 indexed schemaId,
    bytes32 snapshotHash,
    bytes32 consentsHash,
    bytes32 vcHash,
    uint64 issuedAt,
    uint64 expiry
  );

  event CreditReplaced(
    uint256 indexed oldTokenId,
    uint256 indexed newTokenId,
    uint16 reasonCode,
    string evidenceURI
  );

  event CreditRevoked(uint256 indexed tokenId, uint16 reasonCode, string evidenceURI);
  event CreditExpired(uint256 indexed tokenId);

  error CreditExists(address holder, uint32 schemaId);
  error NotAuthorized();
  error InvalidSchema();
  error NotRevokable();
  error SnapshotMismatch();
  error NotActive();
  error NotExpired();

  struct CreditSnapshot {
    bytes32 snapshotHash;
    bytes32 consentsHash;
    bytes32 vcHash;     // optional
    uint64  issuedAt;
    uint64  expiry;     // 0 => no expiry
  }

  function mintCredit(
    address to,
    uint32 schemaId,
    CreditSnapshot calldata snap,
    uint8 burnAuth,            // optional compatibility with EIP-5484 codes
    string calldata tokenURI
  ) external returns (uint256 tokenId);

  function replaceCredit(
    address to,
    uint32 schemaId,
    CreditSnapshot calldata snap,
    string calldata tokenURI,
    uint16 reasonCode,
    string calldata evidenceURI
  ) external returns (uint256 newTokenId);

  function revoke(
    uint256 tokenId,
    uint16 reasonCode,
    string calldata evidenceURI
  ) external;

  function expire(uint256 tokenId) external;

  function creditOf(address holder, uint32 schemaId) external view returns (uint256 tokenId);
  function getSnapshot(uint256 tokenId) external view returns (CreditSnapshot memory snap);
  function burnAuth(uint256 tokenId) external view returns (uint8); // if adopted
  function statusOf(uint256 tokenId) external view returns (uint8); // 0=Active,1=Revoked,2=Expired

  // Optional: EIP-5192 compatibility
  function locked(uint256 tokenId) external view returns (bool);
}
```
Non-transferability. Implementations MUST revert on transferFrom, both safeTransferFrom overloads, approve, and setApprovalForAll.

State Machine

Mint: NONE → Active (enforce (holder, schemaId) uniqueness).

Replace: Active(old) → Revoked(old) atomically; Active(new) minted.

Expire: Active → Expired (time-based; anyone MAY call expire once due).

Revoke: Active|Expired → Revoked (per burnAuth/governance).

Transfer/Approval: disallowed (MUST revert).

Snapshot & Off-chain Data

The scoring JSON (dimensions, total, model version, generatedAt, source fingerprints, consent set, etc.) stays off-chain; only the hash/root and related hashes are on-chain. tokenURI SHOULD be content-addressed (e.g., IPFS).

### Optional ZK Proof Hook

Implementations MAY add a verifier:

```solidity
function isSnapshotProven(uint256 tokenId, bytes calldata proof) external view returns (bool);

```

This ERC does not mandate a proof system; it standardizes the binding points (snapshotHash, consentsHash, vcHash).

Rationale

Schema + Snapshot separates model/version metadata from per-issuance evidence, yielding clear auditability and versioned updates via replace-not-mutate.

Revoke/Replace/Expire mirrors real-world credit lifecycle while remaining ERC-721 compatible for tooling.

BurnAuth compatibility eases adoption in SBT infra parsing EIP-5484 codes.

DID/VC hooks enable selective disclosure without leaking PII.

Backwards Compatibility

ERC-721 compliant (mint/burn Transfer events).

EIP-5192 compatible (locked() MAY always return true).

EIP-5484 compatible (burnAuth() optional exposure).

ERC-5114 is orthogonal; bridges MAY derive badges from 7xxx events if using an identity-NFT pattern.

Security Considerations

Non-transferability MUST be enforced at the API level and (optionally) signaled via locked() to prevent UX pitfalls.

Revocation governance SHOULD define reasonCode vocab and use evidenceURI for auditability; multi-sig for issuer roles recommended.

Privacy: on-chain only hashes; favor content-addressed URIs for public materials; consider ZK proof adapters.

Expiry & replay: verifiers MUST check status and timestamps.

Key loss: policies for revoke-and-reissue SHOULD be documented to avoid abuse.

Reentrancy & gas: follow checks-effects-interactions; consider batch limits.

Reference Minimal ABI (JSON)

```json
[
  {"type":"event","name":"SchemaRegistered","inputs":[
    {"name":"schemaId","type":"uint32","indexed":true},
    {"name":"name","type":"string"},
    {"name":"version","type":"string"},
    {"name":"paramsHash","type":"bytes32"},
    {"name":"uri","type":"string"}
  ]},
  {"type":"event","name":"CreditMinted","inputs":[
    {"name":"to","type":"address","indexed":true},
    {"name":"tokenId","type":"uint256","indexed":true},
    {"name":"schemaId","type":"uint32","indexed":true},
    {"name":"snapshotHash","type":"bytes32"},
    {"name":"consentsHash","type":"bytes32"},
    {"name":"vcHash","type":"bytes32"},
    {"name":"issuedAt","type":"uint64"},
    {"name":"expiry","type":"uint64"}
  ]},
  {"type":"event","name":"CreditReplaced","inputs":[
    {"name":"oldTokenId","type":"uint256","indexed":true},
    {"name":"newTokenId","type":"uint256","indexed":true},
    {"name":"reasonCode","type":"uint16"},
    {"name":"evidenceURI","type":"string"}
  ]},
  {"type":"event","name":"CreditRevoked","inputs":[
    {"name":"tokenId","type":"uint256","indexed":true},
    {"name":"reasonCode","type":"uint16"},
    {"name":"evidenceURI","type":"string"}
  ]},
  {"type":"event","name":"CreditExpired","inputs":[
    {"name":"tokenId","type":"uint256","indexed":true}
  ]},
  {"type":"error","name":"CreditExists","inputs":[
    {"name":"holder","type":"address"},{"name":"schemaId","type":"uint32"}
  ]},
  {"type":"error","name":"NotAuthorized","inputs":[]},
  {"type":"error","name":"InvalidSchema","inputs":[]},
  {"type":"error","name":"NotRevokable","inputs":[]},
  {"type":"error","name":"SnapshotMismatch","inputs":[]},
  {"type":"error","name":"NotActive","inputs":[]},
  {"type":"error","name":"NotExpired","inputs":[]},
  {"type":"function","stateMutability":"nonpayable","name":"mintCredit","inputs":[
    {"name":"to","type":"address"},
    {"name":"schemaId","type":"uint32"},
    {"name":"snap","type":"tuple","components":[
      {"name":"snapshotHash","type":"bytes32"},
      {"name":"consentsHash","type":"bytes32"},
      {"name":"vcHash","type":"bytes32"},
      {"name":"issuedAt","type":"uint64"},
      {"name":"expiry","type":"uint64"}
    ]},
    {"name":"burnAuth","type":"uint8"},
    {"name":"tokenURI","type":"string"}
  ],"outputs":[{"name":"tokenId","type":"uint256"}]},
  {"type":"function","stateMutability":"nonpayable","name":"replaceCredit","inputs":[
    {"name":"to","type":"address"},
    {"name":"schemaId","type":"uint32"},
    {"name":"snap","type":"tuple","components":[
      {"name":"snapshotHash","type":"bytes32"},
      {"name":"consentsHash","type":"bytes32"},
      {"name":"vcHash","type":"bytes32"},
      {"name":"issuedAt","type":"uint64"},
      {"name":"expiry","type":"uint64"}
    ]},
    {"name":"tokenURI","type":"string"},
    {"name":"reasonCode","type":"uint16"},
    {"name":"evidenceURI","type":"string"}
  ],"outputs":[{"name":"newTokenId","type":"uint256"}]},
  {"type":"function","stateMutability":"nonpayable","name":"revoke","inputs":[
    {"name":"tokenId","type":"uint256"},
    {"name":"reasonCode","type":"uint16"},
    {"name":"evidenceURI","type":"string"}
  ],"outputs":[]},
  {"type":"function","stateMutability":"nonpayable","name":"expire","inputs":[
    {"name":"tokenId","type":"uint256"}
  ],"outputs":[]},
  {"type":"function","stateMutability":"view","name":"creditOf","inputs":[
    {"name":"holder","type":"address"},
    {"name":"schemaId","type":"uint32"}
  ],"outputs":[{"name":"tokenId","type":"uint256"}]},
  {"type":"function","stateMutability":"view","name":"getSnapshot","inputs":[
    {"name":"tokenId","type":"uint256"}
  ],"outputs":[{"name":"snap","type":"tuple","components":[
    {"name":"snapshotHash","type":"bytes32"},
    {"name":"consentsHash","type":"bytes32"},
    {"name":"vcHash","type":"bytes32"},
    {"name":"issuedAt","type":"uint64"},
    {"name":"expiry","type":"uint64"}
  ]}]},
  {"type":"function","stateMutability":"view","name":"burnAuth","inputs":[
    {"name":"tokenId","type":"uint256"}
  ],"outputs":[{"name":"code","type":"uint8"}]},
  {"type":"function","stateMutability":"view","name":"statusOf","inputs":[
    {"name":"tokenId","type":"uint256"}
  ],"outputs":[{"name":"status","type":"uint8"}]},
  {"type":"function","stateMutability":"view","name":"locked","inputs":[
    {"name":"tokenId","type":"uint256"}
  ],"outputs":[{"name":"locked","type":"bool"}]}
]
```

Backwards Compatibility Notes

Wallets and explorers parsing ERC-721 will index these tokens; locked() improves UX by hiding transfer paths. Services parsing EIP-5484 burn-auth codes can reuse their logic.
