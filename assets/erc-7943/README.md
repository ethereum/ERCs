# ERC-7943 uRWA Minimal Package

## Prerequisites
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Install dependencies
If OpenZeppelin not yet in lib/:
```bash
forge install OpenZeppelin/openzeppelin-contracts
```

## Build
```bash
forge build
```

## Test
```bash
forge test -vv
```

## Gas report
```bash
forge test --gas-report
```

## Coverage
```bash
forge coverage
```