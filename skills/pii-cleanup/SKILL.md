---
name: pii-cleanup
description: Use when removing PII (personal identifiable information) from a GitHub repository's git history. Runs git filter-repo with --sensitive-data-removal to rewrite history, verify the scrub, and force-push the cleaned result.
---

# PII Cleanup

Remove personal identifiable information from a repository's entire git
history using `git filter-repo`. This skill handles the end-to-end flow:
freeze the repo, clone, build a replacement manifest, rewrite history,
verify, force-push, and unfreeze.

## Important Limitations

**GitHub cannot fully purge old commit data.** After a history rewrite and
force-push, GitHub's internal PR metadata still references the old commit
SHAs. GitHub Support can remove PR diffs but NOT the underlying cached
objects reliably. This means:

- The PII is removed from all **branch and tag history** (git level) ✓
- The PII may still be cached in **old PR diffs** on GitHub's servers ✗
- Any exposed PII should be considered **compromised** regardless

**If the PII truly must disappear from GitHub entirely**, the only reliable
approach is:
1. Quarantine (archive) the old repository
2. Fix the git history locally
3. Create a brand new repository and push the cleaned history there
4. All PR history from the old repo is **lost**

The workflow below covers the **in-place rewrite** approach (fix history,
force-push to the same repo). This removes PII from git history but old
PR diffs on GitHub may retain references.

## Bootstrap

### Prerequisites

- `git filter-repo` >= 2.47 (for `--sensitive-data-removal`)
- `gh` CLI authenticated with admin access to the target repo (needed for rulesets)

```bash
uv tool install git-filter-repo
git-filter-repo --version
```

Or run without installing:

```bash
uvx git-filter-repo --version
```

### verify.sh

The verification script is bundled at [`verify.sh`](./verify.sh). Copy it to
your cleanup working directory and make it executable:

```bash
cp "$(dirname "$0")/verify.sh" ~/Documents/cleanup/verify.sh
chmod +x ~/Documents/cleanup/verify.sh
```

It validates that all PII strings and paths have been removed from history.
Run it **before** the rewrite (to confirm PII is found) and **after** (to
confirm it's gone).

## Commands Reference

### Set up environment variables

```bash
export ORG=your-org
export REPO=<repo-name>
```

### Clone the repository

Clone with `--mirror` to get all refs (branches, tags, PR refs).

```bash
gh repo clone ${ORG}/${REPO} -- --mirror
cd $REPO
```

### Freeze the repository

Block all pushes with a ruleset so no one can push during the rewrite.

```bash
RULESET_ID=$(echo '{"name":"freeze-for-pii-cleanup","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~ALL"],"exclude":[]}},"rules":[{"type":"creation"},{"type":"update"},{"type":"deletion"},{"type":"non_fast_forward"}]}' | gh api --method POST "repos/${ORG}/${REPO}/rulesets" --input - --jq '.id') && echo "Ruleset ID: $RULESET_ID"
```

### Snapshot before rewrite

Capture baseline metrics for comparison after the rewrite.

```bash
git for-each-ref --format='%(refname)' > refs-before.txt
git rev-list --all --count > commit-count-before.txt
du -sh . > size-before.txt
```

### Build a replacement manifest

Create `replacements.txt` with one entry per line. Format: `literal==>replacement`.
Supports `regex:` prefix for pattern-based matching.

```text
secret.value@company.com==>redacted.user@example.com
REALUSERNAME==>TESTUSER1
regex:\b[\w.+-]+@company\.com\b==>REDACTED_EMAIL
```

Optionally create `paths.txt` listing files/paths to remove entirely (one per line).
Supports `glob:` and `regex:` prefixes:

```text
config/secrets.yml
glob:**/credentials*.json
regex:.*\.pem$
```

### Run the rewrite

For **text replacements** combined with **path removal**:

```bash
git filter-repo --force --sensitive-data-removal \
  --invert-paths \
  --replace-text replacements.txt
```

For text replacements only (no file deletion):

```bash
git filter-repo --force --sensitive-data-removal \
  --replace-text replacements.txt
```

For file deletion only:

```bash
git filter-repo --force --sensitive-data-removal \
  --invert-paths --path <file1> --path <file2>
```

> **Note:** `--force` is needed when running on a clone that already has a
> remote configured. `--invert-paths` means "remove these paths" — without
> it, filter-repo keeps only the listed paths (which would empty the repo).

### Verify the scrub

Run the verify script to check all replacement strings and paths are gone:

```bash
~/Documents/cleanup/verify.sh
```

Run it **before** the rewrite (to confirm PII is found) and **after** (to
confirm it's gone).

### Unfreeze the repository

Remove the freeze ruleset to allow force-push.

```bash
gh api --method DELETE "repos/${ORG}/${REPO}/rulesets/${RULESET_ID}"
```

### Force-push (branches + tags only)

Do NOT use `--mirror` for push — GitHub rejects writes to `refs/pull/*`.
Use `--no-verify` to skip any pre-push hooks.

```bash
git push origin --force --no-verify 'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
```

### Save changed-refs

Archive the changed-refs file for reference (e.g. if contacting GitHub Support).

```bash
cp /tmp/$REPO/.git/filter-repo/changed-refs ~/Documents/cleanup/${REPO}_changed-refs-pii-cleanup.txt
```

### Sync a local working directory

```bash
cd <PATH_TO_LOCAL_CLONE>
git fetch origin
git pull --rebase   # or: git reset --hard origin/main
```

## Workflow

1. **Gather inputs from the user:**
   - Repository: `<ORG>/<REPO>`
   - Local working directory path (to sync after)
   - PII strings and their replacements (or files to delete entirely)

2. **Generate and present the full command sequence:**

```bash
export ORG=your-org
export REPO=<REPO>

# 1. Clone
gh repo clone ${ORG}/${REPO} -- --mirror
cd $REPO

# 2. Freeze the repo (block all pushes)
RULESET_ID=$(echo '{"name":"freeze-for-pii-cleanup","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~ALL"],"exclude":[]}},"rules":[{"type":"creation"},{"type":"update"},{"type":"deletion"},{"type":"non_fast_forward"}]}' | gh api --method POST "repos/${ORG}/${REPO}/rulesets" --input - --jq '.id') && echo "Ruleset ID: $RULESET_ID"

# 3. Snapshot before
git for-each-ref --format='%(refname)' > refs-before.txt
git rev-list --all --count > commit-count-before.txt
du -sh . > size-before.txt

# 4. Build manifest
touch replacements.txt
# Edit replacements.txt — format: string_to_remove==>replacement
# Optionally create paths.txt with files to remove entirely

# 5. Verify before rewrite (baseline — should find the PII)
~/Documents/cleanup/verify.sh

# 6. Rewrite history
git filter-repo --force --sensitive-data-removal \
  --invert-paths \
  --replace-text replacements.txt

# 7. Verify after rewrite (should pass — PII is gone)
~/Documents/cleanup/verify.sh

# 8. Unfreeze the repo
gh api --method DELETE "repos/${ORG}/${REPO}/rulesets/${RULESET_ID}"

# 9. Force-push
git push origin --force --no-verify 'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'

# 10. Save changed-refs
cp /tmp/$REPO/.git/filter-repo/changed-refs ~/Documents/cleanup/${REPO}_changed-refs-pii-cleanup.txt

# 11. Sync working directory
cd <PATH_TO_LOCAL_CLONE>
git fetch origin
git pull --rebase
```

3. **If files should be deleted entirely** (not redacted), add `--path` flags
   or use a `paths.txt` in combination with `--invert-paths`.

4. **Remind the user to:**
   - Notify the team before starting ("repo is frozen for PII cleanup")
   - Notify the team after ("all clear — rebase your branches"):
     - `git fetch origin && git rebase origin/main` on every active branch
     - `git push --force-with-lease` to update remote feature branches
     - Do NOT `git pull` on main — use `git pull --rebase` or `git reset --hard origin/main`
   - Any exposed PII should be considered compromised (rotate secrets, etc.)
   - Old PR diffs on GitHub may still show the PII — GitHub cannot reliably purge them
   - If full deletion is required, quarantine the repo and create a new one

## Error Handling

| Error / status | Meaning | Action |
|----------------|---------|--------|
| `Refusing to run on non-fresh clone` | Running on a working clone without `--force` | Add `--force` flag |
| `deny updating a hidden ref` | Used `--mirror` push which tries to write `refs/pull/*` | Use explicit refspecs: `'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'` |
| Verification returns a SHA | PII still exists in history | Re-run `git filter-repo` with corrected manifest; check for typos |
| `remote: permission denied` on push | Branch protection or insufficient permissions | Ensure the freeze ruleset was deleted; check you have admin access |
| `remote origin already exists` | filter-repo removed origin and you're re-adding | Use `git remote set-url origin <url>` instead of `git remote add` |
| Push rejected with `non-fast-forward` | Freeze ruleset still active | Delete the freeze ruleset first |
| Ruleset creation returns 403 | Not a repo admin | Ask an admin to create the freeze, or skip and coordinate verbally |
| History is empty after rewrite (0 commits) | Used `--invert-paths` incorrectly | `--invert-paths` without specific `--path` flags removes everything; ensure you have `--replace-text` or explicit paths |
