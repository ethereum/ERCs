# ERC-8262 Reference Implementation

Oracle, verifier router, interfaces, and one circuit for ERC-8262
(Zero-Knowledge Compliance Oracle). Licensed CC0-1.0, except
`contracts/interfaces/IUltraVerifier.sol`, which mirrors the ABI of a
Barretenberg-generated verifier and is Apache-2.0.

## Layout

```
contracts/
  ERC8262Oracle.sol           oracle: submission, per-type public-input validation,
                              attestation storage, validation registries
  ERC8262Verifier.sol         router: per-proof-type verifier registry + version history
  interfaces/
    IERC8262Verifier.sol      verifier router interface
    IERC8262Oracle.sol        oracle interface
    IERC165.sol               ERC-165 interface
    IUltraVerifier.sol        per-circuit verifier ABI (Apache-2.0)
  libraries/
    ProofTypes.sol            proof-type IDs + public-input shape validation
    JurisdictionConfig.sol    per-jurisdiction thresholds and signed-signal policy
    AccessControl.sol         GUARDIAN / REGISTRAR / CONFIG roles
    EIP712Attestation.sol     EIP-712 typed-data hashing for attestations
    EIP712CredentialRoot.sol  EIP-712 typed-data hashing for credential roots
    Ownable2Step.sol          two-step ownership transfer
    Pausable.sol              global + per-proof-type pause
circuits/
  compliance/                 COMPLIANCE (0x01) circuit (Noir)
  shared/                     shared Noir crate (hashing, Merkle, ECDSA, risk score)
```

### Where public-input validation lives

The split matters when reading the [Public Input Validation](../../ERCS/erc-8262.md#public-input-validation)
section of the standard:

- `ProofTypes.validatePublicInputs` checks **shape only** -- 32-byte alignment
  and the expected input count for the proof type.
- `ERC8262Oracle._validate*Inputs` performs the **semantic** checks. There is one
  such function per proof type, each carrying an indexed comment listing every
  public input at its byte offset, followed by the checks applied to it. Start
  there when cross-checking the standard against this implementation.

Cross-cutting checks shared by those validators are `_assertSubmitter`
(`submitter == msg.sender`), `_assertResultPositive` (the boolean result field is
canonical `true`), `_assertValidConfig`, `_assertConfigNotDenied`,
`_assertChainAndOracleBinding`, and `_validateProofTimestamp`.

The Barretenberg-generated verifier contracts (one ~100 KB Solidity file per
proof type) are build artifacts, reproducible from the circuits, and are
registered into `ERC8262Verifier` by address at deploy time.

## Proving stack

Circuits are written in Noir -- the zero-knowledge domain-specific language for
SNARK proving systems, maintained by the Aztec Foundation under a dual
MIT / Apache-2.0 license -- and compiled to on-chain UltraHonk verifiers by
Barretenberg (`bb`), the optimized bn128 elliptic-curve library and PLONK /
UltraHonk proving backend maintained by Aztec Labs under Apache-2.0. Pinned
versions:

| Tool              | Version                | License          |
| ----------------- | ---------------------- | ---------------- |
| nargo (Noir)      | 1.0.0-beta.20          | MIT / Apache-2.0 |
| bb (Barretenberg) | 4.0.0-nightly.20260120 | Apache-2.0       |
| Foundry (forge)   | stable                 | MIT / Apache-2.0 |

## Build

```sh
forge build

cd circuits/compliance && nargo compile
bb write_solidity_verifier -b ./target/compliance.json -o ./compliance_verifier.sol
```

The `COMPLIANCE` witness in `circuits/compliance/Prover.toml` matches the
Witness Annex in ERC-8262.
