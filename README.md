# copilot-skills

Sample GitHub Copilot CLI skills for evaluation purposes.

Each skill is a self-contained folder under `skills/` with a `SKILL.md`
(instructions for the agent) and a `manifest.yml` (metadata).

| Skill | Purpose |
|-------|---------|
| `github` | Open and update PRs, comments, and reviews via the `gh` CLI. |
| `github-ci` | Debug CI failures, read build logs, and rerun GitHub Actions workflows. |
| `kotlin-review` | Review Kotlin sources, Gradle configs, and Flyway migrations. |
| `pii-cleanup` | Remove PII from a repository's git history with `git filter-repo`. |
