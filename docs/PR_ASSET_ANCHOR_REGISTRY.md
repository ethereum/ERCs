# Upstream PR: Asset Anchor Registry Interface

Use this body when opening a PR from `KulaDao:erc/asset-anchor-registry` to `ethereum/ERCs` `master`.

```bash
gh pr create --repo ethereum/ERCs \
  --head KulaDao:erc/asset-anchor-registry \
  --base master \
  --title "ERC: Asset Anchor Registry Interface" \
  --body-file docs/PR_ASSET_ANCHOR_REGISTRY.md
```

---

## Summary

- Adds draft ERC: **Asset Anchor Registry Interface** (`ERCS/erc-asset_anchor_registry.md`)
- Full spec: registry-scoped token-to-anchor binding, lifecycle, optional recovery (`invalidateTokenBinding`, `registerAndBind`)
- Reference implementation: [`packages/erc-asset-registry`](https://github.com/KulaDao/titled-asset-standards/tree/caa9b05/packages/erc-asset-registry) @ [`caa9b05`](https://github.com/KulaDao/titled-asset-standards/commit/caa9b05) — **86 tests** pass

## Discussion

- Meta thread: https://ethereum-magicians.org/t/proposing-a-family-of-candidate-erc-interfaces-for-titled-asset-infrastructure-architecture-review/28913
- Dedicated Proposal 1 thread: https://ethereum-magicians.org/t/asset-anchor-registry-interface-candidate-erc/28934

## Reference implementation

| | |
|---|---|
| Repository | https://github.com/KulaDao/titled-asset-standards |
| Package | https://github.com/KulaDao/titled-asset-standards/tree/caa9b05/packages/erc-asset-registry |
| Security review | https://github.com/KulaDao/titled-asset-standards/tree/main/docs/security |

## Authors

Chris Turner, David Hay (@david-hay), Reagan Simpson (@krumg111), Collins Musyimi (@Musyimi97)

## Deployment notes

None — spec-only PR.

## Test plan

- [ ] `eipw` / CI green on `ethereum/ERCs`
- [x] `discussions-to` points to dedicated Magicians thread
- [ ] Spec matches `packages/erc-asset-registry` at `caa9b05`
