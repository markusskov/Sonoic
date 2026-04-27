# Execution Plans

Execution plans are versioned working memory for changes that are too broad or risky to keep in a chat transcript.

## Folders

- [active](active/) contains plans currently in progress.
- [completed](completed/) contains finished plans kept for design history.
- [template.md](template.md) is the plan template.
- [tech-debt-tracker.md](tech-debt-tracker.md) captures intentional follow-up work.

## Use A Plan When

- the change spans multiple top-level folders
- the change affects architecture, App Groups, entitlements, background behavior, or now-playing ownership
- the change introduces a new tool, CI job, target, package, or persistent workflow
- the work needs a decision log or staged validation

Small changes can stay plan-free as long as the PR explains the scope and verification clearly.
