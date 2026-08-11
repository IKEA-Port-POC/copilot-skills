---
name: github-ci
description: Use when debugging CI failures, reading build logs, or rerunning GitHub Actions workflows. For PR operations, use the github skill instead.
---

# GitHub CI / Actions Skill

The `gh` CLI is installed and authenticated against `github.com`. All commands
accept `-R OWNER/REPO` to target a specific repository. When working inside a
git repo, `-R` can be omitted and `gh` infers the remote automatically.

> **Pull Requests:** For creating, editing, or reviewing PRs, load the
> **github** skill instead.

---

## Extracting Repo and Run ID from a GitHub Actions URL

When the user pastes an Actions URL, extract the repo and run ID from it:

```bash
RUN_URL="https://github.com/OWNER/REPO/actions/runs/RUN_ID"
RUN_ID="${RUN_URL##*/}"
REPO=$(echo "$RUN_URL" | sed 's|https://github.com/||;s|/actions/.*||')
# RUN_ID=<run-id>  REPO=OWNER/REPO
```

---

## List Runs

```bash
# Last 10 runs (all workflows)
gh run list -R OWNER/REPO --limit 10

# Filter by workflow name or branch
gh run list -R OWNER/REPO --workflow "CI" --limit 10
gh run list -R OWNER/REPO --branch main --limit 5

# Only failed runs
gh run list -R OWNER/REPO --status failure --limit 5

# JSON output
gh run list -R OWNER/REPO --limit 5 \
  --json databaseId,name,status,conclusion,headBranch,createdAt \
  --jq '.[]'
```

## View a Run

```bash
# Summary with job list
gh run view 22520098533 -R OWNER/REPO

# With detailed step breakdown
gh run view 22520098533 -R OWNER/REPO --verbose

# Structured JSON summary — what failed?
gh run view 22520098533 -R OWNER/REPO \
  --json conclusion,name,jobs \
  --jq '{
    name,
    conclusion,
    failed_jobs: [.jobs[] | select(.conclusion == "failure") | {
      name,
      failed_steps: [.steps[] | select(.conclusion == "failure") | .name]
    }]
  }'

# Get job IDs (needed to fetch logs per job)
gh run view 22520098533 -R OWNER/REPO \
  --json jobs \
  --jq '[.jobs[] | {name, databaseId, conclusion}]'
```

## Read CI Logs

```bash
# Logs for failed steps only (fastest way to see what broke)
gh run view 22520098533 -R OWNER/REPO --log-failed

# Full log for a specific job (use job databaseId from the view above)
gh run view --job 65243538037 -R OWNER/REPO --log

# Full log for the entire run (can be large)
gh run view 22520098533 -R OWNER/REPO --log
```

> **Tip:** `--log-failed` returns nothing if the run succeeded. Always check
> the conclusion first with `--json conclusion --jq '.conclusion'` before
> deciding whether to use `--log-failed` or `--log`.

## Rerun Failed Jobs

```bash
# Rerun only the failed jobs (not the whole run)
gh run rerun 22520098533 -R OWNER/REPO --failed

# Rerun the entire run
gh run rerun 22520098533 -R OWNER/REPO
```

---

## Workflow for Diagnosing a Failing CI Run

Given a URL like `https://github.com/OWNER/REPO/actions/runs/RUN_ID`:

```bash
# 1. Extract repo and run ID
RUN_URL="https://github.com/OWNER/REPO/actions/runs/RUN_ID"
RUN_ID="${RUN_URL##*/}"
REPO=$(echo "$RUN_URL" | sed 's|https://github.com/||;s|/actions/.*||')

# 2. Get a structured summary
gh run view "$RUN_ID" -R "$REPO" \
  --json conclusion,name,jobs \
  --jq '{
    name, conclusion,
    failed_jobs: [.jobs[] | select(.conclusion == "failure") | {
      name,
      failed_steps: [.steps[] | select(.conclusion == "failure") | .name]
    }]
  }'

# 3. Read only the failing log lines
gh run view "$RUN_ID" -R "$REPO" --log-failed

# 4. If you need the full log for a specific job
JOB_ID=$(gh run view "$RUN_ID" -R "$REPO" \
  --json jobs \
  --jq '[.jobs[] | select(.conclusion == "failure") | .databaseId][0]')
gh run view --job "$JOB_ID" -R "$REPO" --log
```

---

## Error Handling

| Situation | What to do |
|-----------|------------|
| `gh auth status` shows not logged in | Run `gh auth login` |
| `403 Resource not accessible` | Token lacks the required scope — run `gh auth refresh -s <scope>` |
| Run ID not found | Verify the URL — the run may have been deleted; use `gh run list` |
| `--log-failed` returns nothing | Run succeeded; use `--log` or `--verbose` instead |
