# TestFlight Tester Guide

Use this guide when inviting beta testers or asking Markus/Charles to run a
manual TestFlight pass. It is intentionally tester-facing: it explains what to
set up, what is expected to work, what is out of scope, and what to include in a
bug report.

## Before Installing

Testers need:

- an iPhone running the supported iOS beta/runtime for the current build
- the TestFlight build installed from TestFlight, not from Xcode
- a Sonos account with at least one household and one reachable speaker
- the iPhone on the same Wi-Fi/network as the Sonos speakers for discovery
- Apple Music access if they want to search, browse, or start source playback

Sonoic controls Sonos speakers. The iPhone is not the audio output.

Apple Music is the only source Sonoic can start in this beta. Other services may
continue to play if started in Sonos or elsewhere, but Sonoic should not present
Spotify, Tidal, Sonos Radio, SoundCloud, or other services as live beta sources.

## First-Run Setup

1. Install the processed build through TestFlight.
2. Launch Sonoic and connect the Sonos account when prompted.
3. Allow local network access when iOS asks; this is needed for speaker
   discovery and local diagnostics.
4. Choose a room or group after speakers are discovered.
5. Connect Apple Music from Settings if search, browse, or Apple Music playback
   testing is part of the pass.
6. Open Settings and confirm:
   - Sonos Account is connected.
   - Music shows Apple Music as connected or gives a clear recovery state.
   - A room is selected.
   - Sonoic Plus either shows as disabled for the build or opens the TestFlight
     paywall when Plus validation is part of the pass.
   - Settings > Advanced > Support Summary is visible after selecting a room.

Skipping Sonos login is allowed only when the pass is explicitly about local
discovery or diagnostics. Normal playback, favorites, Cloud Queue, transport,
seek, volume, and now-playing validation require Sonos Cloud authorization.

## Smoke Test Pass

Run these before deeper scenario testing:

1. Relaunch the app and confirm Sonos remains connected.
2. Switch rooms or groups and confirm the mini-player follows the selected room.
3. Start an Apple Music song, album, or playlist only when Sonoic shows a play
   affordance.
4. Use play/pause/next/previous and confirm the UI does not report success when
   Sonos does not change state.
5. Open Queue and confirm it either shows the current queue or an honest
   unavailable/stale state.
6. Try one failure case, such as turning off Wi-Fi or testing an unavailable
   item, and confirm Sonoic explains the failure without fake playback state.

## Bug Reports

For each report, include:

- TestFlight build number and app version
- iPhone model and iOS version
- Sonos products involved and whether the room was grouped
- whether playback was started in Sonoic, in the Sonos app, or elsewhere
- the exact steps, expected result, actual result, and approximate local time
- a screenshot or short screen recording when the UI looks stale or inconsistent
- the redacted Settings > Advanced > Support Summary for auth, playback, queue,
  Cloud Queue, room selection, or mini-player issues

Do not include raw OAuth URLs, auth codes, HTTP headers, access tokens, refresh
tokens, Cloudflare secrets, local OAuth config, raw console logs, unredacted
local IP addresses, or raw Sonos player IDs.

## Known Beta Boundaries

- Sonoic starts Apple Music source playback only when it has a trustworthy
  Sonos-owned path.
- Direct favorite playback depends on Sonos Control API favorites being
  available for the active household.
- Lock Screen, Control Center, artwork, duration, seek, and queue behavior depend
  on what Sonos exposes for the active source.
- LAN/manual mode is for discovery, diagnostics, and local-only tuning. It is
  not the normal playback control path.
- Widget state is best-effort shared state and should prefer honest unavailable
  state over stale success.
- Sonoic Plus may be disabled in builds that are not validating purchases. When
  enabled, purchase and restore behavior must be tested through TestFlight
  sandbox, not an Xcode-installed build.
