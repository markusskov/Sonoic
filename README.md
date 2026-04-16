# Sonoic

Sonoic is an iPhone-first Sonos controller focused on fast everyday control, especially for the current active room or group.

The app is being built as a local-first Sonos hub rather than a generic music client. The near-term goal is simple: make playback and sound control faster, clearer, and more dependable than the current default experience.

## Status

Sonoic is still an early work-in-progress, but the core app shell and first real Sonos control path are already in place.

What works today:

- iPhone app shell with `Home`, `Rooms`, `Queue`, and `Settings`
- real bottom mini-player and expandable player sheet
- manual Sonos host configuration for one local player
- real room naming and bonded home theater member details for the configured manual player
- `Rooms` tab showing the resolved current room, bonded setup, and lightweight refresh state
- `Settings` focused on manual player configuration and diagnostics
- real local `play/pause`, `next`, `previous`, `mute`, and seek commands
- real now-playing metadata, artwork, source attribution, and progress reads
- widget backed by shared app state
- first native Apple now-playing integration experiments

What is still in progress:

- stable Lock Screen / Control Center ownership through Apple’s native now-playing surfaces
- real target and room discovery
- queue, grouping, favorites, and playlist flows
- home theater controls and diagnostics

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
5. Run the app and enter a Sonos player host or IP in `Settings`.

Notes:

- The current real Sonos path is manual-host based. Discovery is not implemented yet.
- The configured manual player can already resolve its real room name and bonded home theater setup in `Rooms`, but it does not yet expose household-wide discovery or grouping.
- `Settings` is currently the manual connection and diagnostics surface rather than the place to browse rooms.
- The app requests local-network access because Sonos control currently happens over the LAN.
- Some now-playing behavior on the Lock Screen is still experimental and under active refinement.

## Development Roadmap

The public development roadmap lives in [plan.md](plan.md).

The short version:

1. finish the native now-playing path cleanly
2. make room and target handling real instead of sample-backed
3. add queue, grouping, and favorites
4. expand into home theater controls and diagnostics

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
