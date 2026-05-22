import Testing
@testable import Sonoic

@MainActor
struct SonosControlAPIQueueItemIDBuilderTests {
    @Test
    func clampsBaseIDToSonosLimit() {
        let maximumLength = SonoicSonosControlAPIQueueItemIDBuilder.maximumLength
        let id = SonoicSonosControlAPIQueueItemIDBuilder.uniqueID(
            index: 0,
            objectID: String(repeating: "a", count: 160),
            itemID: "track-1",
            usedIDs: []
        )

        #expect(id.count == maximumLength)
    }

    @Test
    func suffixesCollisionInsideSonosLimit() {
        let maximumLength = SonoicSonosControlAPIQueueItemIDBuilder.maximumLength
        let baseID = SonoicSonosControlAPIQueueItemIDBuilder.uniqueID(
            index: 0,
            objectID: String(repeating: "a", count: 160),
            itemID: "track-1",
            usedIDs: []
        )

        let duplicateID = SonoicSonosControlAPIQueueItemIDBuilder.uniqueID(
            index: 0,
            objectID: String(repeating: "a", count: 160),
            itemID: "track-1",
            usedIDs: [baseID]
        )

        #expect(duplicateID != baseID)
        #expect(duplicateID.hasSuffix("-1"))
        #expect(duplicateID.count == maximumLength)
    }

    @Test
    func keepsTryingUntilUnusedCollisionSuffix() {
        let baseID = SonoicSonosControlAPIQueueItemIDBuilder.uniqueID(
            index: 1,
            objectID: "song:abc",
            itemID: "track",
            usedIDs: []
        )
        let firstDuplicate = SonoicSonosControlAPIQueueItemIDBuilder.uniqueID(
            index: 1,
            objectID: "song:abc",
            itemID: "track",
            usedIDs: [baseID]
        )

        let secondDuplicate = SonoicSonosControlAPIQueueItemIDBuilder.uniqueID(
            index: 1,
            objectID: "song:abc",
            itemID: "track",
            usedIDs: [baseID, firstDuplicate]
        )

        #expect(firstDuplicate.hasSuffix("-2"))
        #expect(secondDuplicate.hasSuffix("-3"))
        #expect(secondDuplicate != firstDuplicate)
    }

    @Test
    func replacesUnsupportedCharacters() {
        let id = SonoicSonosControlAPIQueueItemIDBuilder.uniqueID(
            index: 0,
            objectID: "song:å ø/123",
            itemID: "track#1",
            usedIDs: []
        )

        #expect(!id.contains(":"))
        #expect(!id.contains("/"))
        #expect(!id.contains("#"))
        #expect(id.contains("-123-track-1"))
    }
}
