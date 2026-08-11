# copilot-skills

Sample GitHub Copilot CLI skills and agents for evaluation purposes.

## Skills

Each skill is a self-contained folder under `skills/` with a `SKILL.md`
(instructions for the agent) and a `manifest.yml` (metadata).

| Skill | Purpose |
|-------|---------|
| `github` | Open and update PRs, comments, and reviews via the `gh` CLI. |
| `github-ci` | Debug CI failures, read build logs, and rerun GitHub Actions workflows. |
| `kotlin-review` | Review Kotlin sources, Gradle configs, and Flyway migrations. |
| `pii-cleanup` | Remove PII from a repository's git history with `git filter-repo`. |

## Agents

Each agent is a single `.agent.md` persona file under `agents/`.

| Agent | Purpose |
|-------|---------|
| `software-engineer` | Implement a change end-to-end: branch, plan, code, open a draft PR, and drive review to a review-ready state. |
| `support-engineer` | Investigate a support ticket or alert read-only and produce a root-cause report with reproducible evidence. |
