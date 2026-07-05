# Upstream PR: Subject-Linked Impact Snapshot Log

Use this body when opening a PR from `KulaDao:erc/impact-snapshot-log` to `ethereum/ERCs` `master`.

```bash
gh pr create --repo ethereum/ERCs \
  --head KulaDao:erc/impact-snapshot-log \
  --base master \
  --title "ERC: Subject-Linked Impact Snapshot Log" \
  --body-file docs/PR_IMPACT_SNAPSHOT_LOG.md
```

---

## Summary

- Adds draft ERC: **Subject-Linked Impact Snapshot Log** (`ERCS/erc-impact_snapshot_log.md`)
- Reference implementation: [`erc-impact-snapshot`](https://github.com/KulaDao/titled-asset-standards/tree/caa9b05/packages/erc-impact-snapshot) @ [`caa9b05`](https://github.com/KulaDao/titled-asset-standards/commit/caa9b05) — **46 tests** pass

## Discussion

- Meta thread: https://ethereum-magicians.org/t/proposing-a-family-of-candidate-erc-interfaces-for-titled-asset-infrastructure-architecture-review/28913
- Dedicated Proposal 5 thread: _(paste URL after Magicians post — update `discussions-to` in ERC front matter)_

## Reference implementation

| | |
|---|---|
| Repository | https://github.com/KulaDao/titled-asset-standards |
| Package | https://github.com/KulaDao/titled-asset-standards/tree/caa9b05/packages/erc-impact-snapshot |
| Security review | https://github.com/KulaDao/titled-asset-standards/tree/main/docs/security |

## Authors

Chris Turner, David Hay (@david-hay), Reagan Simpson (@krumg111), Collins Musyimi (@Musyimi97)

## Deployment notes

None — spec-only PR.

## Test plan

- [ ] `eipw` / CI green on `ethereum/ERCs`
- [ ] `discussions-to` points to dedicated Magicians thread (meta thread interim)
- [ ] Spec matches `erc-impact-snapshot` at `caa9b05`
