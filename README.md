# Sonoic

Sonoic is an iPhone-first Sonos controller focused on fast everyday control, especially for the current active room or group.

The app is being built as a Sonos Cloud controller with a narrow local-tools layer rather than a generic music client. The near-term goal is simple: make playback and sound control faster, clearer, and more dependable than the current default experience.

## Status

Sonoic is still an early work-in-progress, but the core Sonos control experience is now real across playback, rooms, queue, Home, and home theater controls.

What works today:

- iPhone app shell with `Home`, `Rooms`, `Queue`, and `Settings`
- `Home` showing real Sonos favorites, collections, recently played items, now-playing context, and a sources row
- real bottom mini-player and expandable player sheet
- Sonos account connection and Cloud household/group/player reads
- local network discovery for nearby Sonos players and local tools
- room and group selection from discovered household topology
- real room naming and bonded home theater member details for the selected player
- `Rooms` tab showing the current room or group, discovered groups, room list, discovery state, and home theater entry point
- `Queue` tab showing the active Sonos queue with current-item highlighting, tap-to-play, clear, remove, and reorder
- `Settings` with quiet everyday configuration, Sonos Cloud status, local tools, and Advanced diagnostics
- real Cloud-backed `play/pause`, `next`, `previous`, seek, volume, mute, and matched favorite/playlist starts, with local control kept for tools that need same-network access and generated source queues kept local until a Cloud Queue API exists
- real now-playing metadata, artwork, source attribution, and progress reads
- manual playback transition smoothing so Sonoic waits for Sonos confirmation before advancing app-owned progress
- shared parser/transport test target for core Sonos parsing behavior
- widget backed by shared app state
- native Apple now-playing integration with play/pause, next/previous, artwork, progress, and lock-screen scrubbing when Sonos exposes duration
- home theater controls for EQ, sub level, speech enhancement, and night sound
- shared source browsing surface with Apple Music as the first live adapter, multi-source search state, saved library lanes, recently added items, grouped search results, and shared artist/album/playlist detail pages
- explicit service playback capability labels so metadata-only service items are not presented as Sonos-playable
- RevenueCat-backed Sonoic Plus foundation for future support and personalization features

What is still in progress:

- actual Sonoic Plus personalization features such as themes, alternate icons, Home ordering, widgets, and room presets
- stable Lock Screen / Control Center ownership through Apple’s native now-playing surfaces
- Sonos-native playback payloads for more Apple Music catalog and library items
- live adapters for Spotify, Tidal, Sonos Radio, SoundCloud, and other source destinations
- queue-derived flows from `Home`
- broader home theater validation across more Sonos products
- App Intents, shortcuts, and richer outside-app entry points

## Product Direction

Sonoic is intentionally narrow.

- Cloud is the main control plane.
- Local network access is a local-tools layer, not a hidden normal playback fallback.
- It targets Sonos households, not arbitrary speakers.
- It starts with one real household and expands only when a feature proves its value.
- It prioritizes fast control of the active room over broad browsing features.

The current MVP direction is outside-app control for the active target:

- Lock Screen and Control Center playback controls
- reliable `play/pause`, `next`, `previous`, and scrubbing
- fast volume and mute access
- clear stale or unavailable state when Sonoic cannot confirm fresh data

The control-plane rule is intentionally strict: normal playback should either use the Sonos Control API or show that Cloud control is unavailable. LAN/SOAP remains valuable for same-network setup, home-theater tuning, diagnostics, and explicit local/manual tools, but it should not silently take over first-class playback paths.

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
- a Sonos account for the normal Cloud control path
- a Sonos player reachable on the same local network for discovery and local tools

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
5. Configure the Sonos OAuth values described in `docs/sonos-oauth-dev-setup.md` if you are testing Cloud control.
6. Run the app on a device connected to the same local network as your Sonos household.
7. Connect your Sonos account during onboarding or from `Settings`.
8. Open `Rooms`, allow local-network access, and choose a discovered player or group when testing local discovery or local tools.

Notes:

- Sonoic uses Sonos Cloud account state for normal control identity and keeps Bonjour/manual host access for discovery, local tools, and diagnostics.
- `Home` is now a music hub for favorites, collections, recent plays, sources, and the current session. Source browsing uses shared artist/album/playlist routes, with Apple Music as the first live catalog adapter while playback stays Sonos-owned.
- `Rooms` can show discovered rooms, current groups, selected target state, bonded home theater setup, and home theater controls.
- `Queue` can inspect, jump, clear, remove, and reorder the active Sonos queue through the local queue tool path. Adding new queue items from arbitrary services is still future work.
- `Settings` keeps everyday configuration quiet, with Sonos Cloud status, local tools, and diagnostics available from Advanced.
- The app requests local-network access for discovery, local tuning, and diagnostics. Normal playback control should use the Sonos Control API when connected.
- The app requests Apple Music access for metadata and service browsing. Sonoic does not use MusicKit app-owned playback as the main path because Sonos should remain the audio owner.
- Sonoic Plus uses RevenueCat. To preview the paywall path, add a `RevenueCatAPIKey` bundle value and keep the Plus entitlement identifier as `plus`, or override it with `SonoicPlusEntitlementIdentifier`.
- Lock Screen and Control Center support depend on what Sonos exposes for the current source, especially duration, progress, and queue ownership.

## Development Roadmap

The public development roadmap lives in [plan.md](plan.md).

Agent-facing project context starts in [AGENTS.md](AGENTS.md). The harness setup and docs map live in [docs/agent-harness.md](docs/agent-harness.md).

The short version:

1. finish the Cloud control spine cleanly
2. validate discovery, queue, Home, and home theater/local tools on more real Sonos households
3. expand shared source browsing into Sonos-native playback payload research and additional service adapters
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
