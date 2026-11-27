# `address.on-list` list document vectors

Vectors for the list document of `erc.presign.address.on-list`: account normalization, the list hash, matching and `value`, not-read reasons, conformance, and diffs between list versions.

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
  CAIP-10, except that the chain reference may be `*`. Not valid, so the list does not conform: a mixed-case EVM
  address that is not a valid EIP-55 checksum, an upper-case `0X` prefix, a mixed-case `bech32` address, an `eip155`
  reference with a leading zero, and a `bip122` string that is neither a valid BIP-173/350 address nor valid
  Base58Check.
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

Each vector has `basis`. `spec` means the proposal states the rule. `reference` means the proposal is silent and
this implementation made a choice, listed below. Cases under `open` have no expected value and are not checked; there
are none. Synthetic addresses come from `keccak256("erc-8481 on-list vector …")`, and the `example.org` URIs are
placeholders. The FBI addresses are public; the list document's `source` names the alert they were taken from.

Choices of this implementation (`basis: reference`):

- `reject-short-hex`: an `eip155` address of 39 hex digits is not valid CAIP-10.
- `xmpl` in the other-namespace vectors is a placeholder namespace with no CAIP-10 profile, so no normalization is
  applied to it.
- The diff format of `diff.json` is informative; the proposal defines no diff.

License: CC0-1.0 (the script and the vectors). Contributed by the RUNECLAW team.
