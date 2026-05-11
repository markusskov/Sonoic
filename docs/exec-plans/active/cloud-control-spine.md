# Execution Plan: Cloud Control Spine

## Goal

Make Sonoic a Sonos Cloud controller for normal playback and room control, with LAN kept as an explicit local tools layer for tuning, diagnostics, and capabilities the cloud API does not expose well enough yet.

## Scope

In scope:

- Document the product decision: Cloud is the main control plane; LAN is a narrow local tools island.
- Move normal transport naming and call sites away from manual-host semantics.
- Stop hidden LAN fallback from normal Cloud-owned playback, seek, and favorite paths.
- Make unavailable Cloud state visible instead of silently switching transports.
- Keep local SOAP for home-theater tuning, EQ-like controls, bonded accessory inspection, TV diagnostics, local topology troubleshooting, and explicitly labeled local/manual tools.
- Preserve current behavior where possible until a command path is intentionally switched.

Out of scope for this plan:

- Replacing every LAN-only tuning feature with Cloud until the official API coverage is verified.
- Replacing generated source playlist queues before Sonoic has a hosted Cloud Queue API.
- Building a production event backend.
- Shipping broad UI redesign work unrelated to the control-plane split.
- Removing Bonjour discovery if it remains useful for first-run local speaker discovery or local tools.

## Acceptance Criteria

- Normal playback controls think in Cloud household/group/player identity rather than manual host identity.
- Normal play, pause, next, previous, seek, and favorite paths either use Cloud or report Cloud unavailable.
- LAN fallback is not silent in normal playback flows.
- Manual host/local SOAP behavior is reachable only through an explicit local tools boundary.
- Generated source playlist queues, queue inspection/editing, and now-playing refresh are explicitly tracked as remaining migration islands until their Cloud replacements land.
- Main player volume and mute route through Cloud when the selected target has a matching Cloud group/player identity.
- Home theater/EQ/Sub/dialog/night-sound and TV diagnostics still work when same-network LAN access is available.
- Existing Apple Music search/detail/favorite playback surfaces keep their user-facing behavior unless explicitly changed by this plan.
- Lock Screen and Control Center state do not regress from the current baseline.

## Context

- [README.md](../../../README.md)
- [plan.md](../../../plan.md)
- [ARCHITECTURE.md](../../../ARCHITECTURE.md)
- [docs/RELIABILITY.md](../../RELIABILITY.md)
- [Sonos Control API Foundation](sonos-control-api-foundation.md)
- [Sonos Control API OAuth Foundation](sonos-control-api-oauth-foundation.md)
- [Agent harness workflow](../../agent-harness.md)

## Plan

- [x] Update product and architecture docs to describe Cloud as the main control plane and LAN as local tools.
- [x] Rename normal transport/model entry points away from manual-host semantics while keeping public behavior stable.
- [x] Create a small Cloud command surface for normal playback controls and route player/Home/Lock Screen calls through it.
- [x] Remove hidden LAN fallback from Cloud-owned playback commands; return an explicit unavailable/failure state instead.
- [ ] Move manual-host SOAP controls into a Local Tools namespace/surface.
- [x] Convert main player volume/mute to Cloud where supported, keeping LAN volume only in Local Tools until proven otherwise.
- [ ] Convert now-playing refresh toward Cloud playback status/metadata, keeping LAN diagnostics as a secondary view.
- [ ] Keep queue editing LAN-only until a Cloud queue model is available; label or gate it honestly.
- [ ] Add focused tests for command routing, fallback gating, and expired-token behavior.
- [ ] Run full build and harness validation before each PR.

## Validation

- [x] `python3 scripts/agent_harness_check.py`
- [x] `xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- [ ] Device: Sonos account remains connected after app restart.
- [ ] Device: Cloud household/group/player snapshot loads.
- [ ] Device: play/pause/next/previous use Cloud when connected.
- [ ] Device: seek uses Cloud and does not silently fall back to LAN.
- [ ] Device: favorites and playlist playback still start the intended item.
- [ ] Device: main player volume/mute uses Cloud and reports unavailable instead of silently falling back.
- [ ] Device: Lock Screen and Control Center still show correct metadata and controls.
- [ ] Device: local home-theater controls still work on same network.
- [ ] Device: queue jump/edit/clear/reorder still works only as an explicitly local queue tool.
- [ ] Device: generated source playlist queues are visibly tracked as a local migration island and do not pretend to be Cloud Queue API playback.
- [ ] Device: if Cloud is unavailable, normal playback controls surface unavailable state instead of silently falling back to LAN.

## Decision Log

- 2026-05-11: Product stance set to "Sonoic is a Sonos Cloud controller. Advanced local tuning requires same-network access." LAN remains for local-only tuning, diagnostics, and explicit local/manual tools, not as an invisible normal playback fallback.
- 2026-05-11: First behavior pass routes normal transport, seek, favorite, volume, and mute entry points through Cloud-only wrappers. Manual transport methods are now local-only again. Generated source playlist queues remain local until the worker hosts a real Sonos Cloud Queue API.

## Progress

- 2026-05-11: Subagent inventory confirmed normal playback is still named and gated around manual host, with Cloud-first wrappers that silently fall back to LAN. LAN-only areas are home-theater tuning, EQ/Sub/dialog/night sound, bonded accessory topology, TV diagnostics, queue inspection/editing, and current now-playing refresh.
- 2026-05-11: Subagent sample-app research confirmed the official sample exposes Control API session endpoints but does not implement the required Cloud Queue API server (`context`, `itemWindow`, `version`). Sonoic must add that worker surface before replacing generated LAN playlist queues.
- 2026-05-11: Build validation passed after strict active-target matching and Cloud volume/mute routing. Queue jump, queue mutation, source generated queues, and local metadata refresh remain explicitly local until separate Cloud replacements exist.
