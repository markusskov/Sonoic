# Sonos Control API Foundation

> Status: Superseded by the Cloud Control Spine plan. This file is retained as historical context for the first Control API research slice; LAN-default statements below describe the pre-spine state, not the current product direction.

## Current Behavior
Sonoic controls Sonos over the local SOAP APIs. This works well for room discovery, volume, queue inspection, queue editing, now-playing reads, and saved Sonos favorite playback. Apple Music catalog playback currently relies on locally generated Sonos URI/DIDL payloads, which is fragile: the player can accept playback while refusing reliable seek behavior, or reject a guessed URI shape entirely.

## Structural Change
Add the official Sonos Control API as a parallel, gated command path. The first slice introduces source-controlled models and a JSON client for the API surface used by the official Sonos sample app:

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
- `POST /playbackSessions/{sessionId}/playbackSession/refreshCloudQueue`

The app keeps LAN SOAP as the default behavior until Sonos OAuth and group identity mapping exist. Tokens must not be stored in `UserDefaults` and the Sonos client secret must not ship in the iOS app.

The official sample confirms that seek reliability should eventually come from Control API playback state plus current item identity:

- `playbackStatus.itemId` and `queueVersion` identify the current item/session.
- `playbackMetadata.currentItem.track.durationMillis` provides the duration that should drive player and Lock Screen scrubber availability.
- `seek` and `seekRelative` can include `itemId`; Sonos rejects the command if the current item changed, which avoids applying a scrub to the wrong track.
- `playbackStatus.positionMillis` is a snapshot, not a continuously ticking clock, so Sonoic still needs its existing local progress timer.

The official sample also confirms that arbitrary service playback is a playback-session/cloud-queue problem, not a pure MusicKit ID problem. `loadCloudQueue` expects a Sonoic-owned queue endpoint and optional Sonos metadata. That should be a separate backend-backed migration, not another generated local URI variant.

## Validation Check
- Existing LAN playback and queue tests keep passing.
- New Control API model/transport tests prove request shape and JSON decoding.
- Full build passes with the new shared files included in the filesystem-synced Xcode project.
- Manual device testing remains required before any Control API command path is enabled because it affects Sonos playback, Lock Screen, widgets, and now-playing state.
- The current PR must not switch playback controls to Control API until a production-safe token source and group mapping exist.

## Later Migration Tasks
- Add production-safe Sonos OAuth via backend token exchange/refresh.
- Map cloud households/groups to local discovered rooms and active targets.
- Route Sonos favorites/playlists through `loadFavorite` and `loadPlaylist` when authorized.
- Route Control Center/player scrubbing through Control API `seek` with `itemId` once playback metadata is trusted.
- Design Sonoic Cloud Queue endpoints before attempting arbitrary Apple Music catalog playback through Sonos sessions.
- Use Control API event subscriptions from a backend if we need reliable cloud now-playing updates.
