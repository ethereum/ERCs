# ERC-8320: Regulated Asset Claim reference implementation

Reference implementation for ERC-8320.

## Layout

| Path | Contents |
|---|---|
| `contracts/interfaces/IRegulatedAssetClaimRegistry.sol` | Claim registry, lifecycle, roles, and asset-resolution interface |
| `contracts/interfaces/IRegistryAnchor.sol` | Asset-side registry-approval interface |
| `contracts/RegulatedAssetClaimRegistry.sol` | Claim registry (reference implementation) |
| `contracts/RegistryAnchor.sol` | Reference asset-side registry anchor |
| `test/` | Foundry tests |

## Build

```sh
forge build
forge test
```
