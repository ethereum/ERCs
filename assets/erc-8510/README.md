# Inference Receipts: reference implementation and test vectors

Node 20 or later, no dependencies.

    node --test test.mjs        the reference implementation against vectors.json

`receipts.mjs` holds everything the proposal defines: the canonical form, the receipt hash, the signature check
(Keccak-256 and secp256k1 recovery written out with BigInt, for clarity over speed), day lists, day roots, inclusion
proofs and day records.

`cli.mjs` runs them on files:

    node cli.mjs verify receipt.json          the receipt is valid
    node cli.mjs root day.jsonl               count, root and unreadable lines of a day file (one receipt per line)
    node cli.mjs prove day.jsonl 4            the proof for the fifth receipt, checked against the root
    node cli.mjs check day-list.json          a served day list: every receipt valid, of its day and signer, count and root right

## The vectors

`vectors.json` was made by signing five receipts with a throwaway key, `keccak256("ERC inference receipts: test key,
never fund it")`, which is in the file. Signatures follow RFC 6979, so any library signing the same receipt hashes with
that key gives the same signatures. The file also lists six invalid receipts with the rule each breaks, and the
reference deployment's public day list for 2026-11-19: one receipt, whose hash is the root of that day's record.
