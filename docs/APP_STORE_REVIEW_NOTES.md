# App Store Review Notes

Use this template when preparing App Store Connect review notes for a TestFlight
or App Review submission. Keep it factual, non-secret, and aligned with the
current beta scope.

## Reviewer Summary

Sonoic is an iPhone-first controller for Sonos speakers. The TestFlight build
uses Sonos Cloud authorization for normal playback control and uses local
network discovery for finding speakers and diagnostics.

Apple Music is the only live music source Sonoic can start in this beta. Other
services may appear in Sonos now-playing state when started outside Sonoic, but
they are not presented as supported Sonoic playback sources.

## Required Test Environment

- A physical iPhone on the same Wi-Fi/network as at least one reachable Sonos
  speaker.
- A Sonos account with an existing household and room.
- Apple Music access for catalog search, browse, and Apple Music playback
  validation.
- Internet access to the Sonoic Sonos Worker route used by the submitted build.

Sonoic controls Sonos speakers. The iPhone is not the audio output device.

## Permissions And Sign-In Notes

- Sonos sign-in opens the Sonos OAuth flow and returns through the `sonoic`
  callback scheme.
- Apple Music permission is used for Apple Music search and source browsing.
- Local Network permission is used for Sonos discovery and local diagnostics.
- Background modes support audio state continuity and background refresh.
- The app does not require reviewers to provide raw OAuth codes, access tokens,
  refresh tokens, Cloudflare secrets, local OAuth config, or private signing
  assets.

## Suggested Review Path

1. Install the TestFlight/App Review build on a physical iPhone.
2. Launch Sonoic, connect Sonos, and allow local network access.
3. Select a Sonos room or group.
4. Connect Apple Music if prompted.
5. Search for an Apple Music song and start playback from the Search tab.
6. Use play, pause, next, previous, volume, queue, and mini-player surfaces.
7. Open Settings > Advanced > Support Summary to inspect the redacted support
   summary if a failure needs reporting.

## Known Beta Boundaries

- Sonoic starts Apple Music playback only when it can use a trustworthy
  Sonos-owned playback path.
- Direct Sonos favorite playback depends on Sonos Control API favorites being
  available for the active household.
- Lock Screen, Control Center, artwork, duration, seek, and queue behavior
  depend on what Sonos exposes for the active source.
- Sonoic Plus may be disabled in builds that are not validating purchases; if
  enabled, purchase and restore should be tested through TestFlight sandbox.
- Widget state is best-effort shared state and should prefer unavailable state
  over stale success.

## Privacy And Support Notes

- Review the App Privacy answers against [Security And Privacy](SECURITY.md) and
  [TestFlight Readiness](TESTFLIGHT_READINESS.md) before submission.
- Confirm the App Store Connect support URL and privacy policy URL are current.
- If review finds a playback/auth/queue issue, pair the App Store Connect or
  TestFlight report with the redacted Settings > Advanced > Support Summary.
- Do not include secrets, tokens, private URLs, local IP addresses, or raw Sonos
  player identifiers in App Store Connect notes, screenshots, or support
  follow-up.
