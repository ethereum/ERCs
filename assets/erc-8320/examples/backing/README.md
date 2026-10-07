# ERC-8320 BACKING schema example: credit-backed instruments

Informative example, not part of the normative standard. It shows one way to define a canonical schema for the `data` object of a BACKING claim about a credit-backed instrument (a promissory note, a receivables pool, a loan), so that integrators have a concrete reference and consumer logic can be tested for reuse across issuers. It came out of the discussion thread for this ERC.

| File | Contents |
|---|---|
| `backing.credit.v2.schema.json` | JSON Schema (2020-12) for the `data` object |
| `sample-receivables-pool-nominal.json` | Receivables pool, nominal figures, single currency |
| `sample-collateral-appraised.json` | Loan backed by appraised collateral in a different currency, with a reference to the VALUATION claim |
| `sample-guarantee.json` | Guarantee without coverage figures, and an encumbrance whose beneficiary is unknown |

All sample values are synthetic.

## Design choices

**Structure, not adequacy.** The schema fixes how a backing attestation is expressed. It does not decide whether the backing is enough. FX assumptions, haircuts and coverage thresholds stay with the consumer.

**Coverage is conditionally required.** `coverage` is required for `RESERVES`, `COLLATERAL` and `RECEIVABLES_POOL`, so missing figures cannot pass as a clean backing. It is optional for `GUARANTEE` and `OTHER`, where the backing is often a cap or a commitment rather than a measured amount.

**Native currencies, no converted figure.** `backedAmount` and `referenceAmount` each carry their own ISO 4217 currency. The schema has no field for a pre-converted amount: choosing a rate, its timestamp and an FX haircut is an adequacy decision, and it belongs to the consumer.

**`NOMINAL` vs. `APPRAISED`.** `coverage.basis` states how `backedAmount` was measured. `NOMINAL` is a face value or outstanding balance that can be checked against documents or a ledger. `APPRAISED` means the amount depends on an appraisal or mark; in that case `valuationRef` must point to the VALUATION claim that carries it (`chainId`, registry, `assetId`, version, and optionally its `contentHash`). The appraisal is then signed by the party accountable for it, and the BACKING author does not carry a valuation under its own name. A consumer resolving `valuationRef` should read the referenced claim's state when it evaluates: revocation or expiry of the VALUATION claim does not change this BACKING claim on-chain.

**Encumbrance is about the backed instrument.** `encumbrance` reports a competing charge on the asset the claim is about, not the security interest that constitutes the backing. An encumbrance whose beneficiary is unknown is recorded with `beneficiaryKnown: false`. A consumer reading `status != NONE` or `beneficiaryKnown == false` should treat the backing as not clean.

**Records, not certifications.** `evidence.contentHash` binds the claim to an exact evidence package; it does not state that the evidence proves the right. `encumbrance` records an attested status; it does not constitute or perfect a charge. `holderRef` is the holder as recorded, published only as a salted commitment; it does not replace the instrument's own law of circulation. `instrument.jurisdiction` is a field, so the same schema serves instruments under different laws.

The attestor is identified by the claim's `author` and the envelope's `attestorProfile`, so the schema carries no attestor field.

## Identifiers

```
schemaId   = keccak256("erc8320.backing.credit.v2")
           = 0xf8d52ce839f9cd138e0870ac859214827049064c10d86fe04977bba2fff89293
schemaHash = keccak256(exact bytes of backing.credit.v2.schema.json)
           = 0x1085ab88a615dd33bf22d66715c736093906ec2a5afa043e6f6648fa39928fe0
```

Reproduce `schemaHash` with `cast keccak 0x$(xxd -p backing.credit.v2.schema.json | tr -d '\n')`. Any change to the file, including whitespace, changes the hash, so once merged the file is frozen and any change ships as a new file with a new `schemaId` and `schemaHash`. A v1 circulated in the discussion thread; v2 is the first version published here. The samples carry `schemaId` in the envelope as the same `bytes32` value stored on-chain.

## Validate

The schema applies to the `data` object, not to the whole envelope:

```sh
jq .data sample-collateral-appraised.json > data.json
npx ajv-cli@5 validate --spec=draft2020 -s backing.credit.v2.schema.json -d data.json
```

## Open questions

- Backing held in units without an ISO 4217 code (stablecoins, commodities, other assets in kind).
- Whether `GUARANTEE` should get its own shape, such as a cap amount, instead of optional `coverage`.
