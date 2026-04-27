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
