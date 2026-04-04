# ERC-8185: Off-Chain Entity Registry — Reference Implementation

Minimal, self-contained reference implementation of the Off-Chain Entity Registry standard.

## Contracts

| File | Description |
|------|-------------|
| `IOffChainEntityRegistry.sol` | Standard interface |
| `IVerifier.sol` | Verifier interface |
| `OffChainEntityRegistry.sol` | Minimal registry implementation |
| `OracleVerifier.sol` | Example EIP-712 oracle verifier |

## Notes

- This implementation uses a simple `admin` address for access control. Production deployments should use a more robust governance mechanism.
- Namespace labels are validated as lowercase ASCII matching `[a-z0-9-]+`.
- The `OracleVerifier` is one possible verifier implementation. The standard supports any verification mechanism (ZK proofs, DNSSEC, etc.) through the `IVerifier` interface.
- This implementation does not include account functionality. See [ERC-8186](../../erc-8186-identity-account.md) for the companion identity account standard.
