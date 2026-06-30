# ERC-8097 Reference Implementation

Reference Solidity implementation for `ERC-8097: In-Ground Asset Token`.

## Files

- `contracts/IERC-8097.sol` — Interface, enums, and Solidity structs
- `contracts/ERC-8097.sol` — Reference implementation
- `test/ERC-8097.t.sol` — Foundry tests
- `foundry.toml` — Foundry configuration

## Lifecycle

Assets are created and anchored in two phases:

```text
register()             -> INDEXED
advanceLifecycle()     -> CLAIMED
advanceLifecycle()     -> VERIFIED
anchor()               -> ANCHORED
```

`advanceLifecycle()` advances exactly one step and cannot set `ANCHORED`.
Only `anchor()` can set `ANCHORED`, and only after the asset reaches `VERIFIED`.

## Normative Rules Covered

| Rule | Implementation |
|---|---|
| R-FORBIDDEN-TERMS | Forbidden terms excluded from ABI names and runtime strings |
| R-LIFECYCLE-MONOTONIC | `advanceLifecycle()` is single-step only; `anchor()` sets `ANCHORED` |
| R-PRODUCTION-TRANSITIONS | Explicit transition table, including `PRODUCTION <-> CARE_AND_MAINTENANCE` |
| R-DEPLETION-MONOTONIC | `updateDepletion()` only accepts values greater than current depletion |
| R-CP-EIP712 | CP/QP attestation uses EIP-712 typed data |
| R-CP-IDENTITY | Professional-body membership remains off-chain |
| R-CP-REPLAY | Used EIP-712 digests cannot be submitted again |
| R-CP-OBJECT-MATCH | Attested object hash must match the asset's current hashes |
| R-REPORT-REQUIRED | `anchor()` requires `reportPdfHash` and `reportIpfsUri` |
| R-SCORE-RANGE | `currentScore` must be `0..1000` |
| R-SLUG-UNIQUE | `mineSlug` is unique at registration |
| R-REANCHOR-HISTORY | Latest hashes are stored; historical hashes remain in events |
| R-NO-SCORING | Score computation is off-chain |
| R-NO-RISK-ASSESSMENT | Contract anchors records; it does not evaluate merit or risk |
| R-FRESHNESS-OFFCHAIN | Freshness decay is off-chain |

## Forbidden-Term CI

NatDoc comments may mention forbidden terms to describe the rule. CI should
therefore check ABI names and quoted runtime strings, not every source comment.

```bash
forge inspect ERC8097 abi | grep -i "HIGH_RISK\|RISK_BAND" \
  && echo "ERROR: forbidden term in ABI" && exit 1 || echo "OK: ABI clean"

grep -En '"[^"]*HIGH_RISK[^"]*"|"[^"]*RISK_BAND[^"]*"' contracts/*.sol \
  && echo "ERROR: forbidden term in runtime string" && exit 1 || echo "OK: strings clean"
```

## On-Chain vs Off-Chain

```text
ON-CHAIN:
  Asset lifecycle and slug identity
  IRO / IGO / ICO / IEXO / IEO / SML hashes
  Report PDF hash and IPFS URI
  CP/QP EIP-712 attestations
  Attestation replay prevention
  Object-hash matching
  Production transition enforcement
  Depletion monotonicity
  Informational currentScore

OFF-CHAIN:
  Full object JSON
  Document extraction
  IGA Score computation
  Decay lambdas and freshness model
  JORC Table 1 assessment
  Intelligence signal classification
  CP/QP professional-body identity verification
  Registry views
```

## Install

```bash
forge install OpenZeppelin/openzeppelin-contracts
```

## Test

```bash
forge build
forge test -vv
forge test --fuzz-runs 1000 -vv
```

## Deployment

Target: Base chain (`8453`).

```bash
forge create contracts/ERC-8097.sol:ERC8097 \
  --constructor-args <deployer_address> \
  --rpc-url https://mainnet.base.org \
  --private-key $DEPLOYER_KEY
```

This is a reference implementation only. Do not deploy to production without an
independent security audit and an operational policy for relayers and CP/QP
identity verification.

## License

CC0-1.0
