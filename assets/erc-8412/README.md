# ERC-8412 reference implementation and conformance vectors

Everything here is CC0, like the specification.

```
contracts/
  PreregisteredCriteria.sol   reference registry (§6, E1–E14)
  test/Vectors.t.sol          GENERATED Foundry suite: every on-chain vector on the EVM
  foundry.toml
model/
  registry.py                 executable model of the registry, mirrors the contract
  ethcrypto.py                dependency-free keccak256, secp256k1, EIP-712, JCS
  test_ethcrypto.py           known-answer tests against published vectors
verifier/
  verify.py                   reference off-chain verifier (O1–O5 and document checks)
vectors/
  onchain/<INV>.json          cases for E1–E14, duplicate and id rules, positive paths
  offchain/<name>.json        complete document packages for O1–O5 and well-formedness
tools/
  run_all.py                  runs every check below
  gen_onchain_vectors.py      builds on-chain vectors, validated against the model
  gen_offchain_vectors.py     builds off-chain packages, validated against the verifier
  gen_foundry_tests.py        translates on-chain vectors into Vectors.t.sol
  mutation_test.py            proves every invariant is exercised
```

## Run

No dependencies beyond Python 3.10:

```
python tools/run_all.py
```

On the EVM with Foundry:

```
cd contracts
forge install foundry-rs/forge-std --no-git
forge test
```

`Vectors.t.sol` places the registry at the vectors' registry address and sets
the vectors' chain id, so the `preregistrationId` in `ID.json` matches byte for
byte.

## Vector format

**On-chain** (`vectors/onchain/*.json`): a list of cases. Each case names the
invariant it targets and a level (`MUST` or `SHOULD`), and is a sequence of
steps with a block timestamp, a sender, arguments and an expectation.
`"$p1"` refers to the `preregistrationId` bound by an earlier step. Actors are
EOAs derived as `vm.addr(uint256(keccak256("erc8412:<name>")))`; `zero` is
`address(0)`. A step expecting `revert` must revert; the tag records which
invariant the case targets, but conformance does not depend on the revert
reason, since implementations may check invariants in a different order.

**Off-chain** (`vectors/offchain/*.json`): one package per file: on-chain
state, criteria document, evidence bundle and attestation document, with real
keccak256 digests and real EIP-712 waiver signatures. `expect.violations` lists
the rules a conforming checker must report. `chainAccepts` records whether the
registry alone would accept the same preregistration and attestation. For
every refuted package in this set it would, which is why §8 exists.

## What mutation testing shows

`tools/mutation_test.py` switches off one invariant at a time in the model and
re-runs every on-chain vector. Each mutation must make at least one vector fail.
It also replays the pre-fix expiry text (`resolveExpired` allowed at
`block.timestamp == expiry`, no terminal-verdict guard) and confirms the vectors
catch the overwrite reported in review.

## Scope notes

- The off-chain verifier mechanises O2 only as far as documents allow:
  required capture-metadata keys, `notBefore`, `mediaType`. It does not open
  salted commitments or inspect media.
- O4 is mechanised for the standard decision rules. Namespaced rules are
  reported as unchecked rather than refuted.
- `ethcrypto.py` exists so the vectors can be generated and checked without
  third-party packages. It is not constant-time and is not for production keys.
- The contract is reference code: unaudited and not gas-optimised.
