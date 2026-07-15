# Two-Phase Asset Transfers: reference implementation

- `contracts/TwoPhaseEscrow.sol` (+ `ITwoPhaseEscrow.sol`): standalone escrow embodiment for
  native ETH and any ERC-20 / ERC-721 / ERC-1155.
- `contracts/ERC20TwoPhase.sol` / `ERC721TwoPhase.sol` (+ interfaces): token-native extensions.
- `contracts/TwoPhaseToken.sol`, `TwoPhaseNFT.sol`, `Mock1155.sol`: concrete mocks used by the
  tests.
- `test/`: Foundry test suites, including the negative tests showing that no on-chain
  observation yields transferable secret material.

Requires OpenZeppelin Contracts v5 and forge-std. To run the tests in a Foundry project:

```
forge install OpenZeppelin/openzeppelin-contracts
forge test
```
