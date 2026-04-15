# Contributing To Sonoic

Thanks for taking a look at Sonoic.

The project is still early, so the best contributions are the ones that keep momentum high without adding unnecessary structure.

## Before You Start

- Read [README.md](README.md) for product direction and setup notes.
- Read [plan.md](plan.md) for the current roadmap and architecture guardrails.
- If you plan a larger change, open an issue or discussion first so we can align on scope.

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

- make sure the project builds
- remove temporary debug code and logging
- make sure the diff does not include personal Xcode state
- update `README.md` or `plan.md` when project behavior or setup changed
- keep the PR description clear about what changed and why

## Scope Guidance

Good near-term contribution areas:

- improving the native now-playing path
- making room or target data more real
- queue, grouping, favorites, and playlist flows
- better home theater controls and diagnostics
- bug fixes and polish in the player, widget, and shared state path

Please avoid broad refactors that introduce architecture without a concrete product need.
