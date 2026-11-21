# ERC-8510 Inference Receipts: reference implementation and test vectors

Node 20 or later, no dependencies.

    node --test test.mjs        the reference implementation and the CLI against vectors.json

Keccak-256 and secp256k1 recovery are written out with BigInt, for clarity over speed: checking one receipt takes about
11 ms, so a day of 100,000 receipts takes about 20 minutes. Use a native library for volume.

## The library, `receipts.mjs`

For a verifier:

- `parseJson(text)`: JSON.parse that refuses repeated member names; read receipts, lists and records with it.
- `receiptProblem(receipt)`: why a receipt is invalid, or null.
- `receiptHash(receipt)` and `canonical(receipt)`: the leaf and the bytes it hashes.
- `listProblem(list)`: why a day list is invalid, or null.
- `verifyProof(receipt, proof, root)`: whether the root covers the receipt.
- `recordProblem(record)`: why a day record is not well-formed, or null.
- `recordListProblem(record, list)`: why a well-formed record does not state that list, or null.

For an issuer, as well:

- `readDay(text, day, signer)`: the receipts of a day file and how many lines are unreadable.
- `dayList(day, signer, receipts, unreadable, records)`: the list in day-list order, with count and root.
- `dayRoot(receipts)` and `proof(receipts, index)`: the root, and `{ leaf, proof, root }` for one receipt.
- `dayRecord(list)`: the record to publish; it throws while `unreadable` is not 0.

`keccak256`, `checksum`, `digest`, `recover` and `toHex` are the primitives under them.

## The CLI, `cli.mjs`

    node cli.mjs verify <receipt.json>                          the receipt is valid
    node cli.mjs root <day.jsonl> [<day> <signer>]              day, signer, count, root and unreadable of a day file
    node cli.mjs prove <day.jsonl> <index>                      leaf, proof and root of the receipt at that index of the day list
    node cli.mjs check <day-list.json>                          a served day list is valid
    node cli.mjs check-proof <receipt.json> <proof.json> <root> the root covers the receipt (proof.json: a list, or prove's output)
    node cli.mjs check-record <record.json> <day-list.json>     the record is well formed and states the list, which must be valid

Exit codes: 0 when the check passes, 1 when it fails or a file cannot be read, 2 for a usage mistake (a missing or
extra argument, an index that is not a whole number without leading zeros).

A day file holds one receipt per line, in any order; blank lines, CRLF line ends and a leading byte-order mark are fine.
`root` counts every other line that is not a valid receipt of the day and signer as unreadable. Given no day and
signer, it uses those of the first valid receipt and prints them; an empty file gives count 0 and root null. A day
with a non-zero `unreadable` cannot be published until those entries are resolved.

Reading a record out of a log is left to an RPC client. With Foundry, for the reference deployment's 2026-11-19 record:

    cast logs --from-block 3719 --to-block 3719 --address 0x770D6756CA8a1627FFf01B846383b13d6fa0c514 \
      'Inscribed(address indexed,string,bytes)' --rpc-url https://rpc.usebrainchain.com

Decode the log's `data` as `(string,bytes)` with `cast abi-decode --input "x(string,bytes)" <data>`, check the string
is `receipts` and the first topic after the event's is a stated publisher, and save the bytes as UTF-8 for
`check-record`.

## The vectors

`vectors.json` was made by signing receipts with a throwaway key, `keccak256("ERC inference receipts: test key, never
fund it")`, which is in the file. Signatures follow RFC 6979, so any library signing the same receipt hashes with that
key gives the same signatures. Besides five receipts with their canonical forms, hashes, day list, proofs and record,
the file holds:

- `edges`: valid receipts at the edges, probabilities 0, 1 and 0.000001 and a model with `"` and `\`;
- `textForms`: the first receipt written differently in JSON (`1.01e2`, `1.0`, members reordered), with the same hash;
- `equalAt`: two receipts with the same `at`, in day-list order by hash, and their root;
- `invalid`: receipts that each break one rule, with the reason; those that break a type or value rule are correctly
  signed, so the rule is what fails;
- `invalidLines`: JSON texts that repeat a member name, once written with an escape;
- `trees`: day roots over the first 2, 3 and 5 receipts;
- `repeatedPayment`: a valid receipt for a payment another receipt already covers;
- `public`: the reference deployment's day list for 2026-11-19 (with the `records` member added, since it was served
  before the member existed), one receipt whose hash is that day's root, and the day record as inscribed on chain with
  the log that carries it.

## Deployments

BrainChain's inference gateway on Robinhood Chain issues these receipts for calls paid in USDG over x402, signed by
`0x70D882879E1954Ac9A06b693379334Fd131B786D`. It serves its day lists at
`https://inference.usebrainchain.com/v1/receipts/<YYYY-MM-DD>` and publishes each closed day's record on BrainChain
(chain 274663) through `0x770D6756CA8a1627FFf01B846383b13d6fa0c514`, sent by
`0x70C665780E43BA1496a4E691e408F24844dB58eC`. Where it differs from the proposal: it returns the receipt in an
`X-BrainChain-Receipt` header, its records carry two more members, `brainchain` and `at`, and it served day lists before
they carried `records`.
