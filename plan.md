# Sonoic Development Roadmap

This document is the public roadmap for the project.

It describes what is already real in the app, the architectural guardrails we want to preserve, and the next slices that are worth building.

## Current State

Sonoic already has a real app shell and a first-pass Sonos control path. The current architectural migration is to make Sonos Cloud the normal control plane while keeping LAN/SOAP as an explicit local-tools layer.

Implemented so far:

- feature-shaped iPhone app shell with `Home`, `Rooms`, `Queue`, and `Settings`
- one shared app model, `SonoicModel`
- typed Sonos domain models for active target, room list, queue, and now playing
- favorites-first `Home` surface with real Sonos favorites, collections, recently played items, source summaries, and now-playing context
- real mini-player and draggable player sheet
- real Sonos playback controls, with the active migration moving normal transport, seek, volume, and mute to Cloud-owned commands
- real now-playing title, artist, album, source, artwork, duration, and progress reads
- Advanced now-playing inspection for raw Sonos metadata, transport URI, duration, and elapsed-time behavior
- playback transition smoothing so local progress does not run ahead before Sonos confirms `PLAYING`
- discovery-backed Sonos room selection through Bonjour and household topology
- real group awareness for current Sonos groups and group coordinator selection
- real room naming and bonded home theater member details
- Sonos queue inspection with current-item highlighting, tap-to-play, clear, remove, and reorder
- shared external-control snapshot for widgets
- App Group-backed artwork cache and shared state store
- Sonos Cloud account connection through onboarding/Settings, plus manual host/local tools behind Advanced
- `Rooms` surface for the selected room or group, discovered groups, discovered room list, bonded setup, discovery refresh state, and home theater entry point
- `Settings` focused on quiet everyday configuration, with manual setup and diagnostics behind Advanced
- lightweight foreground polling for playback, metadata, volume, and mute
- stale-state handling for outside-app state
- native Apple now-playing integration for playback commands, artwork, progress, and lock-screen scrubbing when duration is available
- home theater controls for EQ, sub level, speech enhancement, and night sound; TV audio details stay behind Advanced until they become useful controls
- Swift Testing target for focused Sonos parser coverage
- shared source surface with Apple Music as the first live adapter, quiet authorization state, multi-source search state, saved playlists/artists/albums/songs, recently added library items, shared artist/album/playlist detail pages, and structured Browse destinations
- explicit playback capability states so service metadata does not pretend to be Sonos-playable until a source adapter can provide a Sonos-native payload
- RevenueCat-backed Sonoic Plus foundation for future support and personalization features; core Sonos control remains free

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
- keep Cloud as the main control plane; LAN should not become an invisible fallback for normal playback commands

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

### 1. Finish the Cloud control spine

The project now has enough real behavior that the highest-value work is making the control plane boring on actual Sonos households.

The next work here should be careful:

- make Cloud household/group/player identity the first-class target model
- route normal play, pause, next, previous, seek, favorite, playlist, volume, and mute through Cloud when supported
- remove hidden LAN fallback from normal playback paths
- move manual host and SOAP controls into explicit local tools
- verify discovery against multiple households and room names
- verify queue editing during transitions and grouped playback while it remains an explicit local queue tool
- verify lock-screen scrubbing and progress across services
- verify home theater controls across products with and without Sub, surrounds, speech enhancement, and night sound
- keep diagnostics behind Advanced so the main UI stays quiet

### 2. Expand music sources from Home

Home now has enough gravity to become the center of Sonoic.

Apple Music V1 is now the first live adapter in a shared source surface. It can search Apple Music, browse saved library lanes, open shared artist/album/playlist details, show recently added library content, and start playback only when Sonoic has a proven Sonos-owned payload. Search is one query with source and kind filters instead of separate service screens.

The next meaningful work here is:

- wire real Apple Music Browse lanes for recommendations, categories, curated playlists, new releases, and radio metadata
- harden Sonos-owned Apple Music payload generation for catalog and library items
- decide which Apple Music playlist, album, and song starts can preserve queue/session context safely
- add future Spotify, Tidal, Sonos Radio, SoundCloud, and other adapters through the shared source registry without new detail screens
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

### 6. Add tasteful Sonoic Plus personalization

Sonoic Plus should feel like support and personalization, not withheld control.

The foundation is in place through RevenueCat, but Plus features should land only when they make the app feel more personal:

- alternate app icons
- theme and accent choices
- custom Home ordering
- extra widget styles
- saved room presets for volume, EQ, speech enhancement, and night sound

Core playback, queue editing, discovery, source browsing, Lock Screen, Control Center, and the default Home quality stay free.

## Open Questions

These are real project decisions, but they do not all need to be answered right away.

- How far should the project go with background refresh before the complexity stops being worth it?
- How much of the Apple native now-playing experience can be supported reliably for a remote-control app?
- Which Control API metadata/events are reliable enough to replace local now-playing polling completely?
- Which home-theater controls are covered by Cloud today, and which should remain local tools?
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
