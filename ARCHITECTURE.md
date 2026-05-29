# Sonoic Architecture

Sonoic should stay direct, feature-shaped, and easy to review. The codebase favors concrete Swift types and visible product behavior over generic layers.

## Current Shape

```text
SonoicApp/
  App/       app entry, scene wiring, background refresh hooks
  Model/     app state, source browsing, command orchestration
  Views/     SwiftUI screens and surfaces organized by feature

SonoicShared/
  Model/     data snapshots shared across app and widget targets
  Sonos/     SOAP clients, Control API clients, parsers, queue helpers
  Storage/   App Group shared state and artwork storage

SonoicWidgets/
  widget views and widget state loading

sonoic-sonos-worker/
  Cloudflare Worker token broker for Sonos OAuth
```

## Dependency Rules

- `SonoicApp` may depend on `SonoicShared`.
- `SonoicWidgets` may depend on `SonoicShared`.
- `SonoicShared` must not depend on app-only, widget-only, or Worker-only concepts.
- Sonos protocol, parsing, SOAP, Control API, and cloud queue helper types belong in `SonoicShared/Sonos` when they are not app UI concerns.
- App orchestration belongs in `SonoicApp/Model`.
- UI composition belongs in `SonoicApp/Views/<Feature>`.
- Worker token-broker code stays in `sonoic-sonos-worker/` and must not leak secrets into the iOS app.

## Control Plane

Sonoic is always cloud-first for normal Sonos control.

- Sonos Control API owns everyday playback commands, seek, now-playing refresh, group/player volume, mute, cloud favorites/playlists, and cloud queue playback.
- Sonos OAuth tokens are stored in Keychain. The Sonos client secret lives only in the Worker.
- Cloud identity uses household, group, and player IDs. Local host/RINCON details are accessory data, not the primary target model.
- Normal transport paths must not silently fall back to LAN when Cloud command mode is active.
- When Cloud cannot send a command, the UI should surface unavailable or stale state instead of pretending a LAN command succeeded.
- LAN remains available for discovery/bootstrap, Advanced diagnostics, manual local mode, and local-only tuning controls that the Cloud API does not cover well enough yet.
- EQ, home theater tuning, Sub/surround controls, and low-level diagnostic SOAP reads belong in the local tuning island until a reliable cloud path exists.

## Source Browsing

Source browsing stays in `SonoicApp` because it combines app navigation, MusicKit metadata, Sonos-owned playback payloads, and user-facing capability decisions.

- `SonoicModel` remains the top-level owner of source state.
- Apple Music is the first live adapter.
- Other services can be metadata-only until they have real auth, catalog, or Sonos-owned payload support.
- Search uses one session state with query, source filter, kind filter, and per-source result states.
- Artists, albums, and playlists route to one shared source detail screen.
- Songs do not have a detail route. Song rows play only when the adapter can provide a trustworthy Sonos-owned payload.

## Sonoic Plus

Sonoic Plus is an app-only support and personalization layer. It must not gate core Sonos control.

Free core behavior includes discovery, playback, queue, rooms, Lock Screen, Control Center, and the default Home experience.

- `SonoicModel` owns the observable Plus state.
- `SonoicPlusController` wraps RevenueCat and RevenueCatUI behind Sonoic-owned types.
- Plus feature checks use `SonoicPlusFeature`.
- RevenueCat setup is driven by bundle configuration. When `RevenueCatAPIKey` is absent, the app stays in a not-configured state instead of failing startup.
- Personalization should land as narrow product slices, not broad paywall plumbing.

## Design Bias

- Keep one clear top-level app model until real pressure proves otherwise.
- Use typed environment injection instead of generic service containers.
- Organize by feature and screen, not by abstract layers.
- Keep helper views and helpers narrow.
- Prefer concrete types over broad protocol scaffolding.
- Add new folders only when a real product surface exists.
- Keep diagnostics behind Advanced so the main UI stays quiet.

## Architecture Change Bar

Document the reasoning in the PR, issue, or a focused doc update when a change does any of the following:

- changes dependency direction between top-level areas
- introduces a shared abstraction or cross-cutting service
- changes App Group, bundle, entitlement, or background behavior
- changes Sonos command, parser, queue, discovery, or now-playing ownership semantics
- creates a new target, package, workflow, Worker binding, or persistent tool

## Validation

Always run the repo hygiene check for docs, scripts, or project-structure changes:

```sh
python3 scripts/agent_harness_check.py
```

For Swift, project, entitlement, asset, plist, or Worker-adjacent iOS behavior changes, also run:

```sh
xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Record any environment-specific build limitation in PR verification notes. Manual device verification is still required for Sonos hardware behavior, widgets, Lock Screen, Control Center, and now-playing state.
