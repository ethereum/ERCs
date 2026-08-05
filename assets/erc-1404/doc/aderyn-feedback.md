# Aderyn Report — Feedback & Triage

**Scope**: `src/` — `ERC1404.sol`, `ERC1404SpenderAware.sol`, `IERC1404.sol`, `IERC1404SpenderAware.sol`, `engine/IERC1404Restriction.sol`, `engine/RestrictedToken.sol`, `engine/WhitelistRuleEngine.sol`
**Tool**: [Aderyn](https://github.com/Cyfrin/aderyn) `0.6.5` static analysis (mocks excluded, `-x mocks`)
**Date reviewed**: 2026-07-20

---

## Summary

| ID  | Title                              | Severity | Instances | Disposition |
|-----|------------------------------------|----------|-----------|-------------|
| H-1 | Arbitrary `from` in `transferFrom` | High     | 2         | **False positive** |
| L-1 | Centralization Risk                | Low      | 9         | **By design** |
| L-2 | Unsafe ERC20 Operation             | Low      | 2         | **False positive** |
| L-3 | Unspecific Solidity Pragma         | Low      | 7         | **By design** |
| L-4 | PUSH0 Opcode                       | Low      | 7         | **By design / conditional** |

Tally: **1 High · 0 Medium · 4 Low · 0 Informational** (7 files, 223 nSLOC).

---

## High Issues

### H-1 — Arbitrary `from` Passed to `transferFrom`

**Disposition: False positive**

Two instances, both the standard static-analysis false positive for ERC20 overrides:

1. `src/ERC1404.sol:148` — `super.transferFrom(from, to, value)`.
2. `src/ERC1404SpenderAware.sol:73` — `ERC20.transferFrom(from, to, value)`.

Verified against source. In both cases the override first evaluates the restriction (`ERC1404` calls `_checkRestriction(from, to, value)`; `ERC1404SpenderAware` calls the spender-aware `detectTransferRestrictionFrom(msg.sender, from, to, value)` and reverts on a non-zero code) and then delegates to OpenZeppelin's `ERC20.transferFrom`, which internally calls `_spendAllowance(from, msg.sender, value)`. A caller cannot move another account's tokens without an allowance granted by `from`. No path bypasses the allowance check.

`ERC1404SpenderAware` in fact *tightens* delegated transfers: it additionally rejects a `transferFrom` whose spender (`msg.sender`) is not whitelisted (code `3`, `SPENDER_NOT_WHITELISTED`), which is strictly more restrictive than the base contract, never less.

`RestrictedToken` does not override `transferFrom`; it inherits OZ's implementation (same `_spendAllowance` guarantee) and enforces restrictions in the `_update` hook. Not flagged, and equally safe.

**No action required.**

---

## Low Issues

### L-1 — Centralization Risk

**Disposition: By design**

9 instances across the owner-gated entry points of the three concrete contracts: `ERC1404` (`setWhitelisted`, `mint`, `burn`), `RestrictedToken` (`mint`, `burn`), and `WhitelistRuleEngine` (`setWhitelisted`). ERC-1404 is a permissioned standard for regulated / restricted transfers; a privileged whitelist administrator is the intended compliance control, not a defect.

The count is unchanged from the previous run: `ERC1404SpenderAware` adds no new privileged function — it inherits the base `onlyOwner` whitelist/mint/burn surface and layers only a `view` predictor (`detectTransferRestrictionFrom`) and transfer enforcement on top.

Optional hardening (already noted in the README "Limitations"): use a multisig/timelock as owner, and prefer `Ownable2Step` over `Ownable`.

**No action required.**

---

### L-2 — Unsafe ERC20 Operation

**Disposition: False positive**

Two instances: `super.transfer(to, value)` at `src/ERC1404.sol:140`, and `ERC20.transferFrom(from, to, value)` at `src/ERC1404SpenderAware.sol:73`. `SafeERC20` is intended for *external* calls to third-party tokens that may not conform to the standard (e.g. no return value). Here both are internal calls to OpenZeppelin's own `ERC20`, which returns `true` or reverts — they never silently fail. Wrapping them in `SafeERC20` would be meaningless.

**No action required.**

---

### L-3 — Unspecific Solidity Pragma

**Disposition: By design**

7 instances — every first-party `src/` file uses `pragma solidity ^0.8.20;`. This is deliberate for a reference implementation: the caret sets a minimum-compatibility floor for integrators, while the exact compiler is pinned by the build (`foundry.toml` → `solc = "0.8.34"`). Pinning the pragma would force every downstream consumer onto one exact version.

+2 vs. the previous run — the two files added this revision, `ERC1404SpenderAware.sol` and `IERC1404SpenderAware.sol`, both keep the same `^0.8.20` floor.

**No action required.**

---

### L-4 — PUSH0 Opcode

**Disposition: By design / conditional**

7 instances. `foundry.toml` explicitly sets `evm_version = 'prague'`, so the emitted bytecode intentionally targets a modern EVM (Shanghai onward), which includes `PUSH0`. This is correct for Ethereum mainnet and current L2s.

+2 vs. the previous run — same two new files. Only relevant if an integrator intends to deploy to a pre-Shanghai chain — in which case they set `evm_version = "paris"` in their own config and re-verify. That is a downstream deployment decision, not a code defect.

**No action required.**

---

## Delta from previous run (2026-07-08)

- **Scope grew** from 5 to 7 files and from 166 to 223 nSLOC, following the addition of `src/ERC1404SpenderAware.sol` (48 nSLOC) and `src/IERC1404SpenderAware.sol` (8 nSLOC).
- **H-1**: 1 → **2** instances — the new `ERC1404SpenderAware.transferFrom` adds a second `ERC20.transferFrom` delegation call site. Same false positive; allowance enforcement is intact and the spender-aware override is strictly more restrictive.
- **L-2**: 1 → **2** instances — same second call site; same false positive.
- **L-3 / L-4**: 5 → **7** instances each — the two new files' `^0.8.20` pragma.
- **L-1**: unchanged at 9 — no new privileged functions were introduced.
- **No new detector categories, no severity increase.** The High count stays at 1 (detector, not instance count); no Medium appeared.

---

## Executive triage

**Nothing is exploitable and nothing needs a code change.** H-1 and L-2 are ERC20-override false positives (allowance enforcement + internal OZ calls) — the extra instances this revision are the new `ERC1404SpenderAware.transferFrom`, which is strictly more restrictive than the base. L-1 is the intended permissioned-token model. L-3 and L-4 are deliberate reference-implementation / build-configuration choices. The `evm_version` and ownership-hardening notes are already documented in the README "Limitations" section.
