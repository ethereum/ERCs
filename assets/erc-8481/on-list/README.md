# `address.on-list` list document vectors

Vectors for the list document of `erc.presign.address.on-list` as of commit `1810662`: account normalization,
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
  chain reference may be `*`.
- **List hash**: `digest(list)` = `keccak256` of the RFC 8785 bytes of the document, taken after each `account` is
  normalized, entries are sorted by `account` in code point order, and duplicates are dropped.
- **Match**: the namespaces are equal, the chain references are equal or the entry's is `*`, and the normalized
  addresses are equal. `value` is the matching entry (the whole entry object, as in the normalized list), or `null`.
- **Not read**: `unavailable` when the list cannot be fetched or its digest differs from `hash`. `unsupported`, for
  each address, when the consumer asked for a list with `{ kind, param }` that the source will not read.

## Files

| File | Vectors | Open |
| --- | --- | --- |
| `normalize.json` | 19 normalization cases (EVM checksum, upper case and `*`; bech32/bech32m upper to lower; base58 exact; whitespace, namespace case, bare address, bad checksum) | 3 |
| `list-hash.json` | 11: the draft's `0xAbC`/`0xabc` case, order, `*` sorting, chain scope, bech32 and base58 case, attestation, two sources pinning one list, published bytes vs JCS, and the FBI list | 2 |
| `match.json` | 9 matches, 4 finding scenarios (7 findings), 3 conformance cases, and a `document` evidence example | 2 |
| `diff.json` | 8 diffs from one v1: added, removed, both, re-case/reorder only, duplicate, scope narrowed, criteria changed, evidence added | 0 |
| `fbi-tradertraitor-2026-10-31.published.txt` | The 628 addresses of the FBI alert of 31 Oct 2026 (608 ETH, 19 BTC, 1 SOL), in its order and case | |
| `fbi-tradertraitor-2026-10-31.list.json` | That alert as one attested list document (ETH as `eip155:*`), in canonical bytes; hash `0x7d7ec0b77a2a47b76dab2b4b6ba067aba76c9e3e60d86bde5676af609e068c98` | |

Each vector has `basis`. `spec` means the draft states the rule. `reference` means the draft is silent and this
implementation made a choice, which is listed below. Cases under `open` have no expected value and are not checked.
Synthetic addresses come from `keccak256("erc-8481 on-list vector …")`, and the `example.org` URIs are placeholders.
The FBI addresses are public. Source: <https://www.fbi.gov/investigate/cyber/alerts/2026/north-korea-responsible-for-6-billion-binance-attack>.

## Open questions

1. **Bytes or value.** The text says that `hash` is `digest` of the document, and that a list "whose bytes do not
   match" is unavailable. These vectors hash the parsed and normalized value, so the whitespace of the published
   bytes does not matter. Should the published document already be in normalized form, or does the reader normalize
   it? If the reader normalizes, "as written in the list" for `value` means the normalized entry.
2. **EVM input.** Should a mixed-case address with a wrong EIP-55 checksum be lowercased or rejected? Is `0X` valid?
3. **bech32.** These vectors reject mixed case, as BIP-173 does. How does a reader tell bech32 from base58 inside a
   namespace (`bip122` has both), and which namespaces are in scope?
4. **Chain reference.** Is `eip155:01` the same as `eip155:1`? The CAIP-2 reference grammar has no `*`, so the
   draft extends it.
5. **Duplicates and multiple matches.** What happens when one account appears twice with different `evidence`?
   And when `eip155:1:X` and `eip155:*:X` both match, which entry is `value`?
6. **Other fields.** May a list carry fields beyond the five? They would be hashed, so a `retrievedAt` field would
   change the hash.
7. **Non-conforming list.** When the bytes match `hash` but the list does not conform (no `attestation` and no
   `evidence`, or a non-CAIP-10 account), which not-read reason applies? Does an empty `entries` conform?
8. **Document evidence.** Is `hash` in the `document` evidence the keccak256 of the page bytes this source read?
   Does an `on-list` finding carry `at`?
9. **Diffs.** The draft defines no diff. The format here (`added`, `removed`, `changed`, `metadataChanged` by
   normalized account) is a suggestion.
10. **Same hash from two sources.** `source`, `criteria` and `attestation` are free text, so two sources get the
    same hash only if they copy the same strings. These vectors use the alert's sentences verbatim. Should the draft
    say "verbatim upstream text"?

License: CC0-1.0 (the script and the vectors). Contributed by the RUNECLAW team.
