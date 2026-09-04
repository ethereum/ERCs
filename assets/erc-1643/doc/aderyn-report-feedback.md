# Aderyn Report — Triage & Feedback

Companion to [`aderyn-report.md`](./aderyn-report.md). Every finding below was opened at the cited
`file:line` and verified against the source before being dispositioned.

| Field | Value |
| --- | --- |
| Tool | Aderyn 0.6.5 |
| Command | `aderyn -x mocks --output doc/aderyn-report.md` |
| Scope | `src/` — 4 `.sol` files, 102 nSLOC (mocks excluded; repo has none) |
| Commit | `bd66a70` |
| Date | 2026-07-28 |
| Result | **0 High · 0 Medium · 3 Low · 0 Info** |

## Summary table

| ID | Detector | Severity | Instances | Disposition | Reason |
| --- | --- | --- | --- | --- | --- |
| L-1 | Centralization Risk | Low | 5 | By design | Owner-gated writes are mandated by the ERC's own Security Considerations |
| L-2 | Unspecific Solidity Pragma | Low | 4 | By design | Floating pragma is correct for a module meant to be inherited downstream |
| L-3 | PUSH0 Opcode | Low | 4 | Environment | Depends on the deployment chain, not on contract logic |

## Per-finding detail

### L-1: Centralization Risk — *By design* (5 instances)

Flagged: `ERC1643.sol:10` (`is IERC1643, Ownable, ERC165`), `ERC1643.sol:49` (`setDocument`),
`ERC1643.sol:72` (`removeDocument`), `ERC20DocumentToken.sol:27` and `ERC721DocumentToken.sol:27`
(`mint`).

This is the intended architecture, not an oversight. ERC-1643's Security Considerations state that
implementations *should* protect `setDocument` and `removeDocument` with appropriate authorization —
an unpermissioned document module would let anyone rewrite a token's legal references, which is the
actual vulnerability this detector's inverse would represent. OpenZeppelin `Ownable` is the documented
choice, and `README.md` plus the ERC's Reference Implementation section both say so explicitly.

The two `mint` instances are example-token scaffolding, present so the ERC-20/ERC-721 samples are
deployable and testable. They are not part of the ERC-1643 module.

Integrators who need distributed control can override `setDocument`/`removeDocument` — both are
`public virtual` — and substitute `AccessControl`, a timelock, or a multisig owner. No change needed
in this repository.

### L-2: Unspecific Solidity Pragma — *By design* (4 instances)

Flagged: `^0.8.24` at line 2 of all four source files.

Pinning would be wrong here. `ERC1643` is an `abstract` module intended to be inherited by consumer
contracts, and `IERC1643` is an interface others import; a hard-pinned `pragma solidity 0.8.34` would
force every downstream project onto that exact compiler. Floating pragmas are standard for library and
interface code, which is why OpenZeppelin ships them too.

Build reproducibility for *this* repository is handled separately and correctly: `foundry.toml` pins
`solc = "0.8.34"`, so local and CI artifacts are deterministic regardless of the pragma range.

The detector's underlying concern — that a *deployed* contract's bytecode should come from a known
compiler — is therefore already satisfied by the build config.

### L-3: PUSH0 Opcode — *Environment* (4 instances)

Flagged: `^0.8.24` at line 2 of all four source files.

Correct as a factual observation and worth keeping visible, but it is not a code defect. `foundry.toml`
sets `evm_version = "prague"`, which is well past Shanghai, so the emitted bytecode does contain `PUSH0`.

This only matters if you deploy to a chain whose EVM predates Shanghai. Ethereum mainnet and the major
L2s support `PUSH0`, so the default configuration is fine. Anyone targeting an older or non-standard
chain must lower `evm_version` in `foundry.toml` at deployment time — a per-deployment decision that
cannot be resolved in the source, and one the reference implementation should not hard-code.

No source change; the constraint is documented here and in the report header.

## Executive triage

**Nothing is exploitable and nothing needs to be fixed.**

All three Low findings are accepted positions: two describe deliberate design choices required by the
ERC itself or by the module's role as inheritable code, and the third is a deployment-target
consideration that belongs to the integrator, not the source.

Aderyn reports **0 High** and **0 Medium**. It found no issue in the document-management logic itself —
the storage layout, the swap-and-pop enumeration, the `exists` guard on removal, or the zero-name
validation.

Static analysis is a floor, not a ceiling. This repository still has **not** received a manual security
review or third-party audit; see [`AUDIT_OVERVIEW.md`](./AUDIT_OVERVIEW.md).
