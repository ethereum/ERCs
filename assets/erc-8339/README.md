# Receiver-Attested Transfers: reference implementation

- `contracts/IFrameConsentGuard.sol`: the interface specified by the ERC.
- `contracts/FrameConsentGuard.sol`: the guard. It checks the receiver's EIP-712 consent
  (ECDSA or ERC-1271) against the next frame of the EIP-8141 transaction and records each
  consent as used. No custody, no owner, no upgradability.
- `contracts/FrameIntrospector.yul` (+ `IFrameIntrospector.sol`): a stateless wrapper that
  exposes the EIP-8141 `TXPARAM`, `FRAMEPARAM` and `FRAMEDATACOPY` opcodes via `verbatim`.
  It compiles today but runs only on an EIP-8141 client.
- `contracts/ConsentCodec.sol`: the canonical `ConsentRequest` / `ConsentResponse` bytes.
- `contracts/MockFrameIntrospector.sol`: a settable stand-in that describes a frame
  transaction on today's EVM, used by the tests.
- `test/FrameConsentGuard.t.sol`, `test/ConsentCodec.t.sol`: the Foundry suite. It covers
  native and ERC-20 happy paths, typo'd receivers, wrong-key signatures, the missing atomic
  flag, the wrong frame mode, expiry, replay (same sender and third party), rollback of the
  used record on a failed transfer, and ERC-1271 receivers.

ERC-721 / ERC-1155 frame matching (`_matchNftCall`) is not implemented yet and fails closed.

Requires OpenZeppelin Contracts v5 and forge-std. To run the tests in a Foundry project with
`src = "contracts"`:

```
forge install OpenZeppelin/openzeppelin-contracts
forge test
```
