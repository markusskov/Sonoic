# Sonoic Development Roadmap

This document is the public roadmap for the project.

It describes what is already real in the app, the architectural guardrails we want to preserve, and the next slices that are worth building.

## Current State

Sonoic already has a real app shell and a first real local Sonos control path.

Implemented so far:

- feature-shaped iPhone app shell with `Home`, `Rooms`, `Queue`, and `Settings`
- one shared app model, `SonoicModel`
- typed Sonos domain models for active target, connection state, and now playing
- real mini-player and draggable player sheet
- real local Sonos `play/pause`, `next`, `previous`, `mute`, and seek
- real now-playing title, artist, album, source, artwork, duration, and progress reads
- manual-host based real room naming and bonded home theater member details
- shared external-control snapshot for widgets
- App Group-backed artwork cache and shared state store
- manual-host based local Sonos configuration through `Settings`
- `Rooms` surface for the resolved active room, bonded setup, and manual refresh state
- `Settings` focused on manual player setup and diagnostics
- lightweight foreground polling for playback, metadata, volume, and mute
- stale-state handling for outside-app state
- first native Apple now-playing integration work

## Architecture Guardrails

The project should stay close to Apple’s current SwiftUI sample style: direct, readable, and light on abstraction.

Principles:

- keep one clear top-level app model until the code proves otherwise
- organize by feature and screen instead of by abstract layers
- keep helper views and helpers small and justified
- prefer concrete types over broad protocol scaffolding
- add new folders only when a feature becomes real
- avoid “foundation” rewrites that are not tied to user-visible progress

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

### 1. Finish the native now-playing path cleanly

The project now has a real player surface in the app and a working experimental path into Apple’s native now-playing UI.

The next work here should be careful:

- keep the lock-screen path stable
- tighten timing and metadata behavior without overfitting hacks
- keep app-owned playback state understandable
- remove any temporary scaffolding once the flow is stable

### 2. Make targets and rooms real

The app can already control one manually configured local Sonos player.

The next meaningful expansion is:

- discovery-backed target lists instead of manual-host placeholders
- real room or group identity beyond the configured manual player
- eventually discovery, once the added complexity is justified

### 3. Build the actual Sonos control flows

Once target handling is more real, the next big product slices are:

- queue
- groups
- favorites
- playlists

These should stay narrow and useful rather than trying to mirror the entire Sonos app at once.

### 4. Extend the home theater path

Sonoic is also meant to become a practical controller for a Sonos home theater setup.

Later slices should cover:

- EQ
- sub level
- speech enhancement
- night sound
- TV audio diagnostics

## Open Questions

These are real project decisions, but they do not all need to be answered right away.

- How far should the project go with background refresh before the complexity stops being worth it?
- When is multicast discovery worth the added entitlement and networking complexity?
- How much of the Apple native now-playing experience can be supported reliably for a remote-control app?
- How far should the `Rooms` tab go before full discovery and grouping make sense?

## Working Style

The healthiest progress pattern for this project is still:

- one small vertical slice at a time
- build the real thing, not a generic future abstraction
- keep file sizes under control
- split files when they stop feeling like one coherent unit
- review often enough that the codebase stays understandable
