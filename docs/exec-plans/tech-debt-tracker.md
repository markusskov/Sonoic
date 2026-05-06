# Technical Debt Tracker

Use this file for intentional follow-up work discovered while implementing real slices.

## Open Items

2026-05-04 - Playback - Manual host transport/progress files are still large
Context:
`SonoicModel+ManualHostProgress.swift` and `SonoicModel+ManualHostTransport.swift` remain among the largest model extensions after the source and settings splits.
Impact:
Playback reliability work is still concentrated in long files, making review slower and accidental state regressions more likely.
Suggested next step:
Extract narrow helper types for manual transition confirmation, transport command availability, and diagnostics formatting while preserving `SonoicModel` as the top-level owner.

2026-05-04 - Now Playing - Session controller still mixes command wiring and state projection
Context:
`SonoicNowPlayableSessionController.swift` remains a large file that owns audio anchor setup, MPNowPlayingInfoCenter projection, and remote command handling.
Impact:
Lock Screen and Control Center changes are high-value and high-risk, so smaller internal seams would make future review safer.
Suggested next step:
Split now-playing info construction and command availability calculations into dedicated helpers with focused tests.

2026-05-04 - Source Domain - Source item model is feature-rich and still growing
Context:
`SonoicSourceItem.swift` carries source identity, display metadata, playback capability, and convenience construction.
Impact:
Adding Spotify/Tidal/SoundCloud may make this model harder to reason about if all provider nuance accumulates here.
Suggested next step:
Keep the public item stable, but move provider-specific construction helpers into adapter-owned mapper files.

2026-05-04 - Sonos Protocol - Queue and content diagnostics need parser parity checks
Context:
Queue metadata, Sonos recently played, favorites, and content probes now work but were discovered through iterative device testing.
Impact:
Future parser changes could silently regress playlist/album queue metadata or recently played behavior.
Suggested next step:
Add fixture-based DIDL/content-directory tests before making more queue or Sonos browse changes.

## Entry Format

```text
YYYY-MM-DD - Area - Short title
Context:
Impact:
Suggested next step:
```
