---
title: Token Safety Score
description: Standard interface for on-chain ERC-20 safety scoring oracles, enabling routers and accounts to enforce pre-trade safety checks atomically.
author: CryptoGen Security (@Aigen-Protocol)
discussions-to: https://ethereum-magicians.org/t/erc-token-safety-score/aigen
status: Draft
type: Standards Track
category: ERC
created: 2026-05-07
requires: 20
---

## Abstract

This standard defines a minimal interface for an on-chain oracle that exposes a safety score `(0-100)` and a flag bitfield for any ERC-20 token contract. Wallet routers, account-abstraction modules, and DEX aggregators MAY query the oracle in a single view call before executing a swap, transfer approval, or balance allocation, and MAY revert atomically if the score falls below a configurable threshold. The standard is read-only (oracle update governance is implementation-defined) and assumes a single canonical oracle per chain that the calling contract trusts via address.

## Motivation

Wallet and trading agents on EVM chains operate against a long tail of malicious tokens (honeypots, hidden mint, blacklist gates, fee manipulation). Existing safety services (GoPlus, De.Fi, Honeypot.is, SafeAgent Shield) provide off-chain HTTP scoring, but smart contracts that execute swaps cannot natively verify a token's safety at the transaction site without a standardized on-chain interface.

The lack of a standard creates three concrete problems:

1. **No atomic guarantee.** An off-chain check at time `T` followed by an on-chain swap at time `T+1` is not atomic; a malicious token can change behavior between the two reads (proxy upgrade, owner state change). Atomic check requires the oracle read to happen in the same transaction as the swap.

2. **Vendor lock-in.** Each safety service publishes its own incompatible interface. A router that wants to be safety-aware must hard-code one vendor.

3. **No composition.** Safety checks cannot be embedded in libraries (e.g. modifier patterns) without a stable interface. Today every contract that wants safety must reimplement the off-chain query path.

This standard fixes all three by defining a tiny, gas-efficient view interface that any router, account, or library can rely on.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

A compliant oracle MUST implement the following Solidity interface:

```solidity
interface ITokenSafetyOracle {
    /// @notice Get the safety profile of a token.
    /// @param token The ERC-20 token contract address.
    /// @return score An integer in [0, 100], where 0 = unsafe and 100 = no detected risk.
    /// @return flags A 256-bit bitfield encoding categorical risks (see Flags below).
    /// @return updatedAt Unix timestamp of the last score update; 0 means never scored.
    function getSafetyScore(address token)
        external
        view
        returns (uint8 score, uint256 flags, uint256 updatedAt);

    /// @notice Convenience predicate.
    /// @param token The ERC-20 token contract address.
    /// @param minScore Threshold the caller requires.
    /// @return safe True iff `updatedAt > 0` AND `score >= minScore`.
    function isSafe(address token, uint8 minScore) external view returns (bool safe);
}
```

### Score semantics

- `score` MUST be in the inclusive range `[0, 100]`.
- `score == 100` indicates the oracle detected no risks.
- `score == 0` combined with `updatedAt == 0` indicates the token has not been scored. Callers SHOULD treat this as "unknown" and decide policy (fail-open or fail-closed).
- `score == 0` combined with `updatedAt > 0` indicates a token actively flagged as malicious.
- The score scale is monotonic: lower means less safe.

### Flags bitfield

The `flags` return value is a 256-bit bitfield encoding categorical risks. Bit positions in the lower 32 bits are reserved by this standard:

| Bit | Risk category |
|----:|---|
| 0 | Honeypot (sell blocked or reverts) |
| 1 | Hidden mint (owner can mint unbounded) |
| 2 | Blacklist (owner can prevent specific holders from selling) |
| 3 | Trading pause (owner can disable trading) |
| 4 | Fee manipulation (owner can change buy/sell fee post-launch) |
| 5 | Whitelist gate (only whitelisted addresses can trade) |
| 6 | Self-destruct present |
| 7 | Delegatecall to mutable address |
| 8 | Proxy with mutable implementation |
| 9 | Anti-whale with owner exemption |
| 10 | Hidden fee receiver mutation |
| 11 | Airdrop with sell block |
| 12 | Time-locked function activates after launch |
| 13 | Custom `balanceOf` (potential balance manipulation) |
| 14 | Source code not verified on canonical block explorer |
| 15 | Liquidity not locked |
| 16-31 | Reserved for future bit assignments by this standard |
| 32-255 | Implementation-defined / oracle-specific |

A bit set to `1` means the corresponding risk was detected. The `score` is a function of these flags but the mapping is implementation-defined; callers SHOULD use `flags` for fine-grained policy decisions and `score` for coarse pass/fail gating.

### `isSafe` predicate

Implementations MUST return `false` from `isSafe` when `updatedAt == 0`, regardless of the score value. This makes the predicate fail-closed for unknown tokens by default.

### Update governance (informative)

This standard does not mandate how scores are written. Implementations MAY use any of:

- A single trusted operator (centralized).
- A multisig or governance contract.
- A staking-based oracle network.
- A push from off-chain workers signed via ECDSA / EIP-191.

Implementations SHOULD emit an event when scores change so consumers can index the history off-chain.

## Rationale

**Why a single view function instead of separate getters?** Returning `(score, flags, updatedAt)` in one call costs one ABI call frame instead of three. Routers calling the oracle on every swap care about gas — `getSafetyScore` is ~3000 gas with a warm storage slot.

**Why `uint8` for score?** The 0-100 range fits in one byte. Solidity packs `uint8` with adjacent storage variables. Larger types would inflate gas without semantic gain.

**Why a 256-bit `flags` bitfield instead of an array?** Bitfields cost one storage slot regardless of how many flags are set. Reading a single `uint256` is one SLOAD. An array of N risks requires N+1 SLOADs (length + items).

**Why include `isSafe` when `getSafetyScore` is sufficient?** The most common caller pattern is: "is this safe enough?" Inlining the threshold comparison in the oracle saves the caller a JUMPI plus the score comparison. It also forces the fail-closed-on-unknown convention — implementing `isSafe` correctly removes a class of caller-side bugs.

**Why no setter in the interface?** Update governance varies wildly by deployment model (operator vs DAO vs staking). Standardizing read access while leaving write authority to implementers maximizes adoption. A router only needs to read.

## Backwards Compatibility

This standard introduces a new interface and is fully backwards-compatible with ERC-20. Tokens are not modified; only an external oracle contract is added.

A contract MAY implement multiple safety oracle interfaces if competing standards emerge. The proposed interface uses two function selectors (`getSafetyScore(address)` = `0x60bb3979`, `isSafe(address,uint8)` = `0xb5364c12`) which do not collide with widely-deployed ERC standards we surveyed.

## Test Cases

### Read fresh score

```javascript
const oracle = new ethers.Contract(ORACLE_ADDRESS, ABI, provider);
const [score, flags, updatedAt] = await oracle.getSafetyScore("0x833589fcd6edb6e08f4c7c32d4f71b54bda02913");
assert(score === 100);
assert(flags === 0n);
assert(updatedAt > 0);
```

### Predicate behavior on unknown token

```javascript
const oracle = new ethers.Contract(ORACLE_ADDRESS, ABI, provider);
const safe = await oracle.isSafe("0xDEADbeef", 40);
assert(safe === false);  // unknown → fail-closed
```

### Predicate behavior on known-safe token

```javascript
const oracle = new ethers.Contract(ORACLE_ADDRESS, ABI, provider);
const safe = await oracle.isSafe("0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", 40);
assert(safe === true);  // known + score(100) >= 40
```

## Reference Implementation

A minimal Solidity implementation suitable for a single-operator deployment:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TokenSafetyOracle {
    struct Score { uint8 score; uint256 flags; uint256 updatedAt; }

    address public operator;
    mapping(address => Score) private _scores;

    event ScoreUpdated(address indexed token, uint8 score, uint256 flags, uint256 timestamp);

    constructor(address _operator) { operator = _operator; }

    function updateScore(address token, uint8 score, uint256 flags) external {
        require(msg.sender == operator, "not operator");
        require(score <= 100, "invalid score");
        _scores[token] = Score(score, flags, block.timestamp);
        emit ScoreUpdated(token, score, flags, block.timestamp);
    }

    function getSafetyScore(address token)
        external view returns (uint8 score, uint256 flags, uint256 updatedAt)
    {
        Score memory s = _scores[token];
        return (s.score, s.flags, s.updatedAt);
    }

    function isSafe(address token, uint8 minScore) external view returns (bool) {
        Score memory s = _scores[token];
        return s.updatedAt > 0 && s.score >= minScore;
    }
}
```

A consumer router enforcing the standard:

```solidity
interface ITokenSafetyOracle {
    function getSafetyScore(address token) external view returns (uint8, uint256, uint256);
    function isSafe(address token, uint8 minScore) external view returns (bool);
}

contract SafeRouter {
    ITokenSafetyOracle public immutable oracle;
    uint8 public minScore = 40;

    error TokenUnsafe(address token, uint8 score, uint256 flags, uint8 minRequired);

    constructor(address _oracle) { oracle = ITokenSafetyOracle(_oracle); }

    function safeSwap(address tokenIn, address tokenOut, uint256 amountIn, /* ... */) external {
        (uint8 score, uint256 flags, uint256 updatedAt) = oracle.getSafetyScore(tokenOut);
        if (updatedAt > 0 && score < minScore) {
            revert TokenUnsafe(tokenOut, score, flags, minScore);
        }
        // ... execute swap on underlying DEX
    }
}
```

## Security Considerations

**Oracle as a single point of failure.** A malicious operator can flag a legitimate token as `score=0` (denying its trade through compliant routers) or whitelist a scam as `score=100` (greenlighting a rug). Implementations SHOULD use multi-signature governance, time-locked changes, or staking-based dispute resolution to reduce this risk.

**Stale scores.** A token can change behavior post-scoring (proxy upgrade, owner action). The `updatedAt` field exposes this: callers SHOULD reject scores older than a deployment-specific staleness threshold for high-value transfers. This standard does not mandate a threshold because it depends on chain block time, swap value, and risk tolerance.

**Read-only frontrun.** An attacker observing pending swaps cannot frontrun an oracle read because the read is in the same transaction as the swap (atomic). However, an attacker who controls the oracle can frontrun score updates to invalidate competing trades. Multi-sig + time-lock mitigates this.

**`flags` bitfield collision.** Implementations MUST follow the bit assignments in this document for bits 0-31. Implementations using bits 32-255 for proprietary signals MUST document them.

**Fail-open vs fail-closed for unknowns.** This standard mandates `isSafe` returns `false` for unscored tokens (fail-closed). Routers using `getSafetyScore` directly MAY choose fail-open for new-token discovery flows; this is a conscious caller decision, not implementer choice.

**Honeypot detection limitations.** A safety score is a static signal. Tokens that pass on-chain bytecode analysis can still drain users via off-chain coordination (e.g. liquidity removal by a privileged address). Routers SHOULD additionally verify liquidity locks and large-holder concentration before greenlighting trades.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
