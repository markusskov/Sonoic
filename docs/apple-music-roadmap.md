# Apple Music Roadmap

Sonoic's Apple Music path should stay Sonos-first. MusicKit can provide authorization, catalog metadata, library metadata, search, browse, and account context, but Sonoic should only show Play when it has a trustworthy Sonos-native payload for the selected target.

This roadmap starts from the current V1 foundation:

- Apple Music authorization status in Settings
- catalog search with scoped results
- saved library lanes for playlists, artists, albums, and songs
- recently added library metadata
- search, library, browse, and detail screens
- Sonos-owned playback candidates for exact favorites and proven Apple Music payloads
- metadata-only behavior for items that do not have a trustworthy Sonos-owned payload

## Guardrails

- Keep Sonos as the audio owner.
- Do not use MusicKit app-owned playback for the main Sonoic play path.
- Do not imply arbitrary Apple Music items are playable until Sonoic can build or receive a valid Sonos-owned playback payload.
- Prefer small vertical slices that can be built and manually verified.
- Keep source and search UI honest about capability.

## Milestone 1: Diagnostics And Trust

1. Add a runtime MusicKit entitlement diagnostic so Settings can show whether the app profile contains the expected MusicKit service.
2. Split Apple Music authorization from Apple Music request readiness so "authorized but not provisioned" is clear.
3. Persist the latest Apple Music request failure with timestamp, endpoint family, and user-facing recovery copy.
4. Add a Settings action that opens iOS Settings when authorization is denied or restricted.
5. Hide or disable actions that cannot help for the current Apple Music state.
6. Show a single consistent disabled state in Home source detail and Search when MusicKit is unavailable.
7. Map common Apple Music API failures into friendly states: missing service, network unavailable, storefront unavailable, unauthorized, rate limited, and unknown.
8. Add a "last refreshed" timestamp for Apple Music library and browse sections.
9. Add a manual refresh button for Apple Music metadata in Settings.
10. Keep search results on screen when a refresh fails, with an inline stale-state note.

## Milestone 2: Stable Identity

11. Add a typed Apple Music identity model that separates catalog IDs, library IDs, storefront IDs, and item kind.
12. Store Apple Music identity on `SonoicSourceItem` instead of deriving behavior from display IDs.
13. Use the identity model for detail routing from search, library, browse, and recently added.
14. Add tests for catalog and library identity equality.
15. Add tests that prove catalog IDs and library IDs do not collide.
16. Cache detail state by typed identity instead of string IDs.
17. Preserve raw Apple Music API IDs for diagnostics without exposing them as UI IDs.
18. Add fixtures for songs, albums, artists, playlists, and stations.
19. Make unsupported item kinds explicit instead of falling into generic metadata behavior.
20. Audit every `item.id` use in source/search/detail code and remove behavior based on string parsing.

## Milestone 3: Browse And Library Depth

21. Add "View All" screens for saved playlists, artists, albums, songs, and recently added.
22. Add paging support for Apple Music library requests.
23. Add paging support for catalog search.
24. Add paging support for charts and browse destinations when Apple exposes next links.
25. Add selected-genre chart loading.
26. Add new releases lanes.
27. Add curated playlist lanes.
28. Add recommendations lanes where MusicKit authorization and account state allow it.
29. Add category detail screens.
30. Add playlist curator, description, and last-updated metadata.
31. Add album release date, track count, and copyright metadata where available.
32. Add artist top songs and top albums when catalog relationships are available.
33. Add station/radio metadata as metadata-only until a Sonos payload exists.
34. Add empty-state copy for each library lane.
35. Add retry affordances per section instead of one page-level failure.

## Milestone 4: Search As A Product Surface

36. Keep Search as a standalone tab with service scope selection.
37. Add source filters for Apple Music, Sonos favorites, Spotify placeholder, and future services.
38. Add kind filters for songs, albums, artists, playlists, and stations.
39. Add recent searches.
40. Add fast clear and cancel behavior.
41. Add exact Sonos favorite match highlighting in search result sections.
42. Add a "Playable with Sonos" filter once enough payload candidates exist.
43. Add debounced search cancellation tests.
44. Keep the last successful query visible when a new query fails.
45. Add accessibility labels for search scope and result actions.

## Milestone 5: Sonos-Native Playback Research

Shipped first safety slice:

- `SonosPlayablePayloadPreparer` validates existing Sonos-native favorite payloads before launch.
- Known Sonos service/container URI families are allowed; queue-owned, group, and generic HTTP URLs are rejected.
- DIDL metadata from favorites is preserved and trimmed, not synthesized.
- Tests cover playable favorite payloads and rejected payloads.
- Settings diagnostics classify current URI ownership so Sonoic can tell queue-backed playback apart from service containers, streams, TV audio, line-in, and unknown sources.
- Research notes live in [Sonos-Native Playback Research](sonos-native-playback-research.md).

Next:

52. Research Sonos Control API authorization and playback-session requirements.
53. Keep hardening Apple Music catalog and library payload generation with real device confirmation.
54. Preserve playlist and album queue/session context when playback starts from a collection.
55. Keep Apple Music playback affordances gated behind proven Sonos-owned payloads.
56. Add diagnostics that explain why an Apple Music item is metadata-only.

## Milestone 6: Queue And Handoff

57. Keep "Play Next" and "Add to Queue" hidden until source ownership and device QA prove the active source can accept queue mutation.
58. Add queue preview for source playlists once payloads are reliable.
59. Add a safe handoff flow that starts a favorite without destroying the current queue.
60. Add queue ownership diagnostics after service starts.
61. Add state refresh after any service-backed play action.
62. Add optimistic UI only after Sonos confirms the transport state.
63. Add recovery UI if Sonos accepts a payload but metadata does not update.
64. Add tests for queue-safe favorite starts.

Closed experiment:

- A local `AddURIToQueue`/`Play Next` attempt with favorite-backed Apple Music payloads did not reliably add to the active queue on device. Do not re-open this as a UI feature until Sonoic either owns a true `x-rincon-queue:` source or uses a documented Sonos-native service/cloud-queue path.

## Milestone 7: UI Polish And Maintainability

65. Split the Apple Music catalog client into smaller files by request family.
66. Keep Apple Music view files under the preferred view-size guardrail.
67. Extract shared Apple Music row art, badges, and metadata chips.
68. Add SwiftUI previews for search, source detail, library detail, item detail, and browse destinations.
69. Add fixture-backed previews for authorized, denied, loading, empty, stale, and failed states.
70. Add a compact service status row used by Home and Settings.
71. Update `README.md` after each major Apple Music milestone.
72. Keep this roadmap pruned as tasks move from plan to shipped behavior.

## Manual Verification Points

Manual device checks are required whenever a change affects:

- MusicKit authorization or provisioning behavior
- real Apple Music API search, browse, library, or recommendations
- Sonos playback start, queue ownership, or transport state
- Lock Screen or Control Center now-playing state
- source playback capability labels
