# Audit Overview

Security status of the ERC-1643 reference implementation.

> **This repository has not been audited.** No manual security review or third-party audit has been
> performed. The analyses listed below are automated static analysis only. Do not use this code in
> production without an independent review.

## Scope

In scope: the four contracts under `src/`.

| File | Role |
| --- | --- |
| `src/erc-1643/IERC1643.sol` | Interface — 4 functions, 2 events, 2 custom errors |
| `src/erc-1643/ERC1643.sol` | Abstract module — storage, enumeration, owner-gated writes |
| `src/ERC20DocumentToken.sol` | Example ERC-20 integration |
| `src/ERC721DocumentToken.sol` | Example ERC-721 integration |

Out of scope: `test/`, `script/`, and everything under `lib/` (OpenZeppelin Contracts v5.6.1,
forge-std v1.16.1).

## Analyses performed

| Analysis | Date | Commit | Report | Triage |
| --- | --- | --- | --- | --- |
| Aderyn 0.6.5 | 2026-07-28 | `bd66a70` | [`aderyn-report.md`](./aderyn-report.md) | [`aderyn-report-feedback.md`](./aderyn-report-feedback.md) |
| Slither 0.11.5 | 2026-07-28 | `bd66a70` | Run locally; report not published (see note) | — |
| Manual review | — | — | Not performed | — |
| Third-party audit | — | — | Not performed | — |

> **Note on the Slither report.** Its output is kept as a local artifact only and is not published in
> this table, because the file must not be carried into the EIP repository's `assets/eip-1643/`
> directory — an extra document there breaks the EIP/ERC validation check. The result is stated in
> full below. Reproduce it with the command under "Reproducing".

## Static-analysis results

| Tool | High | Medium | Low | Info | Anything to fix? |
| --- | --- | --- | --- | --- | --- |
| Aderyn 0.6.5 | 0 | 0 | 3 | 0 | **No** — all by design or environment |
| Slither 0.11.5 | 0 | 0 | 0 | 0 | **No** — no findings in scope |

Aderyn's three Low findings are Centralization Risk (owner-gated writes, mandated by the ERC),
Unspecific Solidity Pragma (correct for inheritable module code), and PUSH0 Opcode (a deployment-chain
consideration). Each is verified against the source and dispositioned in the triage file.

Slither reported **no findings** across 101 detectors — no reentrancy, uninitialized state, unchecked
return value, arbitrary send, shadowing, or incorrect equality. Run unfiltered it produces 46 results,
every one of them anchored in `lib/openzeppelin-contracts` and therefore out of scope; `lib` is
excluded via `--filter-paths` for that reason. The project's own files surface in an unfiltered run
only inside the `solc-version` detector's "different pragma directives are used" finding, which
enumerates every pragma in the compilation unit — a report on the dependency tree, not a defect in
these four files.

## Findings fixed

None to date. No static-analysis or review finding has required a source change.

Spec-conformance verification against `erc-1643.md` (2026-07-28) confirmed that every normative
MUST/SHOULD clause is satisfied, and that the interface and its ERC-165 id (`0xecfecec8`) match the
specification exactly.

## Known accepted risks

| Risk | Rationale |
| --- | --- |
| Owner can rewrite or delete any document | Required by the ERC; integrators should use a timelock or multisig owner. Both write functions are `public virtual` and can be overridden with a different authorization model. |
| Document URIs may point to mutable off-chain content | Consumers must verify fetched content against the stored `documentHash`. |
| `getAllDocuments()` returns an unbounded array | Enumeration cost grows with document count; very large sets may exceed the gas limit for an `eth_call`. |
| Bytecode contains `PUSH0` | `foundry.toml` targets `evm_version = "prague"`. Lower it before deploying to a pre-Shanghai chain. |
| Deploy script reads `PRIVATE_KEY` from the environment | Convenience for examples only. Use a hardware wallet, keystore, or secret manager for real deployments. |

## Reproducing

```bash
aderyn -x mocks --output doc/aderyn-report.md
slither . --checklist --filter-paths "node_modules,submodules,test,forge-std,mocks,lib"
```
