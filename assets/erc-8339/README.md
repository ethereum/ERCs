# Two-Phase Asset Transfers: reference implementation

- `contracts/TwoPhaseEscrow.sol` (+ `ITwoPhaseEscrow.sol`): the escrow, covering native ETH
  and any ERC-20 / ERC-721 / ERC-1155.
- `contracts/MockERC20.sol`, `MockERC721.sol`, `Mock1155.sol`: minimal mintable mocks used by
  the tests.
- `test/TwoPhaseEscrow.t.sol`: Foundry suite covering all four asset kinds, both acceptance
  modes, and the negative tests showing that no on-chain observation yields transferable
  secret material.

Requires OpenZeppelin Contracts v5 and forge-std. To run the tests in a Foundry project:

```
forge install OpenZeppelin/openzeppelin-contracts
forge test
```
