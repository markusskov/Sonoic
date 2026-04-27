# Reliability

Sonoic controls real local Sonos devices, so reliability means the app tells the truth about what it knows.

## Core Reliability Rules

- Failed refreshes must not look successful.
- Stale now-playing, queue, room, or topology state must remain distinguishable from fresh state.
- Discovery should remain the primary setup path, with manual host entry kept as an honest fallback.
- Widget and outside-app state should prefer honest unavailable state over optimistic old data.
- Debug logs are useful locally but should not become noisy permanent output.

## Manual Verification

Use [manual-host-refresh-verification.md](manual-host-refresh-verification.md) for the fallback host, room name, and bonded setup refresh checklist.

For code-affecting changes, run an Xcode build when the local environment allows it:

```sh
xcodebuild -project Sonoic.xcodeproj -scheme Sonoic -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

For harness and docs changes, run:

```sh
python3 scripts/agent_harness_check.py
```

## Known Reliability Gaps

- No automated test target is visible yet.
- Discovery and grouping need more validation across multi-room and multi-household setups.
- Native now-playing ownership is still sensitive because Sonoic is a Sonos controller, not the audio output owner.
- Local network behavior depends on real device, simulator, signing, and network conditions.

## Future Checks

- Parser fixtures for DIDL, SOAP, queue, metadata, and duration behavior.
- State-transition tests for stale, failed, loading, discovered, and fallback-host states.
- A simulator smoke-test script for basic app navigation.
- A device checklist for real local-network Sonos behavior.
