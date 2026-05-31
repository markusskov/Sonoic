import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicSourceSearchSessionTests {
    @Test
    func filtersVisibleItemsBySelectedSource() {
        let appleMusicSource = source(.appleMusic)
        let spotifySource = source(.spotify)
        let appleMusicSong = item(
            id: "apple-song",
            title: "Whiskey In the Jar",
            kind: .song,
            service: .appleMusic
        )
        let spotifySong = item(
            id: "spotify-song",
            title: "Nothing Else Matters",
            kind: .song,
            service: .spotify
        )
        let session = SonoicSourceSearchSessionState(
            query: "metallica",
            selectedServiceID: SonosServiceDescriptor.appleMusic.id,
            scope: .all,
            lastSubmittedQuery: "metallica"
        )

        let visibleItems = session.visibleItems(
            in: [
                SonosServiceDescriptor.appleMusic.id: SonoicSourceSearchState(
                    query: "metallica",
                    service: .appleMusic,
                    items: [appleMusicSong],
                    status: .loaded
                ),
                SonosServiceDescriptor.spotify.id: SonoicSourceSearchState(
                    query: "metallica",
                    service: .spotify,
                    items: [spotifySong],
                    status: .loaded
                ),
            ],
            sources: [appleMusicSource, spotifySource]
        )

        #expect(visibleItems == [appleMusicSong])
    }

    @Test
    func selectedSourceFiltersSubmittedSearchSources() {
        let appleMusicSource = source(.appleMusic)
        let spotifySource = source(.spotify)
        let session = SonoicSourceSearchSessionState(
            query: "metallica",
            selectedServiceID: SonosServiceDescriptor.spotify.id,
            scope: .all,
            lastSubmittedQuery: "metallica"
        )

        #expect(session.filteredSources(from: [appleMusicSource, spotifySource]) == [spotifySource])
    }

    @Test
    func filtersVisibleItemsByKindWithoutClearingQuery() {
        let appleMusicSource = source(.appleMusic)
        let song = item(id: "song", title: "Enter Sandman", kind: .song, service: .appleMusic)
        let album = item(id: "album", title: "Metallica", kind: .album, service: .appleMusic)
        let session = SonoicSourceSearchSessionState(
            query: "metallica",
            selectedServiceID: SonosServiceDescriptor.appleMusic.id,
            scope: .albums,
            lastSubmittedQuery: "metallica"
        )

        let visibleItems = session.visibleItems(
            in: [
                SonosServiceDescriptor.appleMusic.id: SonoicSourceSearchState(
                    query: "metallica",
                    service: .appleMusic,
                    items: [song, album],
                    status: .loaded
                ),
            ],
            sources: [appleMusicSource]
        )

        #expect(visibleItems == [album])
        #expect(session.query == "metallica")
        #expect(session.lastSubmittedQuery == "metallica")
    }

    @Test
    func submittedQueryIsActiveOnlyWhileCurrentQueryMatches() {
        var session = SonoicSourceSearchSessionState(
            query: "metallica",
            selectedServiceID: SonosServiceDescriptor.appleMusic.id,
            scope: .all,
            lastSubmittedQuery: "metallica"
        )

        #expect(session.hasActiveSubmittedQuery)

        session.query = ""
        #expect(!session.hasActiveSubmittedQuery)

        session.query = "metal"
        #expect(!session.hasActiveSubmittedQuery)
    }

    @Test
    func reportsMetadataOnlyItemsAsNotPlayable() {
        let metadataOnlyItem = item(
            id: "metadata-only",
            title: "Stressed Out",
            kind: .song,
            service: .appleMusic
        )

        #expect(!metadataOnlyItem.playbackCapability.canPlay)
    }

    @Test
    func nonAppleSonosNativeItemsAreUnavailableForBetaSourcePlayback() async throws {
        let model = try makeModel(savedManualHost: "192.0.2.10")
        let payload = playablePayload(service: .spotify)
        let spotifyItem = item(
            id: "spotify-native",
            title: "Sweet Jane",
            kind: .song,
            service: .spotify,
            playbackCapability: .sonosNative(payload)
        )
        let previousNowPlaying = model.nowPlaying

        #expect(!model.canPlaySourceItem(spotifyItem))
        expectUnsupportedBetaSourcePlayback {
            _ = try model.sourcePlayablePayload(for: spotifyItem, purpose: .directPlay)
        }
        await expectUnsupportedBetaSourcePlayback {
            _ = try await model.playSourceItem(spotifyItem)
        }
        #expect(model.nowPlaying == previousNowPlaying)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
        #expect(model.manualRecentPlaybackContextPayload == nil)
        #expect(model.recentPlays.isEmpty)
    }

    @Test
    func nonAppleMetadataOnlyItemsRemainNonPlayable() throws {
        let model = try makeModel(savedManualHost: "192.0.2.10")
        let spotifyItem = item(
            id: "spotify-metadata",
            title: "Sweet Jane",
            kind: .song,
            service: .spotify
        )

        #expect(!model.canPlaySourceItem(spotifyItem))
    }

    @Test
    func explainsWhySourcePlaybackIsUnavailable() throws {
        let model = try makeModel()
        let appleMusicItem = item(
            id: "apple-native",
            title: "Fade Into You",
            kind: .song,
            service: .appleMusic,
            playbackCapability: .sonosNative(playablePayload(service: .appleMusic))
        )
        let metadataOnlyItem = item(
            id: "metadata-only",
            title: "Stressed Out",
            kind: .song,
            service: .appleMusic
        )
        let spotifyItem = item(
            id: "spotify-native",
            title: "Sweet Jane",
            kind: .song,
            service: .spotify,
            playbackCapability: .sonosNative(playablePayload(service: .spotify))
        )

        #expect(
            model.sourcePlaybackUnavailableDetail(for: appleMusicItem) ==
                "Choose a Sonos room before starting playback from Sonoic."
        )
        #expect(
            model.sourcePlaybackUnavailableDetail(for: metadataOnlyItem) ==
                "This item does not have a Sonos playback payload yet."
        )
        #expect(model.sourcePlaybackUnavailableDetail(for: spotifyItem)?.contains("Apple Music") == true)

        model.sonosControlAPIState = SonosControlAPIState(
            settings: SonosControlAPISettings(
                mode: .preferred,
                selectedHouseholdID: "household-1",
                selectedGroupID: "group-1"
            ),
            authorizationStatus: .expired,
            lastErrorDetail: nil,
            lastCommandDescription: nil,
            lastUpdatedAt: nil
        )

        #expect(
            model.sourcePlaybackUnavailableDetail(for: appleMusicItem) ==
                "Reconnect Sonos in Settings before starting playback from Sonoic."
        )
    }

    @Test
    func availableSourcePlaybackHasNoUnavailableDetail() throws {
        let model = try makeModel(savedManualHost: "192.0.2.10")
        let appleMusicItem = item(
            id: "apple-native",
            title: "Fade Into You",
            kind: .song,
            service: .appleMusic,
            playbackCapability: .sonosNative(playablePayload(service: .appleMusic))
        )

        #expect(model.canPlaySourceItem(appleMusicItem))
        #expect(model.sourcePlaybackUnavailableDetail(for: appleMusicItem) == nil)
    }

    @Test
    func appleMusicSearchSongsWithQueuePayloadArePlayableThroughSonosCloud() throws {
        let model = try makeModel(
            sonosOAuthConfiguration: sonosOAuthConfiguration()
        )
        model.sonosControlAPIState = SonosControlAPIState(
            settings: SonosControlAPISettings(
                mode: .preferred,
                selectedHouseholdID: "household-1",
                selectedGroupID: "group-1"
            ),
            authorizationStatus: .ready,
            lastErrorDetail: nil,
            lastCommandDescription: nil,
            lastUpdatedAt: nil
        )
        model.sonosMusicServiceProbeState = SonosMusicServiceProbeState(
            status: .loaded,
            snapshot: appleMusicTrackOnlyPlaybackHintSnapshot()
        )
        let searchSong = appleMusicSearchSong()

        let directPayload = try model.sourcePlayablePayload(for: searchSong, purpose: .directPlay)
        let queuePayloadCandidate = try model.sourcePlayablePayload(for: searchSong, purpose: .queueEntry)
        let queuePayload = try #require(queuePayloadCandidate)

        #expect(directPayload == nil)
        #expect(queuePayload.uri == "x-sonosapi-hls-static:song%3a1440857781?sid=204&flags=0&sn=7")
        #expect(model.canPlaySourceItem(searchSong))
        #expect(model.sourcePlaybackUnavailableDetail(for: searchSong) == nil)
    }

    @Test
    func appleMusicSearchSongsAreEnabledBeforePlaybackHintRefresh() throws {
        let model = try makeModel(
            savedManualHost: "192.0.2.10",
            sonosOAuthConfiguration: sonosOAuthConfiguration()
        )
        model.sonosControlAPIState = SonosControlAPIState(
            settings: SonosControlAPISettings(
                mode: .preferred,
                selectedHouseholdID: "household-1",
                selectedGroupID: "group-1"
            ),
            authorizationStatus: .ready,
            lastErrorDetail: nil,
            lastCommandDescription: nil,
            lastUpdatedAt: nil
        )
        let searchSong = appleMusicSearchSong()

        #expect(try model.sourcePlayablePayload(for: searchSong, purpose: .directPlay) == nil)
        #expect(try model.sourcePlayablePayload(for: searchSong, purpose: .queueEntry) == nil)
        #expect(model.canPlaySourceItem(searchSong))
        #expect(model.sourcePlaybackUnavailableDetail(for: searchSong) == nil)
    }

    @Test
    func homeSourcesOfferOnlyAppleMusicAsSetupSource() throws {
        let model = try makeModel()

        #expect(model.homeSources.map(\.service) == [.appleMusic])
        #expect(model.homeSources.map(\.status) == [.availableForSetup])
    }

    @Test
    func homeSourcesKeepNonAppleServicesVisibleWhenObservedThroughSonos() throws {
        let model = try makeModel()
        model.nowPlaying = SonosNowPlayingSnapshot(
            title: "Sweet Jane",
            artistName: "Garrett Kato",
            albumTitle: nil,
            sourceName: "Spotify",
            playbackState: .playing
        )

        let sources = model.homeSources
        let spotifySource = try #require(sources.first { $0.service == .spotify })

        #expect(sources.map(\.service) == [.spotify, .appleMusic])
        #expect(spotifySource.status == .visibleThroughSonos)
        #expect(spotifySource.detailText == "Playing now")
    }

    @Test
    func updatingSameQueryPreservesCachedResults() throws {
        let model = try makeModel()
        let appleMusicSource = source(.appleMusic)
        let cachedItem = item(
            id: "cached-song",
            title: "One",
            kind: .song,
            service: .appleMusic
        )
        let lastUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)

        model.sourceSearchStates[SonosServiceDescriptor.appleMusic.id] = SonoicSourceSearchState(
            query: "Metallica",
            service: .appleMusic,
            items: [cachedItem],
            status: .loaded,
            lastUpdatedAt: lastUpdatedAt
        )

        model.updateSourceSearchQuery("metallica", for: appleMusicSource)

        let state = model.sourceSearchState(for: appleMusicSource)
        #expect(state.items == [cachedItem])
        #expect(state.status == .loaded)
        #expect(state.lastUpdatedAt == lastUpdatedAt)
    }

    @Test
    func updatingNewQueryClearsCachedResults() throws {
        let model = try makeModel()
        let appleMusicSource = source(.appleMusic)
        let cachedItem = item(
            id: "cached-song",
            title: "One",
            kind: .song,
            service: .appleMusic
        )

        model.sourceSearchStates[SonosServiceDescriptor.appleMusic.id] = SonoicSourceSearchState(
            query: "Metallica",
            service: .appleMusic,
            items: [cachedItem],
            status: .loaded,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        model.updateSourceSearchQuery("Nirvana", for: appleMusicSource)

        let state = model.sourceSearchState(for: appleMusicSource)
        #expect(state.items.isEmpty)
        #expect(state.status == .idle)
        #expect(state.lastUpdatedAt == nil)
    }

    private func makeModel(
        savedManualHost: String? = nil,
        sonosOAuthConfiguration: SonosOAuthConfiguration = .load()
    ) throws -> SonoicModel {
        let suiteName = "SonoicSourceSearchSessionTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = SonoicSettingsStore(userDefaults: userDefaults)
        if let savedManualHost {
            store.saveManualSonosHost(savedManualHost)
        }
        return SonoicModel(
            settingsStore: store,
            sonosOAuthConfiguration: sonosOAuthConfiguration,
            startInitialSonosControlAPICloudRefresh: false
        )
    }

    private func sonosOAuthConfiguration() throws -> SonosOAuthConfiguration {
        SonosOAuthConfiguration(
            clientID: "client-id",
            redirectURI: "https://sonoic.test/callback",
            callbackScheme: "sonoic",
            tokenExchangeURL: try fixtureURL("https://sonoic.test/api/token"),
            tokenRefreshURL: nil,
            authorizationEndpoint: try fixtureURL("https://api.sonos.com/login/v3/oauth"),
            scopes: ["playback-control-all"],
            cloudQueueCreateURL: try fixtureURL("https://sonoic.test/api/sonos/cloud-queues")
        )
    }

    private func fixtureURL(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    private func source(_ service: SonosServiceDescriptor) -> SonoicSource {
        SonoicSource(
            service: service,
            favoriteCount: 0,
            collectionCount: 0,
            recentCount: 0,
            isCurrent: false
        )
    }

    private func item(
        id: String,
        title: String,
        kind: SonoicSourceItem.Kind,
        service: SonosServiceDescriptor,
        playbackCapability: SonoicPlaybackCapability = .metadataOnly
    ) -> SonoicSourceItem {
        SonoicSourceItem(
            id: id,
            title: title,
            subtitle: service.name,
            artworkURL: nil,
            artworkIdentifier: nil,
            service: service,
            origin: .catalogSearch,
            kind: kind,
            playbackCapability: playbackCapability
        )
    }

    private func playablePayload(service: SonosServiceDescriptor) -> SonosPlayablePayload {
        SonosPlayablePayload(
            id: "payload",
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            artworkURL: nil,
            service: service,
            uri: service.kind == .appleMusic
                ? "x-sonos-http:apple-music-track.m4a"
                : "x-sonos-spotify:spotify%3atrack%3a1",
            metadataXML: nil
        )
    }

    private func appleMusicSearchSong() -> SonoicSourceItem {
        SonoicSourceItem.appleMusicMetadata(
            id: "1440857781",
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            artworkURL: nil,
            kind: .song,
            origin: .catalogSearch,
            catalogID: "1440857781",
            duration: 214
        )
    }

    private func appleMusicTrackOnlyPlaybackHintSnapshot() -> SonosMusicServiceProbeSnapshot {
        SonosMusicServiceProbeSnapshot(
            observedAt: Date(timeIntervalSince1970: 0),
            serviceListVersion: nil,
            services: [
                SonosMusicServiceDescriptor(
                    id: "204",
                    name: "Apple Music",
                    uri: nil,
                    secureURI: nil,
                    containerType: nil,
                    capabilities: nil,
                    authPolicy: nil,
                    presentationMapURI: nil,
                    stringsURI: nil
                ),
            ],
            accounts: []
        ).includingObservedAccounts(from: [
            SonosMusicServiceObservedValue(
                value: "x-sonos-http:librarytrack%3aexample.m4p?sid=204&flags=8232&sn=7",
                origin: .trackURI
            ),
        ])
    }

    private func expectUnsupportedBetaSourcePlayback(
        _ action: () throws -> Void
    ) {
        do {
            try action()
            Issue.record("Expected unsupported beta source playback to fail.")
        } catch let error as SonoicSourceAdapterError {
            #expect(error.localizedDescription.contains("Apple Music"))
        } catch {
            Issue.record("Expected SonoicSourceAdapterError, got \(error).")
        }
    }

    private func expectUnsupportedBetaSourcePlayback(
        _ action: () async throws -> Void
    ) async {
        do {
            try await action()
            Issue.record("Expected unsupported beta source playback to fail.")
        } catch let error as SonoicSourceAdapterError {
            #expect(error.localizedDescription.contains("Apple Music"))
        } catch {
            Issue.record("Expected SonoicSourceAdapterError, got \(error).")
        }
    }
}
