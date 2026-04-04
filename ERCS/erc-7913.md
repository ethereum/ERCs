---
eip: 7913
title: Token Safety Score
description: A standard interface for querying and publishing token safety scores on EVM chains
author: CryptoGen Security (@CryptoGenesisSecurity)
discussions-to: https://github.com/CryptoGenesisSecurity/erc-token-safety-score/issues
status: Draft
type: Standards Track
category: ERC
created: 2026-04-04
requires: 20
---

## Abstract

This ERC defines a standard interface for token safety scoring — enabling smart contracts, wallets, DEX frontends, and AI agents to query whether an [ERC-20](./eip-20.md) token is safe to interact with. It standardizes the scoring methodology, the on-chain interface for safety oracles, and the metadata format for off-chain safety reports.

## Motivation

The proliferation of scam tokens (honeypots, rug pulls, hidden mints, fee manipulation) causes billions in losses annually. Currently:

1. No standard exists for representing token safety — each tool uses proprietary scoring.
2. AI agents trading autonomously have no standardized way to check token safety before executing trades.
3. DEX frontends and wallets implement ad-hoc safety warnings with inconsistent methodologies.
4. Smart contracts cannot query safety data on-chain — all safety tools are off-chain only.

A standardized Token Safety Score enables:

- Any smart contract to gate interactions based on safety scores.
- AI agents to discover and query safety oracles via a common interface.
- DEX frontends to display consistent safety warnings.
- Composable safety checks across the EVM ecosystem.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Safety Score

A Token Safety Score MUST be an unsigned integer from 0 to 100 where:

- **0-20**: DANGEROUS — High probability of scam/rug
- **21-40**: RISKY — Multiple warning signs detected
- **41-60**: CAUTION — Some concerns, proceed with care
- **61-80**: MODERATE — Minor issues detected
- **81-100**: SAFE — No significant issues found

### Interface

Every compliant Token Safety Oracle MUST implement the following interface:

```solidity
interface IERC7913 {
    /// @notice Emitted when a token's safety score is updated
    event SafetyScoreUpdated(
        address indexed token,
        uint8 score,
        uint256 flags,
        uint256 updatedAt
    );

    /// @notice Get the safety score for a token
    /// @param token The ERC-20 token address
    /// @return score The safety score (0-100), or 0 if not scored
    /// @return flags Bitmask of detected risk flags
    /// @return updatedAt Timestamp of last update, or 0 if never scored
    function getSafetyScore(address token)
        external view returns (uint8 score, uint256 flags, uint256 updatedAt);

    /// @notice Check if a token meets a minimum safety threshold
    /// @param token The ERC-20 token address
    /// @param minScore Minimum acceptable safety score
    /// @return safe Whether the token meets the threshold
    function isSafe(address token, uint8 minScore)
        external view returns (bool safe);
}
```

### Risk Flags

The `flags` field is a 256-bit bitmask where each bit represents a specific risk:

| Bit | Flag | Description |
|-----|------|-------------|
| 0 | `UNVERIFIED` | Source code not verified on block explorer |
| 1 | `HONEYPOT` | Sell transactions blocked or heavily taxed |
| 2 | `HIDDEN_MINT` | Owner can mint unlimited tokens |
| 3 | `BLACKLIST` | Owner can blacklist addresses from trading |
| 4 | `FEE_MANIPULATION` | Owner can change buy/sell fees to 100% |
| 5 | `TRADING_PAUSE` | Owner can disable all trading |
| 6 | `PROXY_UPGRADEABLE` | Contract logic can be changed by owner |
| 7 | `SELF_DESTRUCT` | Contract contains selfdestruct opcode |
| 8 | `DELEGATECALL` | Contract uses delegatecall to external code |
| 9 | `OWNERSHIP_NOT_RENOUNCED` | Owner retains privileged functions |
| 10 | `LOW_LIQUIDITY` | Less than $10,000 in DEX liquidity |
| 11 | `LP_NOT_LOCKED` | Liquidity provider tokens are not locked |
| 12 | `HIGH_TAX` | Combined buy/sell tax exceeds 10% |
| 13 | `MAX_WALLET_LIMIT` | Owner can restrict wallet holdings |
| 14 | `COOLDOWN_RESTRICTION` | Transfer cooldown or anti-bot mechanisms |
| 15 | `EXTERNAL_CALL_RISK` | Sends native currency to external addresses |
| 16-255 | Reserved | For future risk categories |

## Rationale

### Why 0-100 Score?

A continuous score (vs binary safe/unsafe) enables consumers to set their own risk tolerance. A DEX might require score > 60, while a memecoin trading bot might accept score > 30.

### Why On-Chain?

On-chain scores enable smart contracts to gate token interactions (e.g., a DEX refusing to list tokens scoring below 40), composability with other protocols, and full auditability of score history.

### Why Bitmask Flags?

Individual flags allow consumers to filter on specific risks. A stablecoin protocol might only care about `HONEYPOT` and `HIDDEN_MINT`, while a wallet might display all flags to users.

## Backwards Compatibility

This ERC introduces a new interface and does not conflict with existing standards. Tokens do not need to implement this interface — the safety oracle is a separate contract that scores any ERC-20 token.

## Reference Implementation

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TokenSafetyOracle is IERC7913 {
    address public operator;
    mapping(address => Score) private _scores;

    struct Score {
        uint8 score;
        uint256 flags;
        uint256 updatedAt;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "not operator");
        _;
    }

    constructor() {
        operator = msg.sender;
    }

    function updateScore(address token, uint8 score, uint256 flags) external onlyOperator {
        require(score <= 100, "score > 100");
        _scores[token] = Score(score, flags, block.timestamp);
        emit SafetyScoreUpdated(token, score, flags, block.timestamp);
    }

    function getSafetyScore(address token)
        external view override returns (uint8, uint256, uint256)
    {
        Score memory s = _scores[token];
        return (s.score, s.flags, s.updatedAt);
    }

    function isSafe(address token, uint8 minScore)
        external view override returns (bool)
    {
        return _scores[token].score >= minScore && _scores[token].updatedAt > 0;
    }
}
```

Live deployments:

- Optimism: `0x3B8A6D696f2104A9aC617bB91e6811f489498047` (108 tokens scored)
- Base: `0x37b9e9B8789181f1AaaD1cD51A5f00A887fa9b8e` (19 tokens scored)

## Security Considerations

1. **Oracle Trust**: Consumers must trust the oracle operator. Decentralized scoring with multiple oracles and aggregation is RECOMMENDED for production use.

2. **Stale Scores**: Consumers SHOULD check `updatedAt` and define a maximum staleness threshold.

3. **Score Manipulation**: Oracle operators could provide false scores. Multi-oracle aggregation and reputation systems mitigate this.

4. **Front-Running**: Score downgrades are public transactions. Malicious actors could front-run to exit positions. Commit-reveal schemes can mitigate this.

5. **Gas Costs**: All queries are view functions with negligible gas. Batch updates amortize write costs.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
