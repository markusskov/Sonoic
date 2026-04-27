# Sonoic Agent Guide

## Project Shape
Sonoic is an iPhone-first Sonos controller. Keep changes small, user-facing, and feature-shaped.

## First Reads
- Product direction: [README.md](README.md)
- Current roadmap and guardrails: [plan.md](plan.md)
- Architecture map: [ARCHITECTURE.md](ARCHITECTURE.md)
- Agent harness workflow: [docs/agent-harness.md](docs/agent-harness.md)

## Architecture
- Preserve the single top-level `SonoicModel` until code proves it needs splitting.
- Organize by feature and screen, not abstract layers.
- Prefer concrete Swift types over protocol-heavy scaffolding.
- Avoid broad “foundation” rewrites without a concrete product slice.

## Build
Use:
`xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

For simulator checks, use the currently booted simulator when available.

For docs, process, or harness changes, also use:
`python3 scripts/agent_harness_check.py`

## PR Rules
- Stage only files relevant to the task.
- Do not include personal Xcode state.
- Mention manual device verification when changes affect Sonos LAN behavior, widgets, Lock Screen, Control Center, or now-playing state.
