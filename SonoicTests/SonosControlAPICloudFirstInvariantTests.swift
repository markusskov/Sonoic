import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonosControlAPICloudFirstInvariantTests {
    @Test
    func cloudCommandModeBlocksLocalPlaybackWrappersWhenCloudTargetIsUnavailable() async {
        let model = SonoicModel()
        model.useCloudCommandModeWithoutAvailableCloudContext()
        model.nowPlaying = Self.nowPlayingSnapshot(playbackState: .playing)
        let previousNowPlaying = model.nowPlaying

        let didPlay = await model.playManualSonosPlayback()
        let didPause = await model.pauseManualSonosPlayback()
        let didSkipNext = await model.skipToNextManualSonosTrack()
        let didSkipPrevious = await model.skipToPreviousManualSonosTrack()
        let didSeek = await model.seekManualSonosPlayback(to: 42)

        #expect(!didPlay)
        #expect(!didPause)
        #expect(!didSkipNext)
        #expect(!didSkipPrevious)
        #expect(!didSeek)
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
    }

    @Test
    func cloudCommandModeBlocksDirectLocalSourcePlaybackFallback() async throws {
        let model = SonoicModel()
        model.useCloudCommandModeWithoutAvailableCloudContext()
        let previousNowPlaying = model.nowPlaying
        let item = Self.sourceItem(playbackPayload: Self.playbackPayload(id: "payload-1"))

        let didPlaySourceItem = try await model.playSourceItem(item)
        let didPlayPayload = await model.playManualSonosPayload(Self.playbackPayload(id: "payload-2"))
        let didPlayQueuePayloads = await model.playManualSonosQueuePayloads(
            [
                Self.playbackPayload(id: "payload-3")
            ],
            startingTrackNumber: 1
        )

        #expect(!didPlaySourceItem)
        #expect(!didPlayPayload)
        #expect(!didPlayQueuePayloads)
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
    }

    @Test
    func cloudCommandModeSkipsAppleMusicSourcePlaybackProbe() async throws {
        let model = SonoicModel()
        model.useCloudCommandModeWithoutAvailableCloudContext()
        let previousProbeState = model.sonosMusicServiceProbeState
        let previousNowPlaying = model.nowPlaying
        let item = Self.sourceItem(
            playbackPayload: Self.playbackPayload(id: "apple-music-payload", service: .appleMusic),
            service: .appleMusic
        )

        let didPlay = try await model.playSourceItem(item)

        #expect(!didPlay)
        #expect(model.sonosMusicServiceProbeState == previousProbeState)
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
    }

    @Test
    func cloudCommandModeMarksPlaylistQueueUnavailableEvenWithManualHost() async {
        let model = SonoicModel()
        model.useCloudCommandModeWithoutAvailableCloudContext()
        model.manualSonosHost = "192.0.2.10"
        let parentItem = Self.appleMusicPlaylistItem()
        let trackItems = [
            Self.sourceItem(
                playbackPayload: Self.playbackPayload(id: "playlist-track-1", service: .appleMusic),
                service: .appleMusic
            )
        ]
        let previousNowPlaying = model.nowPlaying

        let canPlayQueue = model.canPlaySourcePlaylistQueue(parentItem: parentItem, trackItems: trackItems)
        let didPlayQueue = await model.playSourcePlaylistQueue(parentItem: parentItem, trackItems: trackItems)

        #expect(canPlayQueue == false)
        #expect(didPlayQueue == false)
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
    }

    @Test
    func cloudCommandModeBlocksPlaylistFallbackEvenWithManualHost() async throws {
        let model = SonoicModel()
        model.useCloudCommandModeWithoutAvailableCloudContext()
        model.manualSonosHost = "192.0.2.10"
        let playlistItem = Self.sourceItem(
            playbackPayload: Self.playbackPayload(id: "fallback-playlist", service: .genericStreaming),
            kind: .playlist
        )
        let previousNowPlaying = model.nowPlaying

        let didPlayFallback = try await model.playSourcePlaylistFallback(playlistItem)

        #expect(didPlayFallback == false)
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
    }

    @Test
    func cloudCommandModeBlocksFavoriteBackedPlaylistLANFallback() async {
        let model = SonoicModel()
        model.useCloudCommandModeWithoutAvailableCloudContext()
        model.manualSonosHost = "192.0.2.10"
        model.homeFavoritesState = .loaded(
            SonosFavoritesSnapshot(items: [Self.appleMusicPlaylistFavorite()])
        )
        let parentItem = Self.appleMusicPlaylistItem()
        let previousNowPlaying = model.nowPlaying

        let didPlayQueue = await model.playSourcePlaylistQueue(
            parentItem: parentItem,
            trackItems: [],
            startingAtIndex: nil
        )

        #expect(didPlayQueue == false)
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
    }

    @Test
    func cloudCommandModeBlocksManualQueueItemSeekEvenWithManualHost() async {
        let model = SonoicModel()
        model.useCloudCommandModeWithoutAvailableCloudContext()
        model.manualSonosHost = "192.0.2.10"
        model.queueState = .loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(id: "1", title: "One", artistName: nil, albumTitle: nil, artworkURL: nil, duration: nil),
                    SonosQueueItem(id: "2", title: "Two", artistName: nil, albumTitle: nil, artworkURL: nil, duration: nil)
                ],
                currentItemIndex: 0,
                sourceURI: "x-rincon-queue:RINCON_00000000000001400#0"
            )
        )
        let previousQueueState = model.queueState
        let previousNowPlaying = model.nowPlaying

        let didPlayQueueItem = await model.playManualSonosQueueItem(at: 2)

        #expect(didPlayQueueItem == false)
        #expect(model.queueState == previousQueueState)
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
    }

    @Test
    func cloudCommandModeBlocksLocalQueueMutations() async {
        let model = SonoicModel()
        model.useCloudCommandModeWithoutAvailableCloudContext()
        let snapshot = SonosQueueSnapshot(
            items: [
                SonosQueueItem(id: "1", title: "One", artistName: nil, albumTitle: nil, artworkURL: nil, duration: nil),
                SonosQueueItem(id: "2", title: "Two", artistName: nil, albumTitle: nil, artworkURL: nil, duration: nil)
            ],
            currentItemIndex: 0,
            sourceURI: "x-rincon-queue:RINCON_00000000000001400#0"
        )
        model.queueState = .loaded(snapshot)
        let previousQueueState = model.queueState

        model.queueOperationErrorDetail = nil
        let didClear = await model.clearQueue()
        #expect(!didClear)
        #expect(model.queueOperationErrorDetail == Self.cloudQueueMutationUnavailableDetail)

        model.queueOperationErrorDetail = nil
        let didRemove = await model.removeQueueItems(atOffsets: IndexSet(integer: 0))
        #expect(!didRemove)
        #expect(model.queueOperationErrorDetail == Self.cloudQueueMutationUnavailableDetail)

        model.queueOperationErrorDetail = nil
        let didMove = await model.moveQueueItems(fromOffsets: IndexSet(integer: 0), toOffset: 1)

        #expect(!didMove)
        #expect(model.queueState == previousQueueState)
        #expect(model.queueOperationErrorDetail == Self.cloudQueueMutationUnavailableDetail)
        #expect(model.queueDiagnostics.lastMutationErrorDetail == model.queueOperationErrorDetail)
    }

    @Test
    func cloudCommandModeWithoutCommandTargetBlocksLocalVolumeControls() async {
        let model = SonoicModel()
        model.useCloudCommandModeWithoutAvailableCloudContext()
        model.externalVolume = SonoicExternalControlState.Volume(level: 24, isMuted: false)
        let previousVolume = model.externalVolume

        let didSetVolume = await model.setManualSonosVolume(to: 80)
        await model.toggleManualSonosMute()

        #expect(!didSetVolume)
        #expect(model.externalVolume == previousVolume)
    }

    private static let cloudQueueMutationUnavailableDetail =
        "Queue edits are unavailable while Sonos Cloud command mode is active."

    private static func playbackPayload(
        id: String,
        service: SonosServiceDescriptor = .genericStreaming
    ) -> SonosPlayablePayload {
        SonosPlayablePayload(
            id: id,
            title: "Cloud First",
            subtitle: nil,
            artworkURL: nil,
            service: service,
            uri: "x-sonos-http:track-\(id).m4a",
            metadataXML: "<DIDL-Lite></DIDL-Lite>",
            kind: .item,
            launchMode: .direct,
            duration: 180
        )
    }

    private static func sourceItem(
        playbackPayload: SonosPlayablePayload,
        service: SonosServiceDescriptor = .genericStreaming,
        kind: SonoicSourceItem.Kind = .song
    ) -> SonoicSourceItem {
        SonoicSourceItem(
            id: "source-\(playbackPayload.id)",
            title: playbackPayload.title,
            subtitle: playbackPayload.subtitle,
            artworkURL: playbackPayload.artworkURL,
            artworkIdentifier: nil,
            service: service,
            origin: .library,
            kind: kind,
            playbackCapability: .sonosNative(playbackPayload),
            duration: playbackPayload.duration
        )
    }

    private static func appleMusicPlaylistItem() -> SonoicSourceItem {
        SonoicSourceItem.appleMusicMetadata(
            id: "playlist-1",
            title: "Cloud First Playlist",
            subtitle: "Sonoic",
            artworkURL: nil,
            kind: .playlist,
            origin: .library,
            catalogID: "playlist-1"
        )
    }

    private static func appleMusicPlaylistFavorite() -> SonosFavoriteItem {
        SonosFavoriteItem(
            id: "favorite-playlist-1",
            title: "Cloud First Playlist",
            subtitle: "Sonoic",
            artworkURL: nil,
            service: .appleMusic,
            playbackURI: "x-rincon-cpcontainer:1006206cplaylist%3aplaylist-1",
            playbackMetadataXML: "<item><upnp:class>object.container.playlistContainer</upnp:class></item>",
            kind: .collection
        )
    }

    private static func nowPlayingSnapshot(playbackState: SonosNowPlayingSnapshot.PlaybackState) -> SonosNowPlayingSnapshot {
        SonosNowPlayingSnapshot(
            title: "Cloud First",
            artistName: "Sonoic",
            albumTitle: "Invariant",
            sourceName: "Apple Music",
            playbackState: playbackState,
            elapsedTime: 10,
            duration: 180
        )
    }
}

private extension SonoicModel {
    func useCloudCommandModeWithoutAvailableCloudContext() {
        sonosControlAPIState = SonosControlAPIState(
            settings: SonosControlAPISettings(
                mode: .preferred,
                selectedHouseholdID: nil,
                selectedGroupID: nil
            ),
            authorizationStatus: .expired,
            lastErrorDetail: nil,
            lastCommandDescription: nil,
            lastUpdatedAt: nil
        )
    }
}
