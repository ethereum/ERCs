# Test 1: Simple Token Swap

## 1. Overview

This test demonstrates a token swap from POL to ETH through a Flash Loan Proxy, with a Safe-based smart account acting as the trader.

The trader swaps **5,447 POL** for approximately **873.89 ETH** on the Sepolia testnet. The minimum acceptable output is **873.88 ETH**; a lower output causes the execution to revert.

The swap is initiated through an atomic batch executed by the trader's Smart Wallet. The batch consists of the following operations:

1. Transfer 5,447 POL from the Smart Wallet to the Flash Loan Proxy.
2. Invoke the Flash Loan Proxy with the swap program and its associated calldata.
3. Execute the swap and transfer the resulting ETH to the trader's Smart Wallet.

All operations are executed atomically by the Smart Wallet. If any operation fails, the entire transaction reverts, including the initial token transfer. This ensures that a failed execution does not leave the transferred POL stranded in the proxy.

## 2. Test Environment

| Parameter | Value |
|---|---|
| Network | Sepolia testnet |
| EVM environment | Osaka |
| Solidity compiler | `v0.8.35+commit.47b9dedd` |
| Optimization | Enabled, 10,000,000 runs |
| Trader | Safe-based Smart Wallet |
| Execution model | Atomic batch execution |

The specified compiler configuration is used for this test. Other compatible Solidity compiler versions and configurations may also be used, provided that they produce a program compatible with the execution environment.

## 3. Execution Procedure

The Smart Wallet executes the following operations in a single atomic transaction:

1. Transfer `5,447 POL` to the Flash Loan Proxy.
2. Submit the swap program and its input calldata to the proxy.
3. Execute the swap against the POL/WETH liquidity pool.
4. Unwrap the resulting WETH into ETH.
5. Transfer the resulting ETH to the trader's Smart Wallet.

The swap program enforces a minimum output of `873.88 ETH`. If the resulting amount is below this threshold, execution reverts.

Because the entire sequence is executed atomically, a revert in any operation also reverts the preceding POL transfer.

## 4. Program Specification

### 4.1. Source Code

The execution program is written in Solidity and compiled using the configuration specified in Section 2.

The program is supplied to the Flash Loan Proxy as **raw runtime bytecode**. The Solidity source code is available at:

[`Swap.sol`](../assets/erc-8486/tests/test1/Swap.sol)

The proxy receives the runtime bytecode as the program input. The implementation processes this program according to its execution model.

### 4.2. Runtime Bytecode

The raw runtime bytecode generated for this test is:

```text
[RAW RUNTIME BYTECODE — see test1/Swap.runtime.hex]
```

The bytecode must be supplied without ABI-encoding it as an additional `bytes` value. The proxy's initial invocation payload, however, uses the ABI encoding specified by the proxy interface.

### 4.3. Program Input

The calldata consumed by the execution program is the ABI-encoded selector for `trade()`:

```text
0x1f0ba6c9
```

This selector identifies the `trade()` function implemented by the program.

### 4.4. Proxy Invocation Calldata

The initial calldata submitted to the Flash Loan Proxy is the ABI encoding of the following parameters:

| Parameter | Type | Value |
|---|---|---|
| `bytecode` | `bytes` | Raw runtime bytecode from Section 4.2 |
| `data` | `bytes` | `0x1f0ba6c9` |

The complete ABI-encoded payload is available at:

```text
test1/proxy-invocation-calldata.hex
```

This payload contains the runtime bytecode and program input described above.

## 5. Transaction Parameters

### 5.1. Contract Addresses

| Component | Address |
|---|---|
| Flash Loan Proxy | `0x6ee9084aa99bdae60a1dbe6e9864b5df4d0822eb` |
| Smart Wallet (`tx.to`) | `0xA8B05fdd5460b9727838e88c3ffFd63F3E64999f` |
| Relayer (`tx.sender`) | `0x767EDf5DFDc9aC305033E212640A6Cbfd1203a45` |
| POL token | `0x44499312f493F62f2DFd3C6435Ca3603EbFCeeBa` |
| WETH token | `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14` |
| POL/WETH liquidity pool | `0x510dE933db6d6ce457bdD1d94802B6a6eBaE4232` |

### 5.2. Smart Wallet Batch

The Smart Wallet executes the operations through the following batch target:

| Parameter | Type | Value |
|---|---|---|
| `to` | `address` | `0x9641d764fc13c8B624c04430C7356C1C7C8102e2` |
| `value` | `uint256` | `0` |
| `data` | `bytes` | Encoded batch operations |
| `operation` | `uint8` | `1` |
| `safeTxGas` | `uint256` | `0` |
| `baseGas` | `uint256` | `0` |
| `gasPrice` | `uint256` | `0` |
| `gasToken` | `address` | `0x0000000000000000000000000000000000000000` |
| `refundReceiver` | `address` | `0x0000000000000000000000000000000000000000` |
| `signatures` | `bytes` | `0xa9f37aae99d88189be74a241aff235ac2868a1038db6741ad9acbe05ae0b85ec371b531e1eaedccaa7e8071c6a7a3d59d7acc9f50f8dcc942509a7507d221dbc1b` |

The complete encoded batch calldata is available at:

```text
test1/safe-batch-calldata.hex
```

The batch contains the POL transfer, the Flash Loan Proxy invocation, and the subsequent transfer of the swap output to the trader's Smart Wallet.

## 6. Test Result

| Parameter | Result |
|---|---|
| Transaction status | **Success** |
| Network | Sepolia testnet |
| Minimum acceptable output | 873.88 ETH |
| Reported swap output | Approximately 873.89 ETH |

Transaction details:

[View transaction on Tenderly](https://dashboard.tenderly.co/tx/0x2f8714e68ce14ceeafdd52d32d0c1131344b669ea96e41df3313947eb780bc02)

The transaction completed successfully, demonstrating the use of the Flash Loan Proxy to execute a token swap within an atomic Smart Wallet batch.
