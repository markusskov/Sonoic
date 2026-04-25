# Sonoic

Sonoic is an iPhone-first Sonos controller focused on fast everyday control, especially for the current active room or group.

The app is being built as a local-first Sonos hub rather than a generic music client. The near-term goal is simple: make playback and sound control faster, clearer, and more dependable than the current default experience.

## Status

Sonoic is still an early work-in-progress, but the core Sonos control experience is now real across playback, rooms, queue, Home, and home theater controls.

What works today:

- iPhone app shell with `Home`, `Rooms`, `Queue`, and `Settings`
- `Home` showing real Sonos favorites, collections, recently played items, now-playing context, and a sources row
- real bottom mini-player and expandable player sheet
- local network discovery for nearby Sonos players
- room and group selection from discovered household topology
- real room naming and bonded home theater member details for the selected player
- `Rooms` tab showing the current room or group, discovered groups, room list, discovery state, and home theater entry point
- `Queue` tab showing the active Sonos queue with current-item highlighting, tap-to-play, clear, remove, and reorder
- `Settings` focused on diagnostics and manual connection fallback
- real local `play/pause`, `next`, `previous`, `mute`, seek, and volume commands
- real now-playing metadata, artwork, source attribution, and progress reads
- manual playback transition smoothing so Sonoic waits for Sonos confirmation before advancing app-owned progress
- shared parser/transport test target for core Sonos parsing behavior
- widget backed by shared app state
- native Apple now-playing integration with play/pause, next/previous, artwork, progress, and lock-screen scrubbing when Sonos exposes duration
- home theater controls for EQ, sub level, speech enhancement, night sound, and TV audio diagnostics
- Apple Music source surface with authorization status, catalog search, saved library lanes, recently added items, and item detail pages
- explicit service playback capability labels so metadata-only Apple Music items are not presented as Sonos-playable

What is still in progress:

- stable Lock Screen / Control Center ownership through Apple’s native now-playing surfaces
- Sonos-native playback payloads for Apple Music catalog and library items
- deeper music-service integrations for Spotify, playlists, and source destinations
- queue-derived flows from `Home`
- broader home theater validation across more Sonos products
- App Intents, shortcuts, and richer outside-app entry points

## Product Direction

Sonoic is intentionally narrow.

- It is local-first.
- It targets Sonos households, not arbitrary speakers.
- It starts with one real household and expands only when a feature proves its value.
- It prioritizes fast control of the active room over broad browsing features.

The current MVP direction is outside-app control for the active target:

- Lock Screen and Control Center playback controls
- reliable `play/pause`, `next`, `previous`, and scrubbing
- fast volume and mute access
- clear stale or unavailable state when Sonoic cannot confirm fresh data

## Architecture

The codebase follows the spirit of Apple’s modern SwiftUI sample apps: direct, feature-shaped, and intentionally light on abstraction.

Principles:

- keep one clear top-level app model until the code proves otherwise
- use typed environment injection instead of generic service containers
- organize by feature and screen, not by abstract layers
- keep helper views and helpers narrow
- prefer modern SwiftUI APIs only when they improve clarity
- avoid protocol-heavy or manager-heavy scaffolding before it is needed

Top-level structure:

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

## Running The App

Requirements:

- latest Xcode with Swift 6.3 support
- an iPhone or simulator build environment
- a Sonos player reachable on the same local network for the real control path

Before running on your own Apple developer account:

1. Open `Sonoic.xcodeproj` in Xcode.
2. Update signing for the app and widget targets.
3. Replace the current bundle identifiers and App Group identifier with your own namespace.
4. If you change the App Group or bundle namespace, update the matching identifiers in:
   - `SonoicApp/Sonoic.entitlements`
   - `SonoicWidgetsExtension.entitlements`
   - `SonoicShared/Storage/SonoicSharedStore.swift`
   - `SonoicApp/App/SonoicBackgroundRefresh.swift`
   - `SonoicApp/Info.plist`
5. Run the app on a device connected to the same local network as your Sonos household.
6. Open `Rooms`, allow local-network access, and choose a discovered player or group.

Notes:

- Sonoic uses Bonjour discovery first and keeps manual host entry as a fallback in `Settings`.
- `Home` is now a music hub for favorites, collections, recent plays, sources, and the current session. Apple Music can show authorized metadata, library lanes, search results, item details, and recently added items, while playback stays Sonos-native.
- `Rooms` can show discovered rooms, current groups, selected target state, bonded home theater setup, and home theater controls.
- `Queue` can inspect, jump, clear, remove, and reorder the active Sonos queue. Adding new queue items from arbitrary services is still future work.
- `Settings` is now mostly diagnostics and fallback connection details.
- The app requests local-network access because Sonos control currently happens over the LAN.
- The app requests Apple Music access only for Apple Music metadata surfaces. Sonoic does not use MusicKit app-owned playback as the main path because Sonos should remain the audio owner.
- Some now-playing behavior on the Lock Screen is still experimental and under active refinement.

## Development Roadmap

The public development roadmap lives in [plan.md](plan.md).

The short version:

1. finish the native now-playing path cleanly
2. validate discovery, queue, Home, and home theater controls on more real Sonos households
3. expand Apple Music metadata into Sonos-native playback payload research and playlist/source flows
4. add App Intents, shortcuts, and deeper outside-app entry points

## Open Source Notes

Sonoic is being prepared for open-source development, but the repository is still settling into its public shape.

That currently means:

- the code is real and buildable
- the docs now describe the project for contributors rather than for internal handoff
- the repo is being cleaned up to avoid tracking personal Xcode state
- a public license has not been chosen yet

## Contributing

Contributions are welcome once the repo settles into a stable public baseline.

For now:

- start with [CONTRIBUTING.md](CONTRIBUTING.md)
- keep pull requests focused and incremental
- prefer real vertical slices over broad “foundation” rewrites
- preserve the simple feature-first structure unless there is a clear reason to change it

## Disclaimer

Sonoic is an independent project and is not affiliated with or endorsed by Sonos, Apple, Spotify, or Apple Music.
