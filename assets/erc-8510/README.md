# ERC-8510 Inference Receipts: reference implementation and test vectors

Node 20 or later, no dependencies.

    node --test test.mjs        the reference implementation and the CLI against vectors.json

`receipts.mjs` holds everything the proposal defines: the canonical form, the receipt hash, the signature check, day
lists in day-list order, day roots, inclusion proofs and day records, and a JSON reader that refuses repeated member
names. Keccak-256 and secp256k1 recovery are written out with BigInt, for clarity over speed: checking one receipt takes
about 11 ms, so a day of 100,000 receipts takes about 20 minutes. Use a native library for volume.

`cli.mjs` runs them on files:

    node cli.mjs verify receipt.json          the receipt is valid
    node cli.mjs root day.jsonl               count, root and unreadable lines of a day file, one receipt per line, any order
    node cli.mjs prove day.jsonl 4            the leaf, proof and root for the receipt at index 4 of the day list
    node cli.mjs check day-list.json          a served day list: its shape, every receipt, their order, count and root

Exit codes: 0 when the check passes, 1 when it fails or a file cannot be read, 2 for a usage mistake. `root` and `prove`
refuse a file whose readable receipts are not all valid receipts of one day and one signer. Blank lines, CRLF line ends
and a leading byte-order mark are accepted; a line that is not JSON, repeats a member name or is not an object is counted
as unreadable.

## The vectors

`vectors.json` was made by signing five receipts with a throwaway key, `keccak256("ERC inference receipts: test key,
never fund it")`, which is in the file. Signatures follow RFC 6979, so any library signing the same receipt hashes with
that key gives the same signatures. The file also holds:

- `invalid`: receipts that each break one rule, with the reason; those that break a type or value rule are correctly
  signed, so the rule is what fails;
- `invalidLines`: JSON text a verifier must refuse before reading it as a receipt;
- `trees`: day roots over the first 2, 3 and 5 receipts;
- `repeatedPayment`: a valid receipt for a payment another receipt already covers;
- `public`: the reference deployment's day list for 2026-11-19, one receipt whose hash is that day's root, and the day
  record as inscribed on chain, with the log that carries it.
