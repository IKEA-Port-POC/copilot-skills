#!/usr/bin/env bash
set -euo pipefail

# Validates that all PII strings and paths have been removed from git history.
# Run BEFORE rewrite (to confirm PII is found) and AFTER (to confirm it's gone).
#
# Usage: ./verify.sh
#
# Expects to be run inside the git repo being cleaned.
# Optional files in the current directory:
#   paths.txt        — paths to verify are gone (supports glob: and regex: prefixes)
#   replacements.txt — PII strings to verify are gone (format: literal==>replacement)

failed=0

# Every path on the manifest should be unreachable from any ref.
if [[ -f paths.txt ]]; then
  git log --all --pretty=format: --name-only | sort -u > all-paths.txt
  total=$(grep -cve '^$' paths.txt)
  i=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    i=$((i+1))
    echo "[$i/$total] checking path: $p"
    case "$p" in
      glob:*)
        pat="${p#glob:}"
        if git log --all --oneline -- ":(glob)$pat" | grep -q .; then
          echo "STILL REACHABLE: $p"
          failed=1
        fi
        ;;
      regex:*)
        pat="${p#regex:}"
        if grep -E -- "$pat" all-paths.txt >/dev/null; then
          echo "STILL REACHABLE: $p"
          failed=1
        fi
        ;;
      *)
        if git log --all --oneline -- "$p" | grep -q .; then
          echo "STILL REACHABLE: $p"
          failed=1
        fi
        ;;
    esac
  done < paths.txt
fi

# Every redaction string should be absent from every commit.
if [[ -f replacements.txt ]]; then
  total=$(grep -cve '^$' replacements.txt)
  i=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Format: literal==>replacement — extract the left-hand side
    needle="${line%%==>*}"
    [[ -z "$needle" ]] && continue
    i=$((i+1))
    echo "[$i/$total] checking redaction: $needle"
    case "$needle" in
      regex:*)
        pat="${needle#regex:}"
        if git log --all --format=%H -G "$pat" | head -1 | grep -q .; then
          echo "STILL PRESENT: $needle"
          failed=1
        fi
        ;;
      *)
        if git log --all --format=%H -S "$needle" | head -1 | grep -q .; then
          echo "STILL PRESENT: $needle"
          failed=1
        fi
        ;;
    esac
  done < replacements.txt
fi

# How many PR refs were affected?
changed_refs="$(git rev-parse --git-dir)/filter-repo/changed-refs"
if [[ -f "$changed_refs" ]]; then
  echo "Affected PR refs:"
  grep -c '^refs/pull/.*/head$' "$changed_refs" || true
else
  echo "changed-refs not found (only written by --sensitive-data-removal in git-filter-repo >=2.47)"
fi

# Compare counts and size
git for-each-ref --format='%(refname)' > refs-after.txt
git rev-list --all --count > commit-count-after.txt
du -sh . > size-after.txt
diff commit-count-before.txt commit-count-after.txt || true

# A correct rewrite shrinks history; it never zeros it out.
after=$(cat commit-count-after.txt)
if [[ "$after" -eq 0 ]]; then
  echo "FATAL: history is empty after rewrite — did you forget --invert-paths?"
  failed=1
fi

if [[ "$failed" -eq 0 ]]; then
  echo "verify passed — manifest paths and replacement strings are gone"
else
  echo "verify FAILED — revisit your manifest before pushing"
  exit 1
fi
