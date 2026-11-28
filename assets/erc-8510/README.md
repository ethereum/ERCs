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
- `findRecord(rpcUrl, list, { chunk, fetch })`: the day's record on chain, found as the spec says, or null before there
  is one; plain JSON-RPC over `fetch`, `chunk` blocks per `eth_getLogs` (50,000 by default).

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
    node cli.mjs find-record <rpc-url> <day-list.json> [<n>]    the day's record on chain, checked against the list; n blocks per query

Exit codes: 0 when the check passes, 1 when it fails, a file cannot be read or no record is on chain yet, 2 for a usage
mistake (a missing or extra argument, an index or block count that is not a whole number without leading zeros).

A day file holds one receipt per line, in any order; blank lines, CRLF line ends and a leading byte-order mark are fine.
`root` counts every other line that is not a valid receipt of the day and signer as unreadable. Given no day and
signer, it uses those of the first valid receipt and prints them; an empty file gives count 0 and root null. A day
with a non-zero `unreadable` cannot be published until those entries are resolved.

`find-record` reads the chain, contract and publishers from the list's `records`, checks the RPC serves that chain,
finds the first block after the day closed by binary search on block timestamps, and scans the contract's `Inscribed`
logs from those publishers forward from there. It prints the record with its block, log index and transaction, then
checks it against the list:

    node cli.mjs find-record https://rpc.example.com day-list-2026-11-19.json

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
- `findRecord`: a mocked chain holding the real 2026-11-19 record log and the logs a verifier must skip around it;
- `repeatedPayment`: a valid receipt for a payment another receipt already covers;
- `public`: a running issuer's day list for 2026-11-19 (with the `records` member added, since it was served before the
  member existed), one receipt whose hash is that day's root, and the day record as published on chain with the log
  that carries it.
