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
}
