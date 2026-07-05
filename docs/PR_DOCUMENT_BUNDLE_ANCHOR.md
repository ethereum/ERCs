# Upstream PR: Canonical Document Bundle Anchor

Use this body when opening a PR from `KulaDao:erc/document-bundle-anchor` to `ethereum/ERCs` `master`.

```bash
gh pr create --repo ethereum/ERCs \
  --head KulaDao:erc/document-bundle-anchor \
  --base master \
  --title "ERC: Canonical Document Bundle Anchor" \
  --body-file docs/PR_DOCUMENT_BUNDLE_ANCHOR.md
```

---

## Summary

- Adds draft ERC: **Canonical Document Bundle Anchor** (`ERCS/erc-document_bundle_anchor.md`)
- Full spec: normalization profiles, manifest total order, bundle hash, supersession, optional slot-principal recovery (`assignSlotPrincipal`)
- Reference implementation: [`packages/erc-document-bundle-anchor`](https://github.com/KulaDao/titled-asset-standards/tree/caa9b05/packages/erc-document-bundle-anchor) @ [`caa9b05`](https://github.com/KulaDao/titled-asset-standards/commit/caa9b05) — **104 tests** pass

## Discussion

- Meta thread: https://ethereum-magicians.org/t/proposing-a-family-of-candidate-erc-interfaces-for-titled-asset-infrastructure-architecture-review/28913
- Dedicated Proposal 2 thread: _(paste URL after Magicians post — update `discussions-to` in ERC front matter)_

## Reference implementation

| | |
|---|---|
| Repository | https://github.com/KulaDao/titled-asset-standards |
| Package | https://github.com/KulaDao/titled-asset-standards/tree/caa9b05/packages/erc-document-bundle-anchor |
| Security review | https://github.com/KulaDao/titled-asset-standards/tree/main/docs/security |

## Authors

Chris Turner, David Hay (@david-hay), Reagan Simpson (@krumg111), Collins Musyimi (@Musyimi97)

## Deployment notes

None — spec-only PR.

## Test plan

- [ ] `eipw` / CI green on `ethereum/ERCs`
- [ ] `discussions-to` points to dedicated Magicians thread (meta thread interim)
- [ ] Spec matches `packages/erc-document-bundle-anchor` at `caa9b05`
