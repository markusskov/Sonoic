# Contributing To Sonoic

Thanks for taking a look at Sonoic.

The project is still early, so the best contributions are small, concrete changes that improve real Sonos control without adding unnecessary structure.

## Before You Start

- Read [README.md](README.md) for product direction and setup notes.
- Read [ARCHITECTURE.md](ARCHITECTURE.md) for dependency rules and control-plane boundaries.
- Read [docs/ROADMAP.md](docs/ROADMAP.md) for current priorities.
- AI-assisted contributors should also read [AGENTS.md](AGENTS.md).
- If you plan a larger change, open an issue or draft PR first so we can align on scope.

## What Good Contributions Look Like

- Small, focused pull requests
- Real user-facing progress over speculative infrastructure
- Clear reasoning when changing architecture or project structure
- Tests or manual verification that match the risk of the change
- Docs updates when behavior, setup, architecture, or validation changes

## Code Style

Sonoic aims to stay close to Apple's modern SwiftUI sample style.

- Prefer direct, concrete code over generic abstractions.
- Organize by feature and screen.
- Keep helper types and views narrow.
- Avoid managers, coordinators, factories, and protocol layers unless the code truly needs them.
- Split files when they stop feeling like one coherent unit.
- Preserve the cloud-first control boundary: normal playback commands must not silently fall back to LAN.

## Pull Request Checklist

Before opening a pull request:

- make sure the project builds locally when needed
- make sure the latest PR commit is green in GitHub checks before asking to merge
- run `python3 scripts/agent_harness_check.py` when docs, scripts, project structure, or harness files changed
- remove temporary debug code and logging
- make sure the diff does not include personal Xcode state
- update docs when project behavior, architecture, setup, or verification changed
- keep the PR description clear about what changed and why

## CI And Branch Sync

Sonoic uses GitHub checks to keep `main` safe.

- open a pull request early so the required `build-ios` check runs on each push
- wait for the latest PR commit to go green before merging
- do not merge while GitHub shows the branch is behind `main` or while required checks are still running or failing
- include manual device verification when a change depends on real Sonos hardware, widgets, Lock Screen, Control Center, or now-playing state

## Scope Guidance

Good near-term contribution areas:

- hardening Sonos Cloud playback and queue behavior
- improving Apple Music source browsing while keeping playback Sonos-owned
- making room, target, queue, and now-playing state more dependable
- better home theater controls and diagnostics
- bug fixes and polish in the player, widget, shared state, and Worker paths

Please avoid broad refactors that introduce architecture without a concrete product need.
