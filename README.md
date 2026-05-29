# Sonoic

Sonoic is an iPhone-first Sonos controller focused on fast, honest control of the active room or group.

The app is cloud-first for everyday Sonos control. The Sonos Control API owns normal playback, seek, now-playing refresh, volume, mute, and cloud queue playback. LAN control is kept as a small, explicit island for discovery, manual local mode, diagnostics, and tuning surfaces that the cloud path does not cover well enough yet.

## Status

Sonoic is an early work-in-progress, but the core controller shape is real.

What works today:

- iPhone app shell with `Home`, `Rooms`, `Queue`, and `Settings`
- Sonos OAuth through a Cloudflare Worker token broker so the iOS app does not ship the Sonos client secret
- Sonos Control API command path for play, pause, next, previous, seek, group/player volume, mute, now-playing, favorites, playlists, and cloud queue playback
- local discovery/bootstrap for nearby Sonos players and manual local mode for advanced LAN-only behavior
- real mini-player, expandable player sheet, queue inspection/editing, room selection, group awareness, volume controls, and home theater tuning
- shared app/widget state with artwork caching
- native Apple now-playing integration for Lock Screen and Control Center controls when Sonos exposes enough metadata
- Apple Music as the first live source adapter for metadata, library/search/browse surfaces, and Sonos-owned playback payload research
- RevenueCat-backed Sonoic Plus foundation for future support and personalization features
- focused Swift tests around Sonos Control API, cloud queue context, Apple Music payload generation, shared artwork storage, and cloud-first state invariants

Still in progress:

- broader real-device validation across Sonos households and home theater products
- more reliable Apple Music catalog/library playback coverage through Sonos-owned payloads and cloud queues
- App Intents, shortcuts, widgets, and deeper outside-app entry points
- additional source adapters such as Spotify, Tidal, Sonos Radio, and SoundCloud
- actual Sonoic Plus personalization features such as themes, app icons, Home ordering, widget styles, and room presets

## Product Direction

Sonoic is intentionally narrow:

- Sonos is the audio owner.
- Cloud commands are the normal control path.
- LAN behavior is explicit, not a hidden fallback.
- The active room or group matters more than broad music-client features.
- Stale or unavailable state should be visible instead of disguised as fresh state.

The near-term product goal is to make everyday control of one real Sonos household feel faster and clearer than the default experience.

## Repository Shape

```text
SonoicApp/
  App/       app entry, scene wiring, background refresh hooks
  Model/     app state, source browsing, command orchestration
  Views/     SwiftUI surfaces organized by feature

SonoicShared/
  Model/     data snapshots shared across app and widget targets
  Sonos/     Sonos clients, parsers, Control API models, queue helpers
  Storage/   App Group shared state and artwork storage

SonoicWidgets/
  widget views and widget state loading

sonoic-sonos-worker/
  Cloudflare Worker token broker for Sonos OAuth

docs/
  public project docs, roadmap, reliability, security, and setup notes
```

For more detail, read [ARCHITECTURE.md](ARCHITECTURE.md) and the [docs index](docs/README.md).

## Running The App

Requirements:

- Xcode with Swift 6.3 support
- an iPhone or simulator build environment
- a Sonos household for real device validation
- a Sonos Control API integration for cloud control

Before running on your own Apple developer account:

1. Open `Sonoic.xcodeproj` in Xcode.
2. Update signing for the app and widget targets.
3. Replace bundle identifiers and App Group identifiers with your own namespace.
4. Configure Sonos OAuth using [docs/sonos-oauth-dev-setup.md](docs/sonos-oauth-dev-setup.md).
5. Run on a device connected to the same local network as your Sonos household.
6. Open `Rooms`, allow local-network access, and choose a discovered player or group.

Notes:

- The app requests local-network access for discovery, diagnostics, manual local mode, and local-only tuning controls.
- The app requests Apple Music access for metadata and service browsing. Sonoic does not use MusicKit app-owned playback as its main play path.
- Sonoic Plus uses RevenueCat. To preview the paywall path, add a `RevenueCatAPIKey` bundle value and keep the Plus entitlement identifier as `plus`, or override it with `SonoicPlusEntitlementIdentifier`.
- Lock Screen and Control Center support depend on what Sonos exposes for the current source, especially duration, progress, item identity, and queue ownership.

## Development

Useful commands:

```sh
python3 scripts/agent_harness_check.py
xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Start with:

- [CONTRIBUTING.md](CONTRIBUTING.md) for contribution and PR expectations
- [ARCHITECTURE.md](ARCHITECTURE.md) for dependency rules and control-plane boundaries
- [docs/ROADMAP.md](docs/ROADMAP.md) for current priorities
- [AGENTS.md](AGENTS.md) for AI-assisted contributor guidance

## Open Source Notes

Sonoic is being prepared for open-source development, but the public baseline is still settling.

That currently means:

- the code is real and buildable
- public docs should describe product direction, setup, architecture, and validation
- internal working-memory docs should stay out of the public tree unless they are useful to outside contributors
- a public license has not been chosen yet

## Disclaimer

Sonoic is an independent project and is not affiliated with or endorsed by Sonos, Apple, Spotify, or Apple Music.
