# Sonos Control API Foundation

## Current Behavior
Sonoic now treats the Sonos Control API as the normal playback control plane. LAN remains available for local discovery/bootstrap, advanced diagnostics, manual local mode, and local-only tuning surfaces that Cloud does not expose well enough yet. Apple Music catalog playback uses a Sonoic-owned Cloud Queue session instead of guessed local service URI playback.

## Structural Change
Use the official Sonos Control API as the primary command path for account, household, group, player, playback, queue-session, volume, and mute behavior. The current API surface mirrors the official Sonos sample app where possible:

- `GET /households`
- `GET /households/{householdId}/groups`
- `GET /households/{householdId}/favorites`
- `GET /households/{householdId}/playlists`
- `POST /groups/{groupId}/favorites`
- `POST /groups/{groupId}/playlists`
- `GET /groups/{groupId}/playback`
- `GET /groups/{groupId}/playbackMetadata`
- `POST /groups/{groupId}/playback/play`
- `POST /groups/{groupId}/playback/pause`
- `POST /groups/{groupId}/playback/togglePlayPause`
- `POST /groups/{groupId}/playback/skipToNextTrack`
- `POST /groups/{groupId}/playback/skipToPreviousTrack`
- `POST /groups/{groupId}/playback/seek`
- `POST /groups/{groupId}/playback/seekRelative`
- `POST /groups/{groupId}/playbackSession`
- `POST /playbackSessions/{sessionId}/playbackSession/loadCloudQueue`
- `POST /playbackSessions/{sessionId}/playbackSession/skipToItem`
- `POST /playbackSessions/{sessionId}/playbackSession/seek`
- `POST /playbackSessions/{sessionId}/playbackSession/refreshCloudQueue`

Hidden LAN fallback must not happen in normal transport paths. If Cloud command mode is active and a Cloud command cannot be sent, Sonoic should surface unavailable state instead of silently issuing the same action over LAN. Tokens must not be stored in `UserDefaults` and the Sonos client secret must not ship in the iOS app.

The official sample confirms that seek reliability comes from the current playback/session identity:

- `playbackStatus.itemId` and `queueVersion` identify the current item/session.
- `playbackMetadata.currentItem.track.durationMillis` provides the duration that should drive player and Lock Screen scrubber availability.
- Group `seek` and `seekRelative` can include `itemId`; Sonos rejects the command if the current item changed, which avoids applying a scrub to the wrong track.
- Sonoic-owned Cloud Queue playback should use playback-session `seek` with the Cloud Queue item ID. Numeric group playback `itemId` values are not reliable Cloud Queue object IDs.
- `playbackStatus.positionMillis` is a snapshot, not a continuously ticking clock, so Sonoic still needs its existing local progress timer.

The official sample also confirms that arbitrary service playback is a playback-session/cloud-queue problem, not a pure MusicKit ID problem. `loadCloudQueue` expects a Sonoic-owned queue endpoint and optional Sonos metadata, backed by the Worker Cloud Queue endpoints.

## Validation Check
- Control API model/transport tests prove request shape and JSON decoding.
- Cloud Queue tests prove queue endpoint shape and item lookup.
- Full build passes with the new shared files included in the filesystem-synced Xcode project.
- Manual device testing remains required for playback, seek, Lock Screen, Control Center, queue state, and now-playing convergence.
- Worker tests stay green because Sonos OAuth token exchange/refresh and Cloud Queue delivery are part of the playback path.

## Remaining Migration Tasks
- Finish real-device validation for playback-session seek from Player and Lock Screen.
- Keep queue, now-playing, artwork, and recent playback converged on Cloud Queue snapshots where Sonoic owns the session.
- Move any remaining normal command path that still silently depends on LAN into explicit Cloud unavailable or Local Mode behavior.
- Keep LAN mutation and inspection under manual local mode, diagnostics, or local-only tuning.
- Use Control API event subscriptions from a backend if we need reliable cloud now-playing updates.
