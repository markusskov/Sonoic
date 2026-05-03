# Execution Plan: Refactor Modernization

## Goal

Tighten the current shared-source codebase so future contributors can add services and UI without duplicating Apple Music paths, stale view variants, or diagnostic-only logic.

## Scope

- In scope: dead-code deletion, source naming cleanup, small helper extraction, duplicated state/UI consolidation, and parity checks.
- Out of scope: Spotify/Tidal/SoundCloud implementation, Sonos cloud OAuth, strict concurrency migration, dependency upgrades, and splitting the top-level `SonoicModel`.

## Behavior Guardrails

- Preserve existing Sonos playback behavior.
- Preserve Apple Music catalog search, library, browse, favorites, playlist playback, and source detail routing.
- Keep song rows as direct playback actions; do not reintroduce song detail screens.
- Keep diagnostics behind Advanced.
- Keep long playlist and album track lists unwrapped by glass containers.

## Passes

- [x] Inventory dead code, stale abstractions, oversized modules, and duplicated paths.
- [x] Delete confirmed dead code with compiler or test proof.
- [x] Rename source-generic UI/state that still has stale Apple Music names.
- [x] Consolidate repeated load-state and Apple Music request scaffolding where behavior stays identical.
- [x] Consolidate repeated source message/card/row components using the search result list style.
- [x] Centralize source item routing and source action capability decisions.
- [ ] Run full validation and record remaining migration tasks.

## Validation

- [x] `python3 scripts/agent_harness_check.py`
- [x] `xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- [x] Simulator/unit tests for touched parser, source, search, and payload modules.
- [ ] Device: Apple Music search, source filters, kind filters, and detail routes still work.
- [ ] Device: Home favorites, recently played, playlist playback, Queue, Player, Lock Screen, and Sonos favorites still match current behavior.

## Current Findings

- `AppleMusicSearchResultBalancer.balancedItems` is not used by production code; production uses `groupedItems`.
- Source detail and source reference files are mostly rename replacements, not true line growth.
- Source adapter/search state is real new architecture for future services and should be trimmed carefully rather than collapsed prematurely.
- Apple Music API/client types should stay Apple-named; source-generic views and rows should move away from Apple-specific names.
- Source loading state now uses one `SonoicLoadStatus`; the feature state structs stayed intact so view behavior and call sites remain stable.
- Source playback, playlist queue starts, playlist fallback starts, and source favorite capability checks now go through narrow `SonoicModel` source-action helpers; views still own presentation and alerts.
- Source row/detail action alerts now share one lightweight `SourceActionFailure` value.
- Generic source rows now reuse the same source metadata row content and options icon as the search/source navigation rows, reducing hand-built artwork/title/subtitle variants.
- Home favorites, recently played, and Apple Music recently-added tiles now share one artwork caption tile so carousel cards keep the same image/text/badge rules.

## Separate Migration Tasks

- Swift strict concurrency hardening.
- New source API integrations and auth flows.
- Sonos cloud control API or OAuth.
- Broad Liquid Glass redesign.
- Splitting `SonoicModel` into separate top-level models.
