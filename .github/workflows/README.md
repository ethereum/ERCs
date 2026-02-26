# GitHub Actions Workflows

## CI Workflow (`ci.yml`)

The main CI workflow runs on every pull request and includes:
HTMLProofer, Link Check, CodeSpell, EIP Walidator, and Markdown Linter.

### HTMLProofer Job — Incremental Build Architecture

The HTMLProofer job builds the full EIPs + ERCs website with Jekyll
and then runs HTMLProofer against it. A full Jekyll build takes **6+ minutes**,
so incremental builds are used to speed up the common case
(a PR that only touches one or a few ERC files).

#### High-Level Flow

```
Checkout EIPs repo (full history)
        │
        ▼
Restore file mtimes from git ──► Ensures unchanged files keep
        │                         their original timestamps
        ▼
Checkout ERCs repo (full history)
        │
        ▼
Restore file mtimes from git
        │
        ▼
Detect changed files ──────────► If only ERC files changed → "incremental" mode
        │                         Otherwise → "full" mode
        ▼
Merge EIPs + ERCs into one tree
        │
        ▼
Restore Jekyll cache ─────────► Downloads _site/ and .jekyll-metadata
        │                         from a previous run
        ▼
Jekyll build ─────────────────► incremental mode: `jekyll build --incremental`
        │                         full mode: `jekyll build`
        ▼
HTMLProofer ──────────────────► incremental mode: only checks changed ERC pages
                                  full mode: checks entire _site/
```

#### Why `git-restore-mtime`?

Jekyll's `--incremental` flag works by comparing each source file's
**modification time (mtime)** against timestamps stored in `.jekyll-metadata`
from the previous build. If a file's mtime hasn't changed, Jekyll skips it.

The problem: `actions/checkout` sets **all file mtimes to the checkout time**
(i.e., "now"), so every file looks "modified" and Jekyll rebuilds everything —
even with `--incremental` enabled.

The fix: after checkout, we restore each file's mtime to its **last git commit
timestamp**:

```bash
git ls-files -z | while IFS= read -r -d '' file; do
  ts=$(git log -1 --format=%ct -- "$file" || true)
  [ -n "$ts" ] && touch -d "@$ts" "$file"
done
```

This gives unchanged files consistent timestamps across CI runs,
so Jekyll can correctly identify which files actually changed.

> **Why not use file content hashes instead of timestamps?**
> Jekyll uses mtime by design (like `make`). Other tools (e.g., Webpack, Vite)
> use content hashes, but Jekyll does not support this. The `git-restore-mtime`
> approach works within Jekyll's existing architecture.

#### Cache Strategy

The Jekyll cache stores two artifacts:

| Artifact | Purpose |
|----------|---------|
| `_site/` | Previously built HTML output |
| `.jekyll-metadata` | File mtimes and dependency graph from last build |

**Cache key design:**

```yaml
key: jekyll-${{ runner.os }}-eips-${{ steps.eips.outputs.sha }}
restore-keys: |
  jekyll-${{ runner.os }}-
```

- **`key`** includes the EIPs repo SHA, so each unique EIPs version gets its
  own cache entry. This also ensures a new cache is saved after each build
  (since `actions/cache` only saves when there's no exact key match).
- **`restore-keys`** uses a broad prefix, so even when the EIPs SHA changes,
  the most recent cache is still restored as a starting point.

**GitHub Actions cache scoping rules:**

| Cache source | Accessible? |
|-------------|-------------|
| Current branch | ✅ |
| PR base branch (target) | ✅ |
| Default branch (`master`) | ✅ |
| Other unrelated branches | ❌ |

This means a PR branch automatically has access to caches created by its
base branch or by `master`, without any extra configuration.

**Important:** `actions/cache` outputs `cache-hit=true` **only for exact key
matches**. When a cache is restored via `restore-keys` (partial match),
`cache-hit` is `false` even though files were successfully downloaded.
For this reason, the Build Website step does **not** check `cache-hit`.
Instead, it always uses `--incremental` when the PR only touches ERC files,
and Jekyll itself handles the fallback (if `.jekyll-metadata` is missing,
`--incremental` automatically performs a full build).

#### Merge Repos Step

The EIPs and ERCs repositories are merged into a single directory tree
for Jekyll to build. The `cp -rp` flag is used (not `cp -r`) to **preserve
file modification times** during the copy — otherwise the mtime restoration
from the previous step would be lost.

#### HTMLProofer Scoping

In incremental mode, HTMLProofer only checks the pages corresponding to
changed ERCs (e.g., `_site/EIPS/eip-1234/`), avoiding a full-site scan
that would add several minutes.
