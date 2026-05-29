import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicModelManualHostTransportTests {
    @Test(arguments: [SonosControlAPIMode.fallback, .preferred])
    func cloudCommandModesIgnoreManualHostForTransportAvailability(
        mode: SonosControlAPIMode
    ) throws {
        let model = try makeModel(savedManualHost: "192.0.2.10")
        model.useCloudCommandMode(mode)

        #expect(model.hasManualSonosHost)
        #expect(model.hasActiveSonosControlTarget == false)
        #expect(model.canControlManualPlayback == false)
        #expect(model.allowsLocalManualTransportCommands == false)
    }

    @Test
    func localModeUsesManualHostForTransportAvailability() throws {
        let model = try makeModel(savedManualHost: "192.0.2.10")
        model.sonosControlAPIState = .disabled

        #expect(model.hasManualSonosHost)
        #expect(model.hasActiveSonosControlTarget)
        #expect(model.canControlManualPlayback)
        #expect(model.allowsLocalManualTransportCommands)
    }

    @Test(arguments: [SonosControlAPIMode.fallback, .preferred])
    func cloudCommandModesBlockDirectPayloadLANFallbackEvenWithManualHost(
        mode: SonosControlAPIMode
    ) async throws {
        let model = try makeModel(savedManualHost: "192.0.2.10")
        model.useCloudCommandMode(mode)
        model.nowPlaying = Self.nowPlayingSnapshot()
        model.queueState = .loaded(Self.queueSnapshot())
        let previousNowPlaying = model.nowPlaying
        let previousQueueState = model.queueState

        let didPlay = await model.playManualSonosPayload(Self.playbackPayload(id: "direct-payload"))

        #expect(didPlay == false)
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.queueState == previousQueueState)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
        #expect(model.manualRecentPlaybackContextPayload == nil)
        #expect(model.recentPlays.isEmpty)
    }

    @Test(arguments: [SonosControlAPIMode.fallback, .preferred])
    func cloudCommandModesBlockQueuePayloadLANFallbackEvenWithManualHost(
        mode: SonosControlAPIMode
    ) async throws {
        let model = try makeModel(savedManualHost: "192.0.2.10")
        model.useCloudCommandMode(mode)
        model.nowPlaying = Self.nowPlayingSnapshot()
        model.queueState = .loaded(Self.queueSnapshot())
        let previousNowPlaying = model.nowPlaying
        let previousQueueState = model.queueState

        let didPlay = await model.playManualSonosQueuePayloads(
            [
                Self.playbackPayload(id: "queue-payload-1"),
                Self.playbackPayload(id: "queue-payload-2")
            ],
            startingTrackNumber: 2
        )

        #expect(didPlay == false)
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.queueState == previousQueueState)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
        #expect(model.manualRecentPlaybackContextPayload == nil)
        #expect(model.recentPlays.isEmpty)
    }

    @Test(arguments: [SonosControlAPIMode.fallback, .preferred])
    func cloudCommandModesBlockSingleItemFavoriteLANFallbackEvenWithManualHost(
        mode: SonosControlAPIMode
    ) async throws {
        let model = try makeModel(savedManualHost: "192.0.2.10")
        model.useCloudCommandMode(mode)
        model.nowPlaying = Self.nowPlayingSnapshot()
        model.queueState = .loaded(Self.queueSnapshot())
        let previousNowPlaying = model.nowPlaying
        let previousQueueState = model.queueState

        let didPlay = await model.playManualSonosFavorite(Self.singleItemFavorite())

        #expect(didPlay == false)
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.queueState == previousQueueState)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
        #expect(model.manualRecentPlaybackContextPayload == nil)
        #expect(model.recentPlays.isEmpty)
    }

    @Test(arguments: [SonosControlAPIMode.fallback, .preferred])
    func cloudCommandModesBlockCollectionFavoriteLANFallbackEvenWithManualHost(
        mode: SonosControlAPIMode
    ) async throws {
        let model = try makeModel(savedManualHost: "192.0.2.10")
        model.useCloudCommandMode(mode)
        model.nowPlaying = Self.nowPlayingSnapshot()
        model.queueState = .loaded(Self.queueSnapshot())
        let previousNowPlaying = model.nowPlaying
        let previousQueueState = model.queueState

        let didPlay = await model.playManualSonosFavorite(Self.collectionFavorite())

        #expect(didPlay == false)
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.queueState == previousQueueState)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
        #expect(model.manualRecentPlaybackContextPayload == nil)
        #expect(model.recentPlays.isEmpty)
    }

    private func makeModel(savedManualHost: String = "") throws -> SonoicModel {
        let suiteName = "SonoicModelManualHostTransportTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = SonoicSettingsStore(userDefaults: userDefaults)
        store.saveManualSonosHost(savedManualHost)
        return SonoicModel(
            settingsStore: store,
            startInitialSonosControlAPICloudRefresh: false
        )
    }

    private static func playbackPayload(id: String) -> SonosPlayablePayload {
        SonosPlayablePayload(
            id: id,
            title: "Cloud First",
            subtitle: nil,
            artworkURL: nil,
            service: .appleMusic,
            uri: "x-sonos-http:track-\(id).m4a",
            metadataXML: "<DIDL-Lite></DIDL-Lite>",
            kind: .item,
            launchMode: .direct,
            duration: 180
        )
    }

    private static func queueSnapshot() -> SonosQueueSnapshot {
        SonosQueueSnapshot(
            items: [
                SonosQueueItem(
                    id: "item-1",
                    title: "One",
                    artistName: nil,
                    albumTitle: nil,
                    artworkURL: nil,
                    duration: 180
                )
            ],
            currentItemIndex: 0,
            sourceURI: "x-rincon-queue:RINCON_00000000000001400#0"
        )
    }

    private static func nowPlayingSnapshot() -> SonosNowPlayingSnapshot {
        SonosNowPlayingSnapshot(
            title: "Cloud First",
            artistName: "Sonoic",
            albumTitle: "Manual Transport",
            sourceName: "Apple Music",
            playbackState: .playing,
            elapsedTime: 12,
            duration: 180
        )
    }

    private static func singleItemFavorite() -> SonosFavoriteItem {
        SonosFavoriteItem(
            id: "favorite-track",
            title: "Cloud First Track",
            subtitle: "Sonoic",
            artworkURL: nil,
            service: .appleMusic,
            playbackURI: "x-sonos-http:favorite-track.m4a",
            playbackMetadataXML: "<DIDL-Lite></DIDL-Lite>",
            kind: .item
        )
    }

    private static func collectionFavorite() -> SonosFavoriteItem {
        SonosFavoriteItem(
            id: "favorite-playlist",
            title: "Cloud First Playlist",
            subtitle: "Sonoic",
            artworkURL: nil,
            service: .appleMusic,
            playbackURI: "x-rincon-cpcontainer:1006206cplaylist%3aplaylist-1",
            playbackMetadataXML: "<item><upnp:class>object.container.playlistContainer</upnp:class></item>",
            kind: .collection
        )
    }
}

private extension SonoicModel {
    func useCloudCommandMode(_ mode: SonosControlAPIMode) {
        sonosControlAPIState = SonosControlAPIState(
            settings: SonosControlAPISettings(
                mode: mode,
                selectedHouseholdID: "household-1",
                selectedGroupID: nil
            ),
            authorizationStatus: .expired,
            lastErrorDetail: nil,
            lastCommandDescription: nil,
            lastUpdatedAt: nil
        )
    }
}
