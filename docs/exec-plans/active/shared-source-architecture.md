# Execution Plan: Shared Source Architecture

## Goal

Make Apple Music the first adapter in a shared source system so future Spotify, Tidal, Sonos Radio, SoundCloud, and other services can reuse the same search state, item rows, and artist/album/playlist detail screens.

## Scope

- In scope: source-neutral item references, shared search session state, a concrete source adapter registry, generic artist/album/playlist detail routing, and source/kind filters in Search.
- Out of scope: Spotify/Tidal/SoundCloud API auth, non-Apple catalog search, and changing Sonos playback ownership.

## Acceptance Criteria

- Apple Music search still returns live results and preserves the query when changing source/kind filters.
- Songs do not open detail screens; playable song rows start Sonos-owned playback and metadata-only rows stay honest.
- Search, Home, Favorites, Recently Played, source pages, row menus, and player artist taps route artist/album/playlist items through the same shared detail view.
- Future source adapters can add search/detail/favorite/playback behavior without duplicating source detail screens.

## Context

- [README.md](../../../README.md)
- [plan.md](../../../plan.md)
- [ARCHITECTURE.md](../../../ARCHITECTURE.md)
- [docs/agent-harness.md](../../agent-harness.md)

## Plan

- [x] Rename Apple-only source identity/detail types to source-neutral names.
- [x] Add source ids to item references so cache keys cannot collide across providers.
- [x] Add a concrete source adapter registry with Apple Music as the first live adapter.
- [x] Add shared search session state for query, source filter, and kind filter.
- [x] Convert Search to use source chips plus kind chips after submit.
- [x] Convert source rows and detail actions to call shared source adapter methods.
- [x] Remove song detail routing from shared rows.
- [x] Build and harness validation.

## Validation

- [x] `python3 scripts/agent_harness_check.py`
- [x] `xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- [ ] Device: Apple Music search works.
- [ ] Device: source/kind filters do not clear the submitted query.
- [ ] Device: long playlists/albums still scroll without the old glass rendering issue.

## Decision Log

- 2026-05-03: Keep `SonoicModel` as the top-level app model and add concrete adapters behind it instead of introducing protocol-heavy provider layers.
- 2026-05-03: Keep Apple Music library/browse implementation names for now, but make shared search/detail routing source-neutral.

## Progress

- 2026-05-03: Shared adapter, search session, generic source detail routing, docs, harness, and build validation completed on `sonoic/shared-source-architecture`.
