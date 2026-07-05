# Upstream PR: Subject-Linked Compliance Event Log

Use this body when opening a PR from `KulaDao:erc/compliance-event-log` to `ethereum/ERCs` `master`.

```bash
gh pr create --repo ethereum/ERCs \
  --head KulaDao:erc/compliance-event-log \
  --base master \
  --title "ERC: Subject-Linked Compliance Event Log" \
  --body-file docs/PR_COMPLIANCE_EVENT_LOG.md
```

---

## Summary

- Adds draft ERC: **Subject-Linked Compliance Event Log** (`ERCS/erc-compliance_event_log.md`)
- Reference implementation: [`erc-compliance-event-log`](https://github.com/KulaDao/titled-asset-standards/tree/caa9b05/packages/erc-compliance-event-log) @ [`caa9b05`](https://github.com/KulaDao/titled-asset-standards/commit/caa9b05) — **17 tests** pass

## Discussion

- Meta thread: https://ethereum-magicians.org/t/proposing-a-family-of-candidate-erc-interfaces-for-titled-asset-infrastructure-architecture-review/28913
- Dedicated Proposal 4 thread: _(paste URL after Magicians post — update `discussions-to` in ERC front matter)_

## Reference implementation

| | |
|---|---|
| Repository | https://github.com/KulaDao/titled-asset-standards |
| Package | https://github.com/KulaDao/titled-asset-standards/tree/caa9b05/packages/erc-compliance-event-log |
| Security review | https://github.com/KulaDao/titled-asset-standards/tree/main/docs/security |

## Authors

Chris Turner, David Hay (@david-hay), Reagan Simpson (@krumg111), Collins Musyimi (@Musyimi97)

## Deployment notes

None — spec-only PR.

## Test plan

- [ ] `eipw` / CI green on `ethereum/ERCs`
- [ ] `discussions-to` points to dedicated Magicians thread (meta thread interim)
- [ ] Spec matches `erc-compliance-event-log` at `caa9b05`
