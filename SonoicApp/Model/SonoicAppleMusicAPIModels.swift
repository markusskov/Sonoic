import Foundation

struct AppleMusicServiceMetadata: Sendable {
    var storefrontCountryCode: String
    var canPlayCatalogContent: Bool
    var canBecomeSubscriber: Bool
    var hasCloudLibraryEnabled: Bool
}

nonisolated struct AppleMusicItemMetadata: Sendable {
    var serviceItemID: String
    var catalogItemID: String?
    var libraryItemID: String?
    var title: String
    var subtitle: String?
    var artworkURL: String?
    var externalURL: String?
    var kind: AppleMusicItemKind
    var origin: AppleMusicItemOrigin
    var duration: TimeInterval?

    static func metadata(
        from resource: AppleMusicLibraryResource,
        origin: AppleMusicItemOrigin
    ) -> AppleMusicItemMetadata? {
        guard let kind = AppleMusicItemKind(resourceType: resource.type) else {
            return nil
        }

        return AppleMusicItemMetadata(
            serviceItemID: resource.id,
            catalogItemID: resource.catalogItemID,
            libraryItemID: resource.libraryItemID,
            title: resource.attributes?.name ?? "Unknown",
            subtitle: resource.attributes?.albumName.map { albumName in
                [resource.attributes?.artistName, albumName].compactMap(\.self).joined(separator: " • ")
            } ?? resource.attributes?.artistName ?? resource.attributes?.curatorName,
            artworkURL: resource.attributes?.artwork?.sizedURL(width: 400, height: 400),
            externalURL: resource.attributes?.url,
            kind: kind,
            origin: origin,
            duration: resource.attributes?.duration
        )
    }
}

nonisolated struct AppleMusicItemMetadataSection: Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var items: [AppleMusicItemMetadata]
}

nonisolated struct AppleMusicItemMetadataPage: Sendable {
    var items: [AppleMusicItemMetadata]
    var nextOffset: Int?
}

nonisolated enum AppleMusicSearchResultBalancer {
    static func groupedItems(
        groups: [[AppleMusicItemMetadata]],
        itemLimitPerGroup: Int,
        totalLimit: Int
    ) -> [AppleMusicItemMetadata] {
        guard itemLimitPerGroup > 0, totalLimit > 0 else {
            return []
        }

        var items: [AppleMusicItemMetadata] = []
        items.reserveCapacity(totalLimit)

        for group in groups {
            guard items.count < totalLimit else {
                break
            }

            let remainingItemCount = totalLimit - items.count
            items.append(contentsOf: group.prefix(min(itemLimitPerGroup, remainingItemCount)))
        }

        return items
    }

}

nonisolated struct AppleMusicGenreMetadata: Sendable {
    var id: String
    var title: String
}

nonisolated struct AppleMusicItemLookup: Sendable {
    var serviceItemID: String
    var catalogItemID: String?
    var libraryItemID: String?
    var title: String
    var kind: AppleMusicItemKind
    var origin: AppleMusicItemOrigin
}

nonisolated enum AppleMusicItemOrigin: Sendable {
    case catalogSearch
    case library
}

nonisolated enum AppleMusicItemKind: Sendable {
    case album
    case artist
    case playlist
    case song
    case station

    init?(resourceType: String?) {
        switch resourceType {
        case "albums", "library-albums":
            self = .album
        case "artists", "library-artists":
            self = .artist
        case "playlists", "library-playlists":
            self = .playlist
        case "songs", "library-songs":
            self = .song
        case "stations":
            self = .station
        default:
            return nil
        }
    }
}

nonisolated struct AppleMusicLibraryResponse: Decodable {
    var data: [AppleMusicLibraryResource]
    var next: String?

    var nextOffset: Int? {
        guard let next,
              let components = URLComponents(string: next),
              let offsetValue = components.queryItems?.first(where: { $0.name == "offset" })?.value,
              let offset = Int(offsetValue)
        else {
            return nil
        }

        return offset
    }
}

nonisolated struct AppleMusicLibraryResource: Decodable {
    var id: String
    var type: String?
    var attributes: AppleMusicLibraryAttributes?

    var catalogItemID: String? {
        if type?.hasPrefix("library-") == true {
            return attributes?.playParams?.catalogId
        }

        return id
    }

    var libraryItemID: String? {
        type?.hasPrefix("library-") == true ? id : nil
    }
}

nonisolated struct AppleMusicLibraryAttributes: Decodable {
    var name: String?
    var artistName: String?
    var albumName: String?
    var curatorName: String?
    var artwork: AppleMusicLibraryArtwork?
    var url: String?
    var playParams: AppleMusicPlayParameters?
    var durationInMillis: Int?

    var duration: TimeInterval? {
        durationInMillis.map { TimeInterval($0) / 1000 }
    }
}

nonisolated struct AppleMusicPlayParameters: Decodable {
    var catalogId: String?
}

nonisolated struct AppleMusicLibraryArtwork: Decodable {
    var url: String?

    func sizedURL(width: Int, height: Int) -> String? {
        url?
            .replacingOccurrences(of: "{w}", with: "\(width)")
            .replacingOccurrences(of: "{h}", with: "\(height)")
    }
}

nonisolated struct AppleMusicCatalogSearchResponse: Decodable {
    var results: AppleMusicCatalogSearchResults
}

nonisolated struct AppleMusicCatalogSearchResults: Decodable {
    var artists: AppleMusicCatalogResourceCollection?
}

nonisolated struct AppleMusicCatalogResourceCollection: Decodable {
    var data: [AppleMusicLibraryResource]
}

nonisolated struct AppleMusicRecommendationResponse: Decodable {
    var data: [AppleMusicRecommendationResource]

    func sections() -> [AppleMusicItemMetadataSection] {
        data.compactMap(\.section)
    }
}

nonisolated struct AppleMusicRecommendationResource: Decodable {
    var id: String
    var attributes: AppleMusicRecommendationAttributes?
    var relationships: AppleMusicRecommendationRelationships?

    var section: AppleMusicItemMetadataSection? {
        let items = relationships?.contents?.data.compactMap { resource in
            AppleMusicItemMetadata.metadata(from: resource, origin: .catalogSearch)
        } ?? []

        guard !items.isEmpty else {
            return nil
        }

        return AppleMusicItemMetadataSection(
            id: id,
            title: attributes?.title?.stringForDisplay ?? "For You",
            subtitle: nil,
            items: items
        )
    }
}

nonisolated struct AppleMusicRecommendationAttributes: Decodable {
    var title: AppleMusicDisplayString?
}

nonisolated struct AppleMusicDisplayString: Decodable {
    var stringForDisplay: String?
}

nonisolated struct AppleMusicRecommendationRelationships: Decodable {
    var contents: AppleMusicCatalogResourceCollection?
}

nonisolated struct AppleMusicChartResponse: Decodable {
    var results: AppleMusicChartResults
}

nonisolated struct AppleMusicChartResults: Decodable {
    var songs: [AppleMusicChart]?
    var albums: [AppleMusicChart]?
    var playlists: [AppleMusicChart]?

    func sections() -> [AppleMusicItemMetadataSection] {
        [
            section(id: "songs", title: "Top Songs", charts: songs),
            section(id: "albums", title: "Top Albums", charts: albums),
            section(id: "playlists", title: "Top Playlists", charts: playlists)
        ]
        .compactMap(\.self)
    }

    private func section(
        id: String,
        title: String,
        charts: [AppleMusicChart]?
    ) -> AppleMusicItemMetadataSection? {
        let items = charts?
            .flatMap(\.data)
            .compactMap { resource in
                AppleMusicItemMetadata.metadata(from: resource, origin: .catalogSearch)
            } ?? []

        guard !items.isEmpty else {
            return nil
        }

        return AppleMusicItemMetadataSection(
            id: id,
            title: charts?.first?.name ?? title,
            subtitle: "\(items.count) Apple Music items",
            items: items
        )
    }
}

nonisolated struct AppleMusicChart: Decodable {
    var name: String?
    var data: [AppleMusicLibraryResource]
}

nonisolated struct AppleMusicGenreResponse: Decodable {
    var data: [AppleMusicGenreResource]
}

nonisolated struct AppleMusicGenreResource: Decodable {
    var id: String
    var attributes: AppleMusicGenreAttributes?
}

nonisolated struct AppleMusicGenreAttributes: Decodable {
    var name: String?
}
