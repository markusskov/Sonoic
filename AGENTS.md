# Sonoic Agent Guide

## Project Shape
Sonoic is an iPhone-first Sonos controller. Keep changes small, user-facing, and feature-shaped.

## Architecture
- Preserve the single top-level `SonoicModel` until code proves it needs splitting.
- Organize by feature and screen, not abstract layers.
- Prefer concrete Swift types over protocol-heavy scaffolding.
- Avoid broad “foundation” rewrites without a concrete product slice.

## Build
Use:
`xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

For simulator checks, use the currently booted simulator when available.

## PR Rules
- Stage only files relevant to the task.
- Do not include personal Xcode state.
- Mention manual device verification when changes affect Sonos LAN behavior, widgets, Lock Screen, Control Center, or now-playing state.
