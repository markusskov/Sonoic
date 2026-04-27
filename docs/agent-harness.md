# Agent Harness

This document adapts the harness engineering ideas from OpenAI's article [Harness engineering: leveraging Codex in an agent-first world](https://openai.com/index/harness-engineering/) to Sonoic.

The goal is not to copy a large-company process. The goal is to make Sonoic legible enough that agents can work safely with less human re-explaining.

## Principles

- `AGENTS.md` is a map, not a manual.
- Repository-local Markdown is the source of truth for product, architecture, quality, reliability, and security context.
- Larger work gets an execution plan that records scope, acceptance criteria, progress, decisions, and validation.
- Rules that matter should become scripts or CI checks when possible.
- Human taste should be captured once in docs or tooling, then reused by future agents.

## Sonoic Harness Layout

```text
AGENTS.md
ARCHITECTURE.md
docs/
  agent-harness.md
  design-docs/
  exec-plans/
  generated/
  product-specs/
  references/
  QUALITY_SCORE.md
  RELIABILITY.md
  SECURITY.md
scripts/
  agent_harness_check.py
```

## Agent Workflow

### Small Changes

Use this path for narrow fixes, docs updates, and low-risk polish.

1. Read `AGENTS.md`.
2. Read the specific docs linked from the task area.
3. Make the focused change.
4. Update docs if behavior, setup, or architecture changed.
5. Run `python3 scripts/agent_harness_check.py`.
6. Run Xcode validation if code-affecting files changed.

### Larger Changes

Use this path when the work spans multiple areas or changes architecture.

1. Copy [exec-plans/template.md](exec-plans/template.md) into `docs/exec-plans/active/`.
2. Fill in goal, scope, acceptance criteria, risks, validation, and a progress checklist.
3. Keep the plan current as decisions are made.
4. Move the plan to `docs/exec-plans/completed/` when the work lands.
5. Update [exec-plans/tech-debt-tracker.md](exec-plans/tech-debt-tracker.md) for any intentional follow-up.

### Doc Gardening

Use this path when docs drift from the app.

1. Compare claims in `README.md`, `plan.md`, `ARCHITECTURE.md`, and `docs/`.
2. Prefer deleting stale claims over adding caveats.
3. Keep the same fact in one primary place and link to it elsewhere.
4. Run the harness check to catch broken links and missing required files.

## Mechanical Checks

The first check is intentionally small:

```sh
python3 scripts/agent_harness_check.py
```

It verifies the required harness files exist, `AGENTS.md` stays compact, local Markdown links resolve, execution-plan templates keep required sections, and tracked local Xcode artifacts do not sneak into the repo.

This script is also run by the Agent Harness GitHub workflow.

## Future Harness Upgrades

- Add structural checks for app/shared/widget dependency direction.
- Add file-size and feature-folder drift checks once the codebase grows.
- Add generated architecture summaries under `docs/generated/`.
- Add simulator or device smoke-test scripts for the core player, queue, rooms, settings, and widget flows.
