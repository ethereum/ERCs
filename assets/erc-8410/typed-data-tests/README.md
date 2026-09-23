# Typed-data signature request vectors

Run from this directory with Node.js 20 or later:

```sh
npm ci --ignore-scripts
npm test
```

Dependencies are pinned in `package-lock.json`. No keys, RPC endpoint, wallet,
or producer connection are used. The `.example` endpoints are illustrative and
are never contacted. Permit and order fixtures describe a fictional protocol,
not Aave's deployed contracts or API.

The runner validates all four new structural schemas, recomputes signing hashes
with ethers and viem, independently reconstructs the domain/message commitment,
and checks the fixed-order request digest against the committed vectors. It
checks the original execution-plan schema and recomputes all original digests.
Mutation assertions document which changes affect each identity.

It also exercises request/result/delivery/receipt schema rejection cases and
the separation of signing requests from execution plans. Schemas check shape,
not all semantics: this fixture runner is not a production parser or a delivery
implementation. In particular, duplicate JSON keys, recursive member/type
validation, Unicode validity, URL/DNS admission, origin authentication, policy,
expiry timing, signature validation, and durable relay idempotency need their
own implementation tests in a consuming wallet or producer.

The vectors contain a baseline permit, JSON object reordering, hexadecimal
case normalization, domain changes, signer and amount changes, wallet cutoff
changes, delivery and request-ID changes, large integers, chainless typed data,
and a second-round order containing two concrete approval signature byte
strings. The latter bytes are illustrative, not usable authorizations.
