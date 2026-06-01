# Aderyn Report — Feedback & Triage

**Contract**: `src/ERC1404.sol`  
**Tool**: [Aderyn](https://github.com/Cyfrin/aderyn) static analysis  
**Date reviewed**: 2026-04-29

---

## Summary

| ID  | Title                              | Severity | Verdict           |
|-----|------------------------------------|----------|-------------------|
| H-1 | Arbitrary `from` in `transferFrom` | High     | False positive    |
| L-1 | Centralization Risk                | Low      | Acknowledged      |
| L-2 | Unsafe ERC20 Operation             | Low      | False positive    |
| L-3 | Unspecific Solidity Pragma         | Low      | False positive — intentional |
| L-4 | PUSH0 Opcode                       | Low      | Conditional — depends on target chain |

---

## High Issues

### H-1 — Arbitrary `from` Passed to `transferFrom`

**Verdict: False positive**

Aderyn flags `super.transferFrom(from, to, value)` at line 109 as potentially allowing anyone to drain tokens from an arbitrary `from` address. This is a known static-analysis false positive for ERC20 overrides.

**Why it is safe here:**

The `transferFrom` override correctly calls `_checkRestriction(from, to, value)` before delegating to OpenZeppelin's `ERC20.transferFrom`. OpenZeppelin's implementation internally calls `_spendAllowance(from, msg.sender, value)`, which enforces that `msg.sender` must have a sufficient allowance granted by `from`. There is no code path that bypasses this allowance check.

The pattern `super.transferFrom(from, to, value)` in an ERC20 override is idiomatic and does not introduce an authorization vulnerability.

**No action required.**

---

## Low Issues

### L-1 — Centralization Risk

**Verdict: Acknowledged — by design**

The contract inherits `Ownable` and gates `setWhitelisted`, `mint`, and `burn` behind `onlyOwner`. ERC-1404 is a standard specifically designed for regulated, restricted token transfers (e.g., security tokens). Centralized whitelist control is an intentional design requirement of this standard.

**Recommendations (optional hardening):**

- Use a multi-sig wallet (e.g., Gnosis Safe) as the owner to distribute trust.
- Consider `Ownable2Step` from OpenZeppelin instead of `Ownable` to prevent accidental ownership transfers to wrong addresses.
- Document in the README that the owner is expected to be a governance contract or multi-sig in production.

---

### L-2 — Unsafe ERC20 Operation

**Verdict: False positive**

Aderyn flags `super.transfer(to, value)` at line 104 as an unsafe ERC20 operation and suggests using `SafeERC20`.

`SafeERC20` is a wrapper designed for *calling external ERC20 tokens* that may not conform to the standard (e.g., tokens that return no bool). Here, `super.transfer` is an internal call to OpenZeppelin's own `ERC20.transfer`, which always returns `true` or reverts — it never silently fails. Wrapping it with `SafeERC20` would be incorrect and meaningless.

**No action required.**

---

### L-3 — Unspecific Solidity Pragma

**Verdict: False positive — intentional**

Both `src/ERC1404.sol` and `src/IERC1404.sol` use `pragma solidity ^0.8.20;`. Aderyn recommends pinning to an exact version, but this is a deliberate choice for a reference implementation.

**Why it is intentional:**

This repository is meant to be used as a base by integrators. Pinning the pragma to a specific version would force every downstream project to compile with that exact version, creating unnecessary friction. Instead, the compiler version is left to the consumer to control via their own Foundry config:

```toml
# foundry.toml (in the integrator's project)
[profile.default]
solc_version = "0.8.34"
```

This is the standard approach for libraries and reference implementations — the pragma sets a minimum compatibility floor (`^0.8.20`) while the build tooling enforces the exact version used in practice.

**No action required.**

---

### L-4 — PUSH0 Opcode

**Verdict: Conditional — depends on deployment target**

Solidity `0.8.20` sets the default EVM target to Shanghai, which introduces the `PUSH0` opcode. If the contract is deployed on Ethereum mainnet or any EVM chain that supports Shanghai, this is not an issue.

**It becomes a problem if** the contract is deployed on an L2 or EVM-compatible chain that has not yet implemented the Shanghai upgrade (e.g., older versions of some zkEVM chains or Arbitrum pre-Shanghai support).

**Recommended action:**

- If deploying on mainnet only: no action required.
- If deploying on L2s or alternative chains: explicitly set the EVM version in `foundry.toml`:

```toml
[profile.default]
evm_version = "paris"  # use pre-Shanghai target
```

And verify the target chain supports the chosen EVM version.

---

## Overall Assessment

Three of the five findings (H-1, L-2, L-3) are false positives. H-1 and L-2 are caused by Aderyn's pattern-matching against ERC20 overrides — a known tool limitation — and L-3 is intentional design for a reference implementation. The actual code correctly enforces allowance checks and delegates to well-audited OpenZeppelin internals.

The actionable items are:

1. **Clarify the target deployment chain** and adjust the EVM version in `foundry.toml` if needed (L-4).
2. **Consider `Ownable2Step`** as a low-effort improvement to ownership transfer safety (L-1).
