---
eip:
Title: Token with built-in AMM
description: This token standard embeds AMM into the smart contract, enabling gas-efficient swaps, cutting costs, reducing MEV, and redefining Ethereum trading.
discussions-to: 
Status: Draft
type: Standards Track
category: ERC
Author: Duong Xuan Thao (@Thaoxuanduong)
Created: 2024-12-18
---

## Abstract
This Token Standard integrates Automated Market Maker (AMM) functionality directly into 
the token smart contract, enabling seamless, gas-efficient token swaps without external 
platforms like Uniswap. By embedding liquidity management and trading logic into the token 
itself, this standard eliminates the need for approvals, reduces MEV vulnerability, and drastically 
cuts transaction costs. This standard aim to redefine Ethereum trading with native mechanisms for 
liquidity provision, slippage protection, and fee management.

## Motivation
The existing ERC-20 token standard relies heavily on third-party tools for liquidity management 
and token swapping. While these tools enable DeFi innovation, they also introduce 
inefficiencies:

1. **High Gas Costs**: Swapping tokens via external AMMs requires interaction with multiple 
contracts, making transactions 3-5x more expensive than native token transfers.

2. **MEV Vulnerability**: External AMM reliance exposes users to frontrunning and sandwich 
attacks, leading to significant financial losses.

3. **Complexity**: Users must approve tokens before swapping, adding unnecessary steps 
and costs.

4. **Developer Costs**: Deploying liquidity pools on platforms like Uniswap incurs high 
deployment fees, often exceeding several hundred dollars.

The token standard addresses these inefficiencies by embedding AMM functionality directly 
into the token contract. This results in reduced gas fees, native MEV protection, and a simplified 
user experience.

## Specification

### Liquidity Management

```solidity
function addLiquidity(uint256 tokenAmount) external payable;
function removeLiquidity(uint256 liquidityAmount) external;
```

- `addLiquidity`: Deposits ETH and tokens to the pool, minting liquidity shares.
- `removeLiquidity`: Withdraws proportional shares of reserves.

### Swapping

```solidity
function swapExactTokensForETH(uint256 tokenAmount, uint256 minEthOut) external;
function swapExactETHForTokens(uint256 minTokensOut) external payable;
```

- `swapExactTokensForETH`: Trades tokens for ETH while ensuring a minimum ETH output.
- `swapExactETHForTokens`: Trades ETH for tokens while ensuring a minimum token output.

### Fee Management

```solidity
function setTradingFee(uint16 feeBasisPoints) external onlyOwner;
function disableTradingFee() external onlyOwner;
```

- `setTradingFee`: Sets trading fees as a percentage of the swap amount.
- `disableTradingFee`: Removes fees for promotional or community-driven initiatives.

### Reserves

```solidity
function getReserves() external view returns (uint256 tokenReserve, uint256 ethReserve);
```

- **Purpose**: Provides reserve balances for calculating swap rates and slippage.

### Example Calculation

For a token swap:

1. **Constant Product Formula**: `k = x * y`
   - `x`: Token reserve
   - `y`: ETH reserve
2. **Price Impact**: Calculated using reserve deltas.
3. **Slippage Enforcement**: Minimum output values prevent unfavorable trades.

## Rationale
This standard was designed to address inefficiencies inherent in Ethereum’s current token ecosystem:

- **Why Built-In AMM?** External AMMs are costly and vulnerable; integrating AMM logic directly simplifies and secures trading.
- **Alternatives Considered**: Optimizing Uniswap or relying on Layer 2 solutions. These options introduce fragmentation or fail to address core Ethereum-layer inefficiencies.
- **Trade-Offs**: While the Token Standard simplifies user experience, it places additional logic in the token contract, requiring robust audits to ensure security.

## Security Considerations
1. **Reentrancy Protection**: All state-updating functions are guarded to prevent attacks.
2. **Slippage Enforcement**: Users specify minimum outputs to protect against unexpected 
price impacts.
3. **Liquidity Locking**: Prevents unauthorized liquidity removal by enforcing time-locks and 
permissions.

## Backwards Compatibility
- **ERC-20 Compatibility**: Fully compatible, enabling interactions with existing wallets and tools.
- **Legacy AMMs**: Can still trade on external platforms if desired, though native AMM features are optimized for cost and security.

## Test Cases
1. **Swap Execution**:
   - Input: Token amount, minimum ETH output.
   - Expected: Accurate output based on reserves and fee logic.
2. **Liquidity Add/Remove**:
   - Input: Token and ETH amounts.
   - Expected: Adjusted reserves and liquidity share minting/burning.
3. **Edge Cases**:
   - Excessive slippage.
   - Reserve depletion.

## Reference Implementation
A reference implementation is available on [GitHub](https://github.com/ev-token-standard) and includes:

- Core contract code.
- Testnet deployments.
- Example transactions demonstrating key functionality.

## Copyright
This work is licensed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).
