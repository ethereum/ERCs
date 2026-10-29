# Wallet Pass Extension for NFTs: Assets

| Path | Contents |
| --- | --- |
| [`reference/`](./reference/README.md) | Reference implementation (CC0): a minimal ERC-721 implementing `IERC721WalletPass` with Foundry tests, and an off-chain server implementing the challenge floor, both manifest configurations, and capability URL rotation, with vitest tests. |
| [`implementation-notes.md`](./implementation-notes.md) | Non-normative appendix of platform notes: the Apple Wallet and Google Wallet behavior that shaped the requirements (push, notifications, shared objects, superseded passes, field limits), as met by one production deployment, and the lessons it learned. Names no product. |

## Running the reference tests

Contracts (Foundry):

```shell
cd reference/contracts
forge install foundry-rs/forge-std@v1.9.4 --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-git
forge test
```

Server (Node.js 22 or later):

```shell
cd reference/server
npm install
npx vitest run
```

Expected: 16 contract tests and 63 server tests pass.
