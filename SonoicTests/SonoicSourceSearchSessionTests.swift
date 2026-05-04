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
    func nonAppleSonosNativeItemsRemainPlayable() throws {
        let model = SonoicModel()
        let payload = playablePayload(service: .spotify)
        let spotifyItem = item(
            id: "spotify-native",
            title: "Sweet Jane",
            kind: .song,
            service: .spotify,
            playbackCapability: .sonosNative(payload)
        )

        #expect(model.canPlaySourceItem(spotifyItem))
        #expect(try model.sourcePlayablePayload(for: spotifyItem, purpose: .directPlay) == payload)
    }

    @Test
    func nonAppleMetadataOnlyItemsRemainNonPlayable() {
        let model = SonoicModel()
        let spotifyItem = item(
            id: "spotify-metadata",
            title: "Sweet Jane",
            kind: .song,
            service: .spotify
        )

        #expect(!model.canPlaySourceItem(spotifyItem))
    }

    @Test
    func updatingSameQueryPreservesCachedResults() {
        let model = SonoicModel()
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
    func updatingNewQueryClearsCachedResults() {
        let model = SonoicModel()
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
            uri: "x-sonos-spotify:spotify%3atrack%3a1",
            metadataXML: nil
        )
    }
}
