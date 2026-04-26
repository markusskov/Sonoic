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

    private func appleMusicItem(
        title: String,
        subtitle: String?,
        kind: SonoicSourceItem.Kind
    ) -> SonoicSourceItem {
        SonoicSourceItem.appleMusicMetadata(
            id: "catalog-\(title)",
            title: title,
            subtitle: subtitle,
            artworkURL: nil,
            kind: kind,
            origin: .catalogSearch
        )
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
}
