import Testing
@testable import Sonoic

struct AppleMusicSearchResultBalancerTests {
    @Test
    func groupsItemsByKindWithPerGroupCap() {
        let items = AppleMusicSearchResultBalancer.groupedItems(
            groups: [
                metadataItems(prefix: "artist", count: 3),
                metadataItems(prefix: "song", count: 4),
                metadataItems(prefix: "album", count: 2),
                metadataItems(prefix: "playlist", count: 2)
            ],
            itemLimitPerGroup: 2,
            totalLimit: 7
        )

        #expect(items.map(\.serviceItemID) == [
            "artist-0",
            "artist-1",
            "song-0",
            "song-1",
            "album-0",
            "album-1",
            "playlist-0"
        ])
    }

    @Test
    func groupedItemsIgnoreEmptyGroups() {
        let items = AppleMusicSearchResultBalancer.groupedItems(
            groups: [
                [],
                metadataItems(prefix: "song", count: 3),
                [],
                metadataItems(prefix: "playlist", count: 2)
            ],
            itemLimitPerGroup: 2,
            totalLimit: 4
        )

        #expect(items.map(\.serviceItemID) == [
            "song-0",
            "song-1",
            "playlist-0",
            "playlist-1"
        ])
    }

    @Test
    func interleavesAvailableResultGroups() {
        let items = AppleMusicSearchResultBalancer.balancedItems(
            groups: [
                metadataItems(prefix: "song", count: 4),
                metadataItems(prefix: "album", count: 2),
                metadataItems(prefix: "artist", count: 1),
                metadataItems(prefix: "playlist", count: 1)
            ],
            limit: 6
        )

        #expect(items.map(\.serviceItemID) == [
            "song-0",
            "album-0",
            "artist-0",
            "playlist-0",
            "song-1",
            "album-1"
        ])
    }

    @Test
    func backfillsFromRemainingGroups() {
        let items = AppleMusicSearchResultBalancer.balancedItems(
            groups: [
                metadataItems(prefix: "song", count: 4),
                [],
                [],
                metadataItems(prefix: "playlist", count: 1)
            ],
            limit: 5
        )

        #expect(items.map(\.serviceItemID) == [
            "song-0",
            "playlist-0",
            "song-1",
            "song-2",
            "song-3"
        ])
    }

    private func metadataItems(prefix: String, count: Int) -> [AppleMusicItemMetadata] {
        (0..<count).map { index in
            AppleMusicItemMetadata(
                serviceItemID: "\(prefix)-\(index)",
                catalogItemID: "\(prefix)-\(index)",
                libraryItemID: nil,
                title: "\(prefix) \(index)",
                subtitle: nil,
                artworkURL: nil,
                externalURL: nil,
                kind: .song,
                origin: .catalogSearch
            )
        }
    }
}
