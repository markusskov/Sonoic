# Sonoic Agent Guide

## Project Shape
Sonoic is an iPhone-first, cloud-first Sonos controller. Keep changes small, user-facing, and feature-shaped.

## First Reads
- Product direction and setup: [README.md](README.md)
- Current roadmap: [docs/ROADMAP.md](docs/ROADMAP.md)
- Architecture map: [ARCHITECTURE.md](ARCHITECTURE.md)
- Docs index: [docs/README.md](docs/README.md)

## Architecture
- Preserve the single top-level `SonoicModel` until code proves it needs splitting.
- Sonos Control API owns normal playback, seek, volume, mute, now-playing, and Cloud Queue control.
- LAN is only for discovery/bootstrap, Advanced diagnostics, manual local mode, and local-only tuning.
- Organize by feature and screen, not abstract layers.
- Prefer concrete Swift types over protocol-heavy scaffolding.
- Avoid broad foundation rewrites without a concrete product slice.

## Build
Use:
`xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

For simulator checks, use the currently booted simulator when available.

For docs, process, or harness changes, also use:
`python3 scripts/agent_harness_check.py`

## PR Rules
- Stage only files relevant to the task.
- Do not include personal Xcode state.
- Mention manual device verification when changes affect Sonos hardware behavior, widgets, Lock Screen, Control Center, or now-playing state.
