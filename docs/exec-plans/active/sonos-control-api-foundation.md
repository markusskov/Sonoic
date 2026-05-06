# Sonos Control API Foundation

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

The app keeps LAN SOAP as the default behavior until Sonos OAuth and group identity mapping exist. Tokens must not be stored in `UserDefaults` and the Sonos client secret must not ship in the iOS app.

## Validation Check
- Existing LAN playback and queue tests keep passing.
- New Control API model/transport tests prove request shape and JSON decoding.
- Full build passes with the new shared files included in the filesystem-synced Xcode project.
- Manual device testing remains required before any Control API command path is enabled because it affects Sonos playback, Lock Screen, widgets, and now-playing state.

## Later Migration Tasks
- Add production-safe Sonos OAuth via backend token exchange/refresh.
- Map cloud households/groups to local discovered rooms and active targets.
- Route Sonos favorites/playlists through `loadFavorite` and `loadPlaylist` when authorized.
- Evaluate Playback Sessions / Cloud Queue for arbitrary Apple Music catalog playback.
- Use Control API event subscriptions from a backend if we need reliable cloud now-playing updates.
