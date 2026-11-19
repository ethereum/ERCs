# Text injection cases

Executable examples for `erc.presign.text.injection` as specified in ERC-8481 at
`d62208962642407870b5272e0002f339f19de429`. Contributed by Ted (@haot3x), CC0-1.0.

From the repository root:

```sh
python3 assets/erc-8481/text-injection/test_injection.py
```

The suite has 26 tests and uses Python 3.9+ with no dependencies or network access.
It reuses the existing on-list Keccak implementation and coverage report fixtures.
Expected classes and consumer outcomes are written explicitly in the tests; there
is no command to regenerate expected results from the implementation.

## What the cases establish

- The same text in an on-chain token name and in supplied `agent.card` or
  `payment.description` text yields the same classes. Only the on-chain read has
  `at`; the caller provides provenance, not the field's spelling.
- A U+200B inside `Ignore` and fullwidth Latin letters match under the fixture's
  declared normalization. Removing or reordering those normalization steps changes
  the result. The entity digest always commits the original UTF-8 bytes.
- The six classes appear once each in the specification's order, independently of
  pattern order, textual order or repeated matching patterns.
- No match is `read` with `value: []`. No supported pattern set is `not-read` with
  `reason: unsupported`, without `value`. An explicitly requested set is not
  replaced by one the fixture happens to support.
- A set's hash commits its exact bytes. Reformatting the same JSON needs a new
  hash; SHA3-256 is not Keccak-256. Changed bytes cannot be used under the old hash.
- The existing undecoded ERC-7821 batch fixture remains partial even when its
  additional injection finding is read and empty. Altering coverage or the classes
  changes both the report hash and EIP-712 signing digest.
- Missing/unsupported findings, duplicate findings, another text entity, another
  pattern set and partial coverage hold the example consumer. A complete empty
  result only reaches `continue-other-checks`, never a safe-to-sign verdict.

## Fixture choices, not additional standard requirements

The ERC does not prescribe a pattern-document schema, a mandatory normalizer or a
universal detector. `pattern-set.json` deliberately defines a small local format:

1. Decode UTF-8 JSON. `fixtureVersion` is 1 and `matching` is `literal-substring`.
2. Apply `normalization` steps to the input text in their listed order:
   - `NFKC-3.2.0`: Unicode 3.2.0 NFKC using Python's bundled, frozen
     `unicodedata.ucd_3_2_0` database. This keeps the fixture independent of the
     Python release's current Unicode database; this is not a recommended detector
     policy or a requirement to use this old version.
   - `remove-U+200B`: remove exactly U+200B, not all format characters.
   - `ascii-lower`: replace U+0041–U+005A with U+0061–U+007A.
3. Match each nonempty `literal` by exact substring comparison against the resulting
   text. Literals are already written in their intended comparison form; no regex,
   word-boundary or language-model interpretation is used. Each distinct `id` maps
   to exactly one class. Collect matching classes in the ERC's fixed order.

The reverse-ordered patterns and the two `override` patterns are intentional.
Alternative step lists in individual tests are separately hashed pattern sets.
Unknown fixture normalization steps and classes fail locally; this is not a general
schema validator for every pattern-set format a source might publish.

`urn:erc-8481:fixture:text-injection:v1` resolves to the sibling `pattern-set.json`
in this offline harness, not to a deployed HTTP service. Its exact-byte Keccak is:

```text
0x11ecd756ad97373d3b0bb4ead1a027abf69bd63d3f3e00eb1a498e88be8eaf94
```

The hash was also checked with `@noble/hashes` 1.8.0's `keccak_256`. No additional
package is needed to run the suite. Publication/URI retrieval, source identity,
signature verification and on-chain reads are outside this harness. Chain and
block fields come from the existing synthetic coverage fixture.

The example consumer holds every partial report and every match. Those are its
own policy choices; the ERC permits consumers to accept certain gaps. It assumes
the preceding report/source/binding checks have passed, and it is not a complete
report verifier. The corpus intentionally includes an instruction that the small
pattern set misses: an empty result cannot establish that text is safe.

No specification, deployed detector, Solidity contract or existing checker is
changed. The separate malformed-coverage-field fix is not required by these cases.
