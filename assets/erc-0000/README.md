# Wallet Pass Extension for NFTs: Assets

| Path | Contents |
| --- | --- |
| [`reference/`](./reference/README.md) | Reference implementation (CC0): a minimal ERC-721 implementing `IERC721WalletPass` with Foundry tests, and an off-chain server implementing the challenge floor, both manifest configurations, and capability URL rotation, with vitest tests. |
| [`implementation-notes.md`](./implementation-notes.md) | Non-normative deployment notes: how a production deployment implements the interface and a gated manifest endpoint, delivers passes on Apple Wallet and Google Wallet, and applies the authorization requirements, with lessons learned. |
| [`screenshots/`](./screenshots/README.md) | Screenshots of a live deployment on both platforms. |

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

Expected: 15 contract tests and 17 server tests pass.
