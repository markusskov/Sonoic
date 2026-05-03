import Foundation

extension SonoicMusicKitRequestGate {
    func fetchItemDetailSections(for lookup: AppleMusicItemLookup) async throws -> [AppleMusicItemMetadataSection] {
        switch lookup.kind {
        case .album:
            let tracks = try await fetchAllRelatedItems(
                origin: lookup.origin,
                path: "albums",
                id: lookup.serviceItemID,
                relation: "tracks"
            )

            return tracks.isEmpty ? [] : [
                AppleMusicItemMetadataSection(
                    id: "tracks",
                    title: "Tracks",
                    subtitle: "\(tracks.count) songs",
                    items: tracks
                )
            ]
        case .playlist:
            let tracks = try await fetchAllRelatedItems(
                origin: lookup.origin,
                path: "playlists",
                id: lookup.serviceItemID,
                relation: "tracks"
            )

            return tracks.isEmpty ? [] : [
                AppleMusicItemMetadataSection(
                    id: "tracks",
                    title: "Tracks",
                    subtitle: "\(tracks.count) songs",
                    items: tracks
                )
            ]
        case .artist:
            return try await fetchArtistDetailSections(for: lookup)
        case .song, .station:
            return []
        }
    }

    private func fetchArtistDetailSections(
        for lookup: AppleMusicItemLookup
    ) async throws -> [AppleMusicItemMetadataSection] {
        if let catalogID = lookup.catalogItemID ?? (lookup.origin == .catalogSearch ? lookup.serviceItemID : nil),
           let section = try? await fetchArtistAlbumsSection(
            origin: .catalogSearch,
            id: catalogID
           ) {
            return [section]
        }

        if let libraryID = lookup.libraryItemID ?? (lookup.origin == .library ? lookup.serviceItemID : nil),
           let section = try? await fetchArtistAlbumsSection(
            origin: .library,
            id: libraryID
           ) {
            return [section]
        }

        return try await fetchArtistSearchFallbackSections(for: lookup.title)
    }

    private func fetchArtistAlbumsSection(
        origin: AppleMusicItemOrigin,
        id: String
    ) async throws -> AppleMusicItemMetadataSection? {
        let albums = try await fetchRelatedItems(
            origin: origin,
            path: "artists",
            id: id,
            relation: "albums",
            limit: 24
        )
        guard !albums.isEmpty else {
            return nil
        }

        return AppleMusicItemMetadataSection(
            id: "albums",
            title: "Albums",
            subtitle: "\(albums.count) albums",
            items: albums
        )
    }

    private func fetchArtistSearchFallbackSections(
        for artistName: String
    ) async throws -> [AppleMusicItemMetadataSection] {
        let results = try await searchCatalog(term: artistName, limit: 16, totalLimit: 16)
        let songs = Array(results.filter { $0.kind == .song }.prefix(8))
        let albums = Array(results.filter { $0.kind == .album }.prefix(8))
        var sections: [AppleMusicItemMetadataSection] = []

        if !songs.isEmpty {
            sections.append(
                AppleMusicItemMetadataSection(
                    id: "songs",
                    title: "Songs",
                    subtitle: "Search matches",
                    items: songs
                )
            )
        }

        if !albums.isEmpty {
            sections.append(
                AppleMusicItemMetadataSection(
                    id: "albums",
                    title: "Albums",
                    subtitle: "Search matches",
                    items: albums
                )
            )
        }

        return sections
    }

    private func fetchRelatedItems(
        origin: AppleMusicItemOrigin,
        path: String,
        id: String,
        relation: String,
        limit: Int
    ) async throws -> [AppleMusicItemMetadata] {
        let response = try await fetchRelatedItemsResponse(
            origin: origin,
            path: path,
            id: id,
            relation: relation,
            limit: limit
        )

        return response.data.compactMap { resource in
            AppleMusicItemMetadata.metadata(from: resource, origin: origin)
        }
    }

    private func fetchAllRelatedItems(
        origin: AppleMusicItemOrigin,
        path: String,
        id: String,
        relation: String
    ) async throws -> [AppleMusicItemMetadata] {
        var items: [AppleMusicItemMetadata] = []
        var nextOffset: Int?
        var seenOffsets = Set<Int>()

        while true {
            let response = try await fetchRelatedItemsResponse(
                origin: origin,
                path: path,
                id: id,
                relation: relation,
                limit: Self.relatedTrackPageLimit,
                offset: nextOffset
            )
            items.append(contentsOf: response.data.compactMap { resource in
                AppleMusicItemMetadata.metadata(from: resource, origin: origin)
            })

            guard let offset = response.nextOffset,
                  !response.data.isEmpty,
                  !seenOffsets.contains(offset)
            else {
                return items
            }

            seenOffsets.insert(offset)
            nextOffset = offset
        }
    }

    private func fetchRelatedItemsResponse(
        origin: AppleMusicItemOrigin,
        path: String,
        id: String,
        relation: String,
        limit: Int,
        offset: Int? = nil
    ) async throws -> AppleMusicLibraryResponse {
        switch origin {
        case .library:
            try await fetchResourceResponse(
                path: "/v1/me/library/\(path)/\(id)/\(relation)",
                limit: limit,
                offset: offset
            )
        case .catalogSearch:
            try await fetchResourceResponse(
                path: "/v1/catalog/\(try await storefrontCountryCode())/\(path)/\(id)/\(relation)",
                limit: limit,
                offset: offset
            )
        }
    }
}
