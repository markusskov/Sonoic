# Sonoic Architecture

Sonoic is an iPhone-first Sonos controller. The architecture should stay direct, feature-shaped, and easy for future agents to navigate.

## Current Shape

```text
SonoicApp/
  App/      app entry, scene wiring, background refresh hooks
  Model/    app state, app-only models, now-playing integration
  Views/    feature-shaped SwiftUI screens and surfaces

SonoicShared/
  Model/    data snapshots shared across targets
  Sonos/    SOAP clients, parsers, Sonos-specific helpers
  Storage/  App Group-backed shared state and artwork storage

SonoicWidgets/
  widget views, widget bundle, widget state loading
```

## Dependency Rules

- `SonoicApp` may depend on `SonoicShared`.
- `SonoicWidgets` may depend on `SonoicShared`.
- `SonoicShared` must not depend on app-only or widget-only concepts.
- Sonos network parsing and SOAP details belong in `SonoicShared/Sonos`.
- App state orchestration belongs in `SonoicApp/Model`.
- UI composition belongs in `SonoicApp/Views/<Feature>`.

## Source Browsing

Source browsing stays inside `SonoicApp` because it combines app navigation, MusicKit metadata, Sonos-native playback payloads, and user-facing capability decisions.

- `SonoicModel` remains the top-level owner of source state.
- `SonoicSourceAdapter` centralizes source capabilities, search, detail loading, favorite toggles, and Sonos playback payload lookup.
- Apple Music is the first live adapter. Other services can be metadata-only until they have real auth, catalog, or Sonos payload support.
- Search uses one session state with query, source filter, kind filter, and per-source result states.
- Artists, albums, and playlists route to one shared source detail screen regardless of whether the entry point is Search, Home, Recently Played, Favorites, a row menu, or the player.
- Songs do not have a detail route. Song rows play only when the adapter can provide a trustworthy Sonos-owned payload.

## Sonoic Plus

Sonoic Plus is an app-only purchase and personalization layer. It must not gate core Sonos control: discovery, playback, queue, rooms, Lock Screen, Control Center, and the default Home experience stay free.

- `SonoicModel` owns the observable Plus state.
- `SonoicPlusController` wraps RevenueCat and RevenueCatUI behind Sonoic-owned types.
- Plus feature checks use `SonoicPlusFeature` so future UI can ask one small question without depending on RevenueCat directly.
- RevenueCat setup is driven by bundle configuration. When `RevenueCatAPIKey` is absent, the app stays in a not-configured state instead of failing startup.
- Personalization features should be added as narrow product slices, not as broad paywall plumbing.

## Design Bias

Sonoic should look more like a focused Apple sample app than a layered enterprise app.

- One clear top-level app model is preferred until pressure proves otherwise.
- Typed environment injection is preferred over generic service containers.
- Feature folders are preferred over abstract architecture folders.
- Shared helpers should be narrow and named after the real behavior they support.
- New folders should follow real product surfaces, not imagined future systems.

## Architecture Change Bar

Open an execution plan when a change does any of the following:

- changes dependency direction between top-level areas
- introduces a new shared abstraction or cross-cutting service
- changes App Group, bundle, entitlement, or background behavior
- changes Sonos command, parser, queue, discovery, or now-playing ownership semantics
- creates a new target, package, workflow, or persistent tool

Use [docs/exec-plans/template.md](docs/exec-plans/template.md) and keep the plan in `docs/exec-plans/active/` until the work lands.

## Validation

Always run the harness check:

```sh
python3 scripts/agent_harness_check.py
```

For Swift, project, entitlement, asset, or plist changes, also run:

```sh
xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Record any environment-specific build limitation in the PR verification notes.
