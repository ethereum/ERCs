# `address.on-list` list document vectors

Vectors for the list document of `erc.presign.address.on-list` as of commit `d21f46e` (with the answers of `9abaacf` and `d21f46e` to the open cases of `1810662`): account normalization,
the list hash, matching and `value`, not-read reasons, conformance, and diffs between list versions.

```sh
python3 onlist_vectors.py           # check all vector files (Python 3.9+, standard library only)
python3 onlist_vectors.py --write   # regenerate them; output is deterministic
```

The script carries its own keccak256 (Keccak padding, not SHA3-256), RFC 8785 canonicalization (no floats are
used), bech32/bech32m and base58, so nothing needs installing. Its self-test checks keccak256 of `""` and `"abc"`,
the EIP-55 examples, and the RFC 8785 key order. The hashes were also recomputed independently with
`@noble/hashes` and `@scure/base`, and all of them agree.

## What is computed

- **Account**: `eip155` lowercase hex, `bech32` lowercase, `base58` as written. Inside `bip122` an address is
  `bech32` when it is a valid BIP-173 or BIP-350 address, `base58` otherwise. Other namespaces (not `eip155`,
  `bip122` or `solana`) are kept exactly as written; no CAIP-10 profile normalization is applied. An entry must be
  CAIP-10, and the chain reference may be `*`. Not valid, so the list does not conform: a mixed-case EVM address
  that is not a valid EIP-55 checksum, an upper-case `0X` prefix, a mixed-case `bech32` address, an `eip155`
  reference with a leading zero.
- **List hash**: `digest(list)` = `keccak256` of the RFC 8785 bytes of the document, taken after each `account` is
  normalized, entries are sorted by `account` in code point order, and entries equal after normalization are merged.
  The hash is over the parsed value, so white space and key order in the published bytes do not change it. Two
  entries with the same normalized `account` but different content make the list non-conforming. Extra top-level
  fields are allowed, hashed, and ignored by readers.
- **Match**: the namespaces are equal, the chain references are equal or the entry's is `*`, and the normalized
  addresses are equal. `value` is the matching entry in normalized form, or `null`. When `eip155:1:X` and
  `eip155:*:X` both match, `value` is the entry with the exact chain reference. A list with no entries conforms,
  and every address reads `null` against it.
- **Document evidence**: the `hash` of the upstream publication's `document` evidence entry is `keccak256` of the
  raw bytes the source read at `retrievedAt` (not SHA3-256, no parsing or re-encoding). Two fetches of a page that
  re-renders give two hashes; the list pinned from both has one.
- **Not read**: `unavailable` when the list cannot be fetched, its normalized digest differs from `hash`, or it does
  not conform (even when the hash matches). `unsupported`, for
  each address, when the consumer asked for a list with `{ kind, param }` that the source will not read.

## Files

| File | Vectors | Open |
| --- | --- | --- |
| `normalize.json` | 25 normalization cases (EVM checksum, upper case and `*`; bech32/bech32m upper to lower; base58 exact incl. P2SH; another namespace kept as written; whitespace, namespace case, bare address, bad EIP-55 checksum, `0X`, `eip155:01`, mixed-case and bad-checksum bech32) and 10 `bip122` encoding cases (`classification`: P2WPKH lower/upper, P2TR, P2PKH, P2SH, a bad bech32 checksum, witness v1 with a bech32 checksum, v0 with a bech32m checksum, mixed case) | 0 |
| `list-hash.json` | 15: the draft's `0xAbC`/`0xabc` case, order, `*` sorting, chain scope, bech32 and base58 case, attestation, two sources pinning one list, extra fields, published bytes vs JCS, duplicates with different content, case variants in another namespace (two entries, two hashes), an empty list, and the FBI list | 0 |
| `match.json` | 15 matches (incl. exact chain reference over `*`, another namespace exact and case-different), 7 finding scenarios (incl. a non-conforming list with a matching hash, an extra top-level field, an empty list reading `null` in four namespaces), 7 conformance cases, and 3 `document` evidence hashes (`documentEvidence`) | 0 |
| `upstream-page.fetch1.html.txt`, `upstream-page.fetch2.html.txt` | Two fetches of one synthetic upstream page that re-renders (timestamp, nonce): raw-byte fixtures for the `document` evidence hash | |
| `diff.json` | 8 diffs from one v1: added, removed, both, re-case/reorder only, duplicate, scope narrowed, criteria changed, evidence added (informative format) | 0 |
| `fbi-tradertraitor-2026-10-31.published.txt` | The 628 addresses of the FBI alert of 31 Oct 2026 (608 ETH, 19 BTC, 1 SOL), in its order and case | |
| `fbi-tradertraitor-2026-10-31.list.json` | That alert as one attested list document (ETH as `eip155:*`), in canonical bytes; hash `0x7d7ec0b77a2a47b76dab2b4b6ba067aba76c9e3e60d86bde5676af609e068c98` | |

Each vector has `basis`. `spec` means the draft states the rule. `reference` means the draft is silent and this
implementation made a choice, which is listed below. Cases under `open` have no expected value and are not checked.
Synthetic addresses come from `keccak256("erc-8481 on-list vector …")`, and the `example.org` URIs are placeholders.
The FBI addresses are public. Source: <https://www.fbi.gov/investigate/cyber/alerts/2026/north-korea-responsible-for-6-billion-binance-attack>.

## Resolved in `d21f46e`

The four cases still marked as our call after `9abaacf` now follow the draft text at `d21f46e`:

| Was our call | Ruling (draft text at `d21f46e`) | Vectors |
| --- | --- | --- |
| Empty `entries` (Q7) | conforms; `on-list` reads `null` for every address | `list-hash.json` `empty-entries` (now `basis: spec`), `match.json` `empty-list-reads-null`, `empty-list-conforms`, `empty-list-without-attestation-conforms` |
| bech32 vs base58 in `bip122` | `bech32` when a valid BIP-173/350 address, `base58` otherwise | `normalize.json` `classification`, `base58-btc-p2sh` |
| Namespaces covered | others compared exactly as written, unless their CAIP-10 profile defines a normalization | `normalize.json` `other-namespace-*`, `list-hash.json` `other-namespace-*`, `match.json` `other-namespace-*` (list `L3`) |
| `document` evidence hash (Q8) | `keccak256` of the bytes the source read at `retrievedAt` | `match.json` `documentEvidence` (two fixture files and a CRLF variant; `notSha3_256` guards against the wrong hash) |

Still our call, not ruled by the text:

- A `bip122` string that is not a valid BIP-173/350 address and not valid base58check either (for example a
  bech32 address with one wrong checksum character). The encoding rule calls it `base58`; this implementation
  treats it as not valid CAIP-10, so the list does not conform (`normalize.json` `reject-bad-bech32-checksum`,
  `basis: reference`).
- `xmpl` in the other-namespace vectors is a placeholder namespace with no CAIP-10 profile. Whether a real
  namespace's profile "defines a normalization" is not decided here; no such normalization is applied.

A mixed-case `bech32` address is not a valid BIP-173 address, so the encoding rule calls it `base58`
(`classification` `mixed-case-bech32-is-base58`); the list still does not conform, since the draft names that case as
invalid. No earlier expected value changed; the lists `L` and `L2` and the FBI list hash are unchanged. The
`document` evidence example now carries computed hashes in place of a placeholder.

## Resolved in `9abaacf`

The 7 open cases of the first version now have expected values. Six follow the draft text at `9abaacf`; the empty
list is not ruled there and stays this implementation's call:

| Was open | Ruling (draft text at `9abaacf`) | Vector |
| --- | --- | --- |
| Bad EIP-55 checksum (Q2) | mixed-case EVM address with a bad checksum: list does not conform | `normalize.json` `reject-evm-bad-checksum`, `match.json` `bad-eip55-entry-fails` |
| `0X` prefix (Q2) | not valid CAIP-10 for `eip155`: list does not conform | `normalize.json` `reject-evm-0X-prefix` |
| `eip155:01` (Q4) | leading zero in the chain reference: list does not conform | `normalize.json` `reject-chain-ref-leading-zero` |
| Duplicate with different evidence (Q5) | list does not conform | `list-hash.json` `duplicate-different-evidence-nonconforming` |
| Empty `entries` (Q7) | not ruled in `9abaacf`; our call: conforms (`basis: reference`) | `list-hash.json` `empty-entries` |
| Two entries match (Q5) | the exact chain reference wins | `match.json` `two-entries-exact-chain-wins` |
| Non-conforming list, hash matches (Q7) | not read / `unavailable` | `match.json` `nonconforming-hash-match-unavailable` |

Also from `9abaacf`: the hash is over the normalized parsed value and publishers SHOULD publish the normalized form
(Q1); extra top-level fields are allowed, hashed and ignored (Q6); `criteria` SHOULD quote the upstream verbatim
(Q10); the diff format stays informative (Q9). Still `basis: reference`: how bech32 and base58 are told apart in
`bip122`, which namespaces are covered, the empty list, and the `document` evidence hash (Q8); all four are ruled in
`d21f46e` (above). No hash in the first version changed; the FBI list hash is still `0x7d7ec0b7…8c98`.

License: CC0-1.0 (the script and the vectors). Contributed by the RUNECLAW team.
