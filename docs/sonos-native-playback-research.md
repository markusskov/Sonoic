# Sonos-Native Playback Research

Sonoic's playback goal is still simple: Sonos should own the audio output. MusicKit can provide Apple Music identity, metadata, library, catalog, and search, but it does not make an Apple Music item automatically playable by Sonos.

## What We Know

- Existing Sonos favorites can include a Sonos-native playback URI and DIDL metadata. Sonoic can safely launch those through local AVTransport when `SonosPlayablePayloadPreparer` accepts the payload.
- Apple Music catalog and library IDs are Apple identities, not documented Sonos object IDs.
- `x-rincon-queue:` means the active transport is using the local Sonos queue. This is the only URI family Sonoic currently treats as locally queue-editable.
- `x-rincon-cpcontainer:` can describe a service container, but it does not prove the active source is the editable Sonos queue.
- Local `AddURIToQueue` is not reliable for the Apple Music favorite payloads we tested, even when the payload can start direct playback.

## Official Sonos Path

The documented Sonos-native path for service playback points toward Sonos cloud/control integration:

1. Register a Sonos Control API integration and use Sonos OAuth with playback control scopes.
2. Resolve the user's Sonos household and player/group.
3. Create or use a playback session for the target.
4. Provide a cloud queue or playback object that Sonos can resolve through a real Sonos music service identity.
5. Load the cloud queue or playback object into the Sonos playback session.

Useful docs:

- [Sonos Control API](https://docs.sonos.com/docs/control)
- [Sonos Authorization](https://docs.sonos.com/docs/authorize)
- [Playback Sessions](https://docs.sonos.com/docs/playback-sessions)
- [Cloud Queue: Play Audio](https://docs.sonos.com/docs/cloud-queue-play-audio)
- [loadCloudQueue](https://docs.sonos.com/reference/playbacksession-loadcloudqueue-sessionid)
- [Playback Objects](https://docs.sonos.com/docs/playback-objects)
- [Account Matching](https://docs.sonos.com/docs/account-matching)
- [Playback on Sonos](https://docs.sonos.com/docs/playback-on-sonos)

## Apple Music Boundary

Apple MusicKit gives Sonoic permissioned access to Apple Music metadata and user-library context:

- [Apple Music API](https://developer.apple.com/documentation/applemusicapi/)
- [MusicKit User Authentication](https://developer.apple.com/documentation/applemusicapi/user_authentication_for_musickit)
- [Get a Catalog Song](https://developer.apple.com/documentation/applemusicapi/get-a-catalog-song)
- [Get All Library Songs](https://developer.apple.com/documentation/applemusicapi/get-all-library-songs)

Those Apple IDs are valuable for UI, search, detail screens, and matching against existing Sonos favorites. They are not enough, by themselves, to build a valid Sonos-native Apple Music playback object.

## Current Sonoic Rule

Sonoic should only show direct Play for Apple Music rows when it has an exact Sonos-native payload from an existing Sonos favorite or another proven Sonos source. Everything else stays metadata-only.

Queue actions should be gated even more strictly:

- Allow local queue inspection/editing only when the current URI is `x-rincon-queue:`.
- Do not treat `x-rincon-cpcontainer:` as queue ownership.
- Do not reintroduce `Play Next` or `Add to Queue` for service payloads until a device test proves the target source accepts the operation and the queue refresh reflects it.

## Next Slices

1. Keep source ownership diagnostics visible under Settings -> Advanced.
2. Add device logs for current URI, track URI, and queue edit attempts before another queue-action PR.
3. Spike Sonos Control API auth separately from local SOAP playback.
4. Spike whether Sonos exposes a documented Apple Music service object mapping for an authorized household.
5. If the mapping exists, prototype payload generation behind tests and hidden debug UI first.
6. If the mapping requires cloud queue/service infrastructure, design that as a separate backend-backed milestone.
