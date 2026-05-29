# Reliability

Sonoic controls real Sonos devices, so reliability means the app tells the truth about what it knows and what it can control.

## Core Rules

- Failed refreshes must not look successful.
- Stale now-playing, queue, room, volume, or topology state must stay distinguishable from fresh state.
- Sonos Cloud command mode must not silently fall back to LAN for normal playback commands.
- LAN should remain explicit: discovery, manual local mode, diagnostics, and local-only tuning.
- Widget and outside-app state should prefer honest unavailable state over optimistic old data.
- Debug logs are useful locally but should not become noisy permanent output.

## Validation

For docs, scripts, project structure, or harness changes:

```sh
python3 scripts/agent_harness_check.py
```

For Swift, project, entitlement, asset, plist, or app behavior changes:

```sh
xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Use [Manual Host Refresh Verification](manual-host-refresh-verification.md) when validating fallback host, room name, and bonded setup refresh behavior on device.

## Manual Verification Needed

Manual device checks are still required for:

- real Sonos playback, seek, queue, now-playing, volume, and mute behavior
- Sonos Cloud authorization loss and token refresh behavior
- LAN discovery and manual local mode
- widgets, Lock Screen, Control Center, and App Group state
- home theater controls and product-specific tuning

## Known Gaps

- Real-device validation is still broader than the automated suite.
- Discovery and grouping need more validation across multi-room and multi-household setups.
- Native now-playing ownership remains sensitive because Sonoic is a Sonos controller, not the audio output owner.
- Local network behavior depends on device, simulator, signing, and network conditions.
