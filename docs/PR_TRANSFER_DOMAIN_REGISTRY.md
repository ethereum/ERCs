# Upstream PR: Directional Transfer Domain Registry

Use this body when opening a PR from `KulaDao:erc/transfer-domain-registry` to `ethereum/ERCs` `master`.

```bash
gh pr create --repo ethereum/ERCs \
  --head KulaDao:erc/transfer-domain-registry \
  --base master \
  --title "ERC: Directional Transfer Domain Registry" \
  --body-file docs/PR_TRANSFER_DOMAIN_REGISTRY.md
```

---

## Summary

- Adds draft ERC: **Directional Transfer Domain Registry** (`ERCS/erc-transfer_domain_registry.md`)
- Reference implementation: [`erc-transfer-domain`](https://github.com/KulaDao/titled-asset-standards/tree/caa9b05/packages/erc-transfer-domain) @ [`caa9b05`](https://github.com/KulaDao/titled-asset-standards/commit/caa9b05) — **49 tests** pass

## Discussion

- Meta thread: https://ethereum-magicians.org/t/proposing-a-family-of-candidate-erc-interfaces-for-titled-asset-infrastructure-architecture-review/28913
- Dedicated Proposal 3 thread: _(paste URL after Magicians post — update `discussions-to` in ERC front matter)_

## Reference implementation

| | |
|---|---|
| Repository | https://github.com/KulaDao/titled-asset-standards |
| Package | https://github.com/KulaDao/titled-asset-standards/tree/caa9b05/packages/erc-transfer-domain |
| Security review | https://github.com/KulaDao/titled-asset-standards/tree/main/docs/security |

## Authors

Chris Turner, David Hay (@david-hay), Reagan Simpson (@krumg111), Collins Musyimi (@Musyimi97)

## Deployment notes

None — spec-only PR.

## Test plan

- [ ] `eipw` / CI green on `ethereum/ERCs`
- [ ] `discussions-to` points to dedicated Magicians thread (meta thread interim)
- [ ] Spec matches `erc-transfer-domain` at `caa9b05`
