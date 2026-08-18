# GitHub Actions Workflows

## CI Workflow (`ci.yml`)

The main CI workflow runs on pull requests and includes HTMLProofer, Link
Check, CodeSpell, EIP Walidator, and Markdown Linter.

### HTMLProofer notes

The HTMLProofer job keeps pull-request runs fast by combining three tactics:

- restore file mtimes after checkout so Jekyll's incremental build can skip
  unchanged inputs
- cache `_site/` and `.jekyll-metadata` between runs
- run HTMLProofer only on changed ERC pages when the pull request changes
  ERC markdown files and nothing else

The optimization is intentionally conservative:

- any non-ERC-markdown change falls back to a full HTMLProofer run
- PR reruns can reuse caches created by earlier runs of the same PR, but those
  caches stay scoped to that PR's merge ref and are not shared with unrelated
  PRs
- cache restore/save behavior follows normal GitHub Actions cache scoping for
  the current branch, the pull request base branch, and the default branch
- the workflow file itself is the source of truth; keep this README high-level
