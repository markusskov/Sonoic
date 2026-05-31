import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicAppleMusicPlaybackPayloadResolverTests {
    private let resolver = SonoicAppleMusicPlaybackPayloadResolver()

    @Test
    func returnsExactCandidateForMatchingAppleMusicFavorite() throws {
        let item = appleMusicItem(
            title: "Sweet Jane",
            subtitle: "Garrett Kato • That Low and Lonesome Sound",
            kind: .song
        )
        let favorite = favorite(
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            service: .appleMusic,
            uri: "x-sonosapi-hls:song%3a123?sid=204",
            kind: .item
        )

        let candidate = try #require(resolver.candidates(for: item, favorites: [favorite]).first)

        #expect(candidate.confidence == .exact)
        #expect(candidate.payload.uri == favorite.playbackURI)
        #expect(candidate.payload.service == .appleMusic)
    }

    @Test
    func rejectsDifferentServiceFavorite() {
        let item = appleMusicItem(title: "Sweet Jane", subtitle: "Garrett Kato", kind: .song)
        let favorite = favorite(
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            service: .spotify,
            uri: "x-sonosapi-hls:song%3a123?sid=9",
            kind: .item
        )

        #expect(resolver.candidates(for: item, favorites: [favorite]).isEmpty)
    }

    @Test
    func rejectsSameTitleWithDifferentSubtitleWhenDetailsAreAvailable() {
        let item = appleMusicItem(title: "Intro", subtitle: "Artist One • Album One", kind: .song)
        let favorite = favorite(
            title: "Intro",
            subtitle: "Artist Two",
            service: .appleMusic,
            uri: "x-sonosapi-hls:song%3a456?sid=204",
            kind: .item
        )

        #expect(resolver.candidates(for: item, favorites: [favorite]).isEmpty)
    }

    @Test
    func returnsLikelyCandidateWhenSubtitleIsMissingButKindMatches() throws {
        let item = appleMusicItem(title: "Road Trip", subtitle: nil, kind: .playlist)
        let favorite = favorite(
            title: "Road Trip",
            subtitle: nil,
            service: .appleMusic,
            uri: "x-rincon-cpcontainer:1006206cplaylist%3a123?sid=204",
            kind: .collection
        )

        let candidate = try #require(resolver.candidates(for: item, favorites: [favorite]).first)

        #expect(candidate.confidence == .likely)
        #expect(candidate.payload.kind == .collection)
    }

    @Test
    func rejectsSongWhenSubtitleIsMissing() {
        let item = appleMusicItem(title: "Intro", subtitle: nil, kind: .song)
        let favorite = favorite(
            title: "Intro",
            subtitle: "Artist One",
            service: .appleMusic,
            uri: "x-sonosapi-hls:song%3a456?sid=204",
            kind: .item
        )

        #expect(resolver.candidates(for: item, favorites: [favorite]).isEmpty)
    }

    @Test
    func rejectsSongFavoriteWhenFavoriteSubtitleIsMissing() {
        let item = appleMusicItem(title: "Intro", subtitle: "Artist One • Album One", kind: .song)
        let favorite = favorite(
            title: "Intro",
            subtitle: nil,
            service: .appleMusic,
            uri: "x-sonosapi-hls:song%3a456?sid=204",
            kind: .item
        )

        #expect(resolver.candidates(for: item, favorites: [favorite]).isEmpty)
    }

    @Test
    func returnsExactCandidateWhenFavoritePayloadContainsCatalogID() throws {
        let item = appleMusicItem(
            title: "Suspicious Minds",
            subtitle: "Elvis Presley • From Elvis in Memphis",
            kind: .song,
            catalogID: "1440845464"
        )
        let favorite = favorite(
            title: "Suspicious Minds",
            subtitle: nil,
            service: .appleMusic,
            uri: "x-sonosapi-hls:song%3a1440845464?sid=204",
            kind: .item
        )

        let candidate = try #require(resolver.candidates(for: item, favorites: [favorite]).first)

        #expect(candidate.confidence == .exact)
        #expect(candidate.payload.uri == favorite.playbackURI)
    }

    @Test
    func rejectsFavoriteWithUnsafePlaybackURI() {
        let item = appleMusicItem(
            title: "Sweet Jane",
            subtitle: "Garrett Kato • That Low and Lonesome Sound",
            kind: .song
        )
        let favorite = favorite(
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            service: .appleMusic,
            uri: "x-rincon-queue:RINCON_123#0",
            kind: .item
        )

        #expect(resolver.candidates(for: item, favorites: [favorite]).isEmpty)
    }

    @Test
    func returnsPreparedFavoritePayload() throws {
        let item = appleMusicItem(
            title: "Sweet Jane",
            subtitle: "Garrett Kato • That Low and Lonesome Sound",
            kind: .song
        )
        let favorite = favorite(
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            service: .appleMusic,
            uri: "  x-sonosapi-hls:song%3a123?sid=204  ",
            kind: .item
        )

        let candidate = try #require(resolver.candidates(for: item, favorites: [favorite]).first)

        #expect(candidate.payload.uri == "x-sonosapi-hls:song%3a123?sid=204")
        #expect(candidate.payload.metadataXML == "<DIDL-Lite><item><dc:title>Sweet Jane</dc:title></item></DIDL-Lite>")
    }

    @Test
    func avoidsExactSongMatchWhenOnlyAlbumOverlaps() throws {
        let item = appleMusicItem(
            title: "Intro",
            subtitle: "Artist One • Shared Album",
            kind: .song
        )
        let favorite = favorite(
            title: "Intro",
            subtitle: "Shared Album",
            service: .appleMusic,
            uri: "x-sonosapi-hls:song%3a789?sid=204",
            kind: .item
        )

        let candidate = try #require(resolver.candidates(for: item, favorites: [favorite]).first)

        #expect(candidate.confidence == .likely)
    }

    @Test
    func rejectsSameTitleWithDifferentKindAndNoSubtitleMatch() {
        let item = appleMusicItem(title: "Road Trip", subtitle: "Garrett Kato", kind: .song)
        let favorite = favorite(
            title: "Road Trip",
            subtitle: "Road Trip Playlist",
            service: .appleMusic,
            uri: "x-rincon-cpcontainer:1006206cplaylist%3a123?sid=204",
            kind: .collection
        )

        #expect(resolver.candidates(for: item, favorites: [favorite]).isEmpty)
    }

    @Test
    func directPlayPurposeKeepsFavoriteGeneratedNativeSelectionOrder() throws {
        let item = purposeContractItem(nativePayloadID: "native-direct")
        let exactFavorite = verifiedAppleMusicFavorite()

        let favoriteModel = try model(favorites: [exactFavorite], includesAppleMusicPlaybackHint: true)
        let favoritePayload = try favoriteModel.appleMusicPlayablePayload(for: item, purpose: .directPlay)
        #expect(favoritePayload?.uri == exactFavorite.playbackURI)

        let generatedModel = try model(includesAppleMusicPlaybackHint: true)
        let generatedPayload = try generatedModel.appleMusicPlayablePayload(for: item, purpose: .directPlay)
        #expect(generatedPayload?.uri == catalogHLSURI())

        let nativeModel = try model(includesAppleMusicPlaybackHint: false)
        let nativePayload = try nativeModel.appleMusicPlayablePayload(for: item, purpose: .directPlay)
        #expect(nativePayload?.id == "native-direct")
    }

    @Test
    func queueEntryPurposePrefersCloudQueuePayloadThenFavoriteThenNative() throws {
        let item = purposeContractItem(nativePayloadID: "native-queue")
        let exactFavorite = verifiedAppleMusicFavorite()

        let generatedModel = try model(favorites: [exactFavorite], includesAppleMusicPlaybackHint: true)
        let generatedPayload = try generatedModel.appleMusicPlayablePayload(for: item, purpose: .queueEntry)
        #expect(generatedPayload?.uri == libraryTrackURI())

        let favoriteModel = try model(favorites: [exactFavorite], includesAppleMusicPlaybackHint: false)
        let favoritePayload = try favoriteModel.appleMusicPlayablePayload(for: item, purpose: .queueEntry)
        #expect(favoritePayload?.uri == exactFavorite.playbackURI)

        let nativeModel = try model(includesAppleMusicPlaybackHint: false)
        let nativePayload = try nativeModel.appleMusicPlayablePayload(for: item, purpose: .queueEntry)
        #expect(nativePayload?.id == "native-queue")
    }

    @Test
    func favoritePurposeUsesGeneratedPayloadOrVerifiedFavoriteOnly() throws {
        let item = purposeContractItem(nativePayloadID: "native-favorite")
        let verifiedFavorite = verifiedAppleMusicFavorite()
        let titleOnlyFavorite = titleOnlyAppleMusicFavorite()

        let generatedModel = try model(favorites: [verifiedFavorite], includesAppleMusicPlaybackHint: true)
        let generatedPayload = try generatedModel.appleMusicPlayablePayload(for: item, purpose: .favorite)
        #expect(generatedPayload?.uri == catalogHLSURI())

        let verifiedFavoriteModel = try model(favorites: [verifiedFavorite], includesAppleMusicPlaybackHint: false)
        let verifiedFavoritePayload = try verifiedFavoriteModel.appleMusicPlayablePayload(for: item, purpose: .favorite)
        #expect(verifiedFavoritePayload?.uri == verifiedFavorite.playbackURI)

        let titleOnlyFavoriteModel = try model(favorites: [titleOnlyFavorite], includesAppleMusicPlaybackHint: false)
        let titleOnlyPayload = try titleOnlyFavoriteModel.appleMusicPlayablePayload(for: item, purpose: .favorite)
        #expect(titleOnlyPayload == nil)
    }

    @Test
    func favoritePurposeBuildsGeneratedPlaylistContainerPayloadFromPlaybackHint() throws {
        let item = appleMusicItem(
            title: "Road Songs",
            subtitle: "Apple Music",
            kind: .playlist,
            catalogID: "p.abc123"
        )
        let model = try model(includesAppleMusicPlaybackHint: true)

        let resolvedPayload = try model.appleMusicPlayablePayload(for: item, purpose: .favorite)
        let payload = try #require(resolvedPayload)

        #expect(payload.kind == .collection)
        #expect(payload.uri == "x-rincon-cpcontainer:1006206cplaylist%3ap.abc123?sid=204&flags=8300&sn=3")
        #expect(payload.metadataXML?.contains("<container id=\"playlist:p.abc123\"") == true)
    }

    @Test
    func favoriteToggleSavesLibraryPlaylistAsLocalHomeFavorite() async throws {
        let item = appleMusicItem(
            title: "Markus Mix",
            subtitle: "Apple Music",
            kind: .playlist,
            catalogID: nil,
            libraryID: "p.library-only"
        )
        let model = try model(includesAppleMusicPlaybackHint: true)
        model.manualSonosHost = "192.0.2.10"

        let result = try await model.toggleAppleMusicSonosFavorite(for: item)
        guard case .added(let objectID) = result else {
            Issue.record("Expected local favorite to be added.")
            return
        }

        let favorite = try #require(model.homeFavoritesState.snapshot?.items.first)
        let homeItem = SonoicSourceItem(favorite: favorite)
        #expect(model.isLocalAppleMusicFavoriteObjectID(objectID))
        #expect(favorite.id == objectID)
        #expect(favorite.kind == .collection)
        #expect(favorite.playbackURI == "x-sonoic-apple-music-libraryplaylist:p.library-only")
        #expect(homeItem.origin == .favorite)
        #expect(homeItem.kind == .playlist)
        #expect(homeItem.sourceReference?.catalogID == nil)
        #expect(homeItem.sourceReference?.libraryID == "p.library-only")
        #expect(model.appleMusicFavoriteObjectID(for: item) == objectID)

        let removeResult = try await model.toggleAppleMusicSonosFavorite(for: item)
        guard case .removed = removeResult else {
            Issue.record("Expected local favorite to be removed.")
            return
        }
        #expect(model.homeFavoritesState == .empty)
        #expect(model.appleMusicFavoriteObjectID(for: item) == nil)
    }

    @Test
    func metadataPurposeKeepsFavoriteGeneratedNativeSelectionOrder() throws {
        let item = purposeContractItem(nativePayloadID: "native-metadata")
        let exactFavorite = verifiedAppleMusicFavorite()

        let favoriteModel = try model(favorites: [exactFavorite], includesAppleMusicPlaybackHint: true)
        let favoritePayload = try favoriteModel.appleMusicPlayablePayload(for: item, purpose: .metadata)
        #expect(favoritePayload?.uri == exactFavorite.playbackURI)

        let generatedModel = try model(includesAppleMusicPlaybackHint: true)
        let generatedPayload = try generatedModel.appleMusicPlayablePayload(for: item, purpose: .metadata)
        #expect(generatedPayload?.uri == catalogHLSURI())

        let nativeModel = try model(includesAppleMusicPlaybackHint: false)
        let nativePayload = try nativeModel.appleMusicPlayablePayload(for: item, purpose: .metadata)
        #expect(nativePayload?.id == "native-metadata")
    }

    private func appleMusicItem(
        title: String,
        subtitle: String?,
        kind: SonoicSourceItem.Kind,
        catalogID: String? = nil,
        libraryID: String? = nil,
        nativePayload: SonosPlayablePayload? = nil
    ) -> SonoicSourceItem {
        var item = SonoicSourceItem.appleMusicMetadata(
            id: catalogID ?? libraryID ?? "catalog-\(title)",
            title: title,
            subtitle: subtitle,
            artworkURL: nil,
            kind: kind,
            origin: .catalogSearch,
            catalogID: catalogID,
            libraryID: libraryID
        )

        if let nativePayload {
            item.playbackCapability = .sonosNative(nativePayload)
        }

        return item
    }

    private func favorite(
        title: String,
        subtitle: String?,
        service: SonosServiceDescriptor,
        uri: String,
        kind: SonosFavoriteItem.Kind
    ) -> SonosFavoriteItem {
        SonosFavoriteItem(
            id: "favorite-\(title)-\(service.id)",
            title: title,
            subtitle: subtitle,
            artworkURL: nil,
            service: service,
            playbackURI: uri,
            playbackMetadataXML: "<DIDL-Lite><item><dc:title>\(title)</dc:title></item></DIDL-Lite>",
            kind: kind
        )
    }

    private func purposeContractItem(nativePayloadID: String) -> SonoicSourceItem {
        appleMusicItem(
            title: "Sweet Jane",
            subtitle: "Garrett Kato • That Low and Lonesome Sound",
            kind: .song,
            catalogID: appleMusicContractCatalogID,
            libraryID: appleMusicContractLibraryID,
            nativePayload: playbackPayload(
                id: nativePayloadID,
                uri: "x-sonos-http:\(nativePayloadID).m4a"
            )
        )
    }

    private func verifiedAppleMusicFavorite() -> SonosFavoriteItem {
        favorite(
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            service: .appleMusic,
            uri: "x-sonosapi-hls:song%3a\(appleMusicContractCatalogID)?sid=204",
            kind: .item
        )
    }

    private func titleOnlyAppleMusicFavorite() -> SonosFavoriteItem {
        favorite(
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            service: .appleMusic,
            uri: "x-sonosapi-hls:song%3aother-song?sid=204",
            kind: .item
        )
    }

    private func model(
        favorites: [SonosFavoriteItem] = [],
        includesAppleMusicPlaybackHint: Bool
    ) throws -> SonoicModel {
        let suiteName = "SonoicAppleMusicPlaybackPayloadResolverTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let model = SonoicModel(
            settingsStore: SonoicSettingsStore(userDefaults: userDefaults),
            startInitialSonosControlAPICloudRefresh: false
        )
        model.homeFavoritesState = .loaded(SonosFavoritesSnapshot(items: favorites))

        if includesAppleMusicPlaybackHint {
            model.sonosMusicServiceProbeState = SonosMusicServiceProbeState(
                status: .loaded,
                snapshot: appleMusicPlaybackHintSnapshot()
            )
        }

        return model
    }

    private func appleMusicPlaybackHintSnapshot() -> SonosMusicServiceProbeSnapshot {
        // The probe snapshot represents Sonos-observed Apple Music account serials,
        // so generated payloads stay Sonos-owned.
        return SonosMusicServiceProbeSnapshot(
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
                value: catalogHLSURI(),
                origin: .currentURI
            ),
            SonosMusicServiceObservedValue(
                value: libraryTrackURI(),
                origin: .trackURI
            ),
        ])
    }

    private func playbackPayload(id: String, uri: String) -> SonosPlayablePayload {
        SonosPlayablePayload(
            id: id,
            title: "Native \(id)",
            subtitle: "Apple Music",
            artworkURL: nil,
            service: .appleMusic,
            uri: uri,
            metadataXML: "<DIDL-Lite></DIDL-Lite>",
            kind: .item
        )
    }

    private var appleMusicContractCatalogID: String {
        "1440857781"
    }

    private var appleMusicContractLibraryID: String {
        "i.BOVNeOxU6BVbp8"
    }

    private func catalogHLSURI() -> String {
        "x-sonosapi-hls:song%3a\(appleMusicContractCatalogID)?sid=204&sn=3"
    }

    private func libraryTrackURI() -> String {
        "x-sonos-http:librarytrack%3a\(appleMusicContractLibraryID).m4p?sid=204&flags=8232&sn=7"
    }
}
