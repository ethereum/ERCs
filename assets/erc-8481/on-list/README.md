# `address.on-list` list document vectors

Vectors for the list document of `erc.presign.address.on-list` as of commit `9abaacf` (the answers to the open cases of `1810662`): account normalization,
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

- **Account**: `eip155` lowercase hex, `bech32` lowercase, `base58` as written. An entry must be CAIP-10, and the
  chain reference may be `*`. Not valid, so the list does not conform: a mixed-case EVM address that is not a valid
  EIP-55 checksum, an upper-case `0X` prefix, a mixed-case `bech32` address, an `eip155` reference with a leading zero.
- **List hash**: `digest(list)` = `keccak256` of the RFC 8785 bytes of the document, taken after each `account` is
  normalized, entries are sorted by `account` in code point order, and entries equal after normalization are merged.
  The hash is over the parsed value, so white space and key order in the published bytes do not change it. Two
  entries with the same normalized `account` but different content make the list non-conforming. Extra top-level
  fields are allowed, hashed, and ignored by readers.
- **Match**: the namespaces are equal, the chain references are equal or the entry's is `*`, and the normalized
  addresses are equal. `value` is the matching entry in normalized form, or `null`. When `eip155:1:X` and
  `eip155:*:X` both match, `value` is the entry with the exact chain reference.
- **Not read**: `unavailable` when the list cannot be fetched, its normalized digest differs from `hash`, or it does
  not conform (even when the hash matches). `unsupported`, for
  each address, when the consumer asked for a list with `{ kind, param }` that the source will not read.

## Files

| File | Vectors | Open |
| --- | --- | --- |
| `normalize.json` | 22 normalization cases (EVM checksum, upper case and `*`; bech32/bech32m upper to lower; base58 exact; whitespace, namespace case, bare address, bad EIP-55 checksum, `0X`, `eip155:01`, mixed-case and bad-checksum bech32) | 0 |
| `list-hash.json` | 13: the draft's `0xAbC`/`0xabc` case, order, `*` sorting, chain scope, bech32 and base58 case, attestation, two sources pinning one list, extra fields, published bytes vs JCS, duplicates with different content, an empty list, and the FBI list | 0 |
| `match.json` | 11 matches (incl. exact chain reference over `*`), 6 finding scenarios (incl. a non-conforming list with a matching hash, an extra top-level field), 5 conformance cases, and a `document` evidence example | 0 |
| `diff.json` | 8 diffs from one v1: added, removed, both, re-case/reorder only, duplicate, scope narrowed, criteria changed, evidence added (informative format) | 0 |
| `fbi-tradertraitor-2026-10-31.published.txt` | The 628 addresses of the FBI alert of 31 Oct 2026 (608 ETH, 19 BTC, 1 SOL), in its order and case | |
| `fbi-tradertraitor-2026-10-31.list.json` | That alert as one attested list document (ETH as `eip155:*`), in canonical bytes; hash `0x7d7ec0b77a2a47b76dab2b4b6ba067aba76c9e3e60d86bde5676af609e068c98` | |

Each vector has `basis`. `spec` means the draft states the rule. `reference` means the draft is silent and this
implementation made a choice, which is listed below. Cases under `open` have no expected value and are not checked.
Synthetic addresses come from `keccak256("erc-8481 on-list vector …")`, and the `example.org` URIs are placeholders.
The FBI addresses are public. Source: <https://www.fbi.gov/investigate/cyber/alerts/2026/north-korea-responsible-for-6-billion-binance-attack>.

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
`bip122`, which namespaces are covered, the empty list, and the `document` evidence hash (Q8). No hash in the first
version changed; the FBI list hash is still `0x7d7ec0b7…8c98`.

License: CC0-1.0 (the script and the vectors). Contributed by the RUNECLAW team.
