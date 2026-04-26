# Sonoic Development Roadmap

This document is the public roadmap for the project.

It describes what is already real in the app, the architectural guardrails we want to preserve, and the next slices that are worth building.

## Current State

Sonoic already has a real app shell and a full first-pass local Sonos control path.

Implemented so far:

- feature-shaped iPhone app shell with `Home`, `Rooms`, `Queue`, and `Settings`
- one shared app model, `SonoicModel`
- typed Sonos domain models for active target, room list, queue, and now playing
- favorites-first `Home` surface with real Sonos favorites, collections, recently played items, source summaries, and now-playing context
- real mini-player and draggable player sheet
- real local Sonos `play/pause`, `next`, `previous`, `mute`, volume, and seek
- real now-playing title, artist, album, source, artwork, duration, and progress reads
- Advanced now-playing inspection for raw Sonos metadata, transport URI, duration, and elapsed-time behavior
- manual playback transition smoothing so local progress does not run ahead before Sonos confirms `PLAYING`
- discovery-backed Sonos room selection through Bonjour and household topology
- real group awareness for current Sonos groups and group coordinator selection
- real room naming and bonded home theater member details
- Sonos queue inspection with current-item highlighting, tap-to-play, clear, remove, and reorder
- shared external-control snapshot for widgets
- App Group-backed artwork cache and shared state store
- manual host fallback through `Settings`
- `Rooms` surface for the selected room or group, discovered groups, discovered room list, bonded setup, discovery refresh state, and home theater entry point
- `Settings` focused on quiet everyday configuration, with manual setup and diagnostics behind Advanced
- lightweight foreground polling for playback, metadata, volume, and mute
- stale-state handling for outside-app state
- native Apple now-playing integration for playback commands, artwork, progress, and lock-screen scrubbing when duration is available
- home theater controls for EQ, sub level, speech enhancement, and night sound; TV audio details stay behind Advanced until they become useful controls
- Swift Testing target for focused Sonos parser coverage
- Apple Music source surface with quiet authorization state, catalog search, saved playlists/artists/albums/songs, recently added library items, search/library item detail pages, and structured Browse destinations
- explicit playback capability states so service metadata does not pretend to be Sonos-playable until Sonoic has a Sonos-native payload

## Architecture Guardrails

The project should stay close to Apple’s current SwiftUI sample style: direct, readable, and light on abstraction.

Principles:

- keep one clear top-level app model until the code proves otherwise
- organize by feature and screen instead of by abstract layers
- keep helper views and helpers small and justified
- prefer concrete types over broad protocol scaffolding
- add new folders only when a feature becomes real
- avoid “foundation” rewrites that are not tied to user-visible progress
- keep the main UI quiet: short labels, obvious actions, and no diagnostic explanations outside Advanced

In practice:

- `SonoicApp/App` holds app entry and scene wiring
- `SonoicApp/Model` holds app state and app-only types
- `SonoicApp/Views/<Feature>` holds one feature area at a time
- `SonoicShared` holds only code genuinely shared by the app and widget extension

## Current Folder Layout

```text
SonoicShared/
  Model/
  Sonos/
  Storage/

SonoicApp/
  App/
  Model/
  Views/
    Home/
    Player/
    Queue/
    Root/
    Rooms/
    Settings/
    Shared/
```

## Near-Term Priorities

### 1. Harden the current Sonos path on real hardware

The project now has enough real behavior that the highest-value work is making it boring on actual Sonos households.

The next work here should be careful:

- verify discovery against multiple households and room names
- verify queue editing during transitions and grouped playback
- verify lock-screen scrubbing and progress across services
- verify home theater controls across products with and without Sub, surrounds, speech enhancement, and night sound
- keep diagnostics behind Advanced so the main UI stays quiet

### 2. Expand music sources from Home

Home now has enough gravity to become the center of Sonoic.

Apple Music V1 is now a real service surface. It can search Apple Music, browse saved library lanes, open item details, and show recently added library content. Search should feel like one search with grouped results, not a mode picker. Playback still stays honest: only Sonos-native favorites can start playback today.

The next meaningful work here is:

- wire real Apple Music Browse lanes for recommendations, categories, curated playlists, new releases, and radio metadata
- research and implement Sonos-native service payload generation for Apple Music items
- decide whether Apple Music library playlists/albums can be mapped safely into Sonos queue/session starts
- keep Spotify as a separate integration path because Spotify iOS SDK/App Remote is app-owned control, not Sonos-native playback
- add queue-derived actions from recent plays, favorites, and service metadata once payload ownership is clear
- keep playback affordances visible only when each item has a trustworthy playback path

### 3. Make Queue a creation surface

Queue is now a real control surface. The next step is letting it create useful playback states, not only edit the current one.

The next meaningful work here is:

- add next / play next flows from favorites and Home
- save or reuse useful queue states
- improve empty-queue recovery
- expose queue actions cleanly without duplicating the player surface

### 4. Deepen outside-app controls

Sonoic can publish native now-playing state, but it is still a remote-control app rather than the audio output owner.

The useful path is:

- keep Lock Screen and Control Center controls reliable
- add App Intents for common actions
- consider Control Center controls and widgets for rooms, volume, and favorites
- preserve clear stale-state behavior whenever Sonos cannot be confirmed

### 5. Polish the home theater path

The first home theater path is real. It should now get product polish and more device verification.

Next slices:

- better capability descriptions for unsupported controls
- move TV audio inspection into Advanced if more HTControl state proves available
- product-specific tuning for Arc, Beam, Ray, Amp, Sub, and surround setups
- fast room switching without stale theater state

## Open Questions

These are real project decisions, but they do not all need to be answered right away.

- How far should the project go with background refresh before the complexity stops being worth it?
- How much of the Apple native now-playing experience can be supported reliably for a remote-control app?
- How far should Sonoic go into service-native browsing before it starts duplicating the Sonos app?
- Which Apple Music API lanes are worth making first: recently added, charts, editorial playlists, recommendations, or category browsing?
- What is the smallest reliable Sonos-native payload path for an Apple Music catalog/library item?
- Which home theater details are useful enough for quiet UI, and which diagnostics should stay Advanced-only?

## Working Style

The healthiest progress pattern for this project is still:

- one small vertical slice at a time
- build the real thing, not a generic future abstraction
- keep file sizes under control
- split files when they stop feeling like one coherent unit
- review often enough that the codebase stays understandable
