import Foundation
import Testing
@testable import Sonoic

struct SonoicRecentPlayItemTests {
    @Test
    @MainActor
    func hidesServiceNameRowsFromHomeHistory() {
        let recentPlay = SonoicRecentPlayItem(
            id: "apple-music-service-title",
            title: "Apple Music",
            artistName: "Grimm Grimm",
            albumTitle: "Cliffhanger",
            sourceName: "Apple Music",
            artworkURL: nil,
            artworkIdentifier: nil,
            service: .appleMusic,
            lastPlayedAt: .now,
            playbackURI: "x-sonosapi-hls:song%3a1792083502?sid=204&sn=3",
            playbackMetadataXML: nil
        )

        #expect(!recentPlay.isVisibleInHomeHistory)
    }

    @Test
    @MainActor
    func keepsRealAppleMusicRowsVisible() {
        let recentPlay = SonoicRecentPlayItem(
            id: "cliffhanger",
            title: "Cliffhanger",
            artistName: "Grimm Grimm",
            albumTitle: "Cliffhanger",
            sourceName: "Apple Music",
            artworkURL: nil,
            artworkIdentifier: nil,
            service: .appleMusic,
            lastPlayedAt: .now,
            playbackURI: "x-sonosapi-hls:song%3a1792083502?sid=204&sn=3",
            playbackMetadataXML: nil
        )

        #expect(recentPlay.isVisibleInHomeHistory)
    }

    @Test
    @MainActor
    func recentAppleMusicCollectionsPreferLibraryRoute() {
        let recentPlay = SonoicRecentPlayItem(
            id: "playlist",
            title: "Chill",
            artistName: "Apple Music",
            albumTitle: nil,
            sourceName: "Apple Music",
            artworkURL: nil,
            artworkIdentifier: nil,
            service: .appleMusic,
            lastPlayedAt: .now,
            favoriteKind: .collection,
            sourceItemID: "library-playlist-id",
            appleMusicCatalogID: "catalog-playlist-id",
            appleMusicLibraryID: "library-playlist-id",
            sourceItemKindRawValue: SonoicSourceItem.Kind.playlist.rawValue
        )

        let sourceItem = SonoicSourceItem(recentPlay: recentPlay)

        #expect(sourceItem.sourceReference?.serviceID == SonosServiceDescriptor.appleMusic.id)
        #expect(sourceItem.sourceReference?.routedID(for: .recentPlay) == "library-playlist-id")
        #expect(sourceItem.sourceReference?.routedID(for: .catalogSearch) == "catalog-playlist-id")
    }

    @Test
    @MainActor
    func recentAppleMusicSourceItemsRecoverIDsFromPlaybackURI() {
        let recentPlay = SonoicRecentPlayItem(
            id: "legacy-playlist",
            title: "Chill",
            artistName: "Apple Music",
            albumTitle: nil,
            sourceName: "Apple Music",
            artworkURL: nil,
            artworkIdentifier: nil,
            service: .appleMusic,
            lastPlayedAt: .now,
            playbackURI: "x-rincon-cpcontainer:1006206cplaylist%3a12345?sid=204&sn=3",
            favoriteKind: .collection
        )

        let sourceItem = SonoicSourceItem(recentPlay: recentPlay)

        #expect(sourceItem.kind == .playlist)
        #expect(sourceItem.serviceItemID == "12345")
        #expect(sourceItem.sourceReference?.serviceID == SonosServiceDescriptor.appleMusic.id)
        #expect(sourceItem.sourceReference?.catalogID == "12345")
    }
}
