# Contributing To Sonoic

Thanks for taking a look at Sonoic.

The project is still early, so the best contributions are the ones that keep momentum high without adding unnecessary structure.

## Before You Start

- Read [README.md](README.md) for product direction and setup notes.
- Read [plan.md](plan.md) for the current roadmap and architecture guardrails.
- Read [AGENTS.md](AGENTS.md) for the agent-readable project map.
- If you plan a larger change, open an issue or discussion first so we can align on scope.
- For broad or risky work, create an execution plan from [docs/exec-plans/template.md](docs/exec-plans/template.md).

## What Good Contributions Look Like

- Small, focused pull requests
- Real user-facing progress over speculative infrastructure
- Clear reasoning when changing architecture or project structure
- Updates to docs when behavior or setup changes

## Code Style

Sonoic aims to stay close to Apple’s modern SwiftUI sample style.

Please keep these rules in mind:

- Prefer direct, concrete code over generic abstractions
- Organize by feature and screen
- Keep helper types and views narrow
- Avoid adding managers, coordinators, factories, or protocol layers unless the code truly needs them
- Split files when they stop feeling like one coherent unit

## Pull Request Checklist

Before opening a pull request:

- make sure the project builds locally when needed
- make sure the latest PR commit is green in GitHub checks before asking to merge
- run `python3 scripts/agent_harness_check.py` when docs, scripts, or harness files changed
- remove temporary debug code and logging
- make sure the diff does not include personal Xcode state
- update docs when project behavior, architecture, setup, or verification changed
- keep the PR description clear about what changed and why

## CI And Branch Sync

Sonoic uses GitHub checks to keep the `main` branch safe.

- open a pull request early so the required `build-ios` check runs on each push
- wait for the latest PR commit to go green before merging `main` into your branch
- if you merge `main` into your branch, treat that merge commit as a fresh candidate and wait for `build-ios` to pass again
- do not merge while GitHub shows the branch is behind `main` or while required checks are still running or failing
- include manual device verification in the PR when the change depends on a real Sonos setup, widget behavior, or outside-app controls

## Scope Guidance

Good near-term contribution areas:

- improving the native now-playing path
- making room or target data more real
- queue, grouping, favorites, and playlist flows
- better home theater controls and diagnostics
- bug fixes and polish in the player, widget, and shared state path

Please avoid broad refactors that introduce architecture without a concrete product need.
