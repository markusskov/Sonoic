import Foundation

extension SonoicMusicKitRequestGate {
    func fetchLibraryAlbums(limit: Int, offset: Int? = nil) async throws -> AppleMusicItemMetadataPage {
        let response = try await fetchLibraryResponse(path: "albums", limit: limit, offset: offset)
        let items = response.data.map { album in
            AppleMusicItemMetadata(
                serviceItemID: album.id,
                catalogItemID: album.catalogItemID,
                libraryItemID: album.libraryItemID,
                title: album.attributes?.name ?? "Unknown Album",
                subtitle: album.attributes?.artistName,
                artworkURL: album.attributes?.artwork?.sizedURL(width: 400, height: 400),
                externalURL: album.attributes?.url,
                kind: .album,
                origin: .library
            )
        }

        return AppleMusicItemMetadataPage(items: items, nextOffset: response.nextOffset)
    }

    func fetchLibraryPlaylists(limit: Int, offset: Int? = nil) async throws -> AppleMusicItemMetadataPage {
        let response = try await fetchLibraryResponse(path: "playlists", limit: limit, offset: offset)
        var items = response.data.map { playlist in
            AppleMusicItemMetadata(
                serviceItemID: playlist.id,
                catalogItemID: playlist.catalogItemID,
                libraryItemID: playlist.libraryItemID,
                title: playlist.attributes?.name ?? "Unknown Playlist",
                subtitle: playlist.attributes?.curatorName,
                artworkURL: playlist.attributes?.artwork?.sizedURL(width: 400, height: 400),
                externalURL: playlist.attributes?.url,
                kind: .playlist,
                origin: .library
            )
        }

        let artworkFallbackIndices = items.indices
            .filter { items[$0].artworkURL == nil && items[$0].catalogItemID?.sonoicNonEmptyTrimmed != nil }
            .prefix(Self.playlistArtworkFallbackLimit)

        for index in artworkFallbackIndices {
            try Task.checkCancellation()
            guard let catalogID = items[index].catalogItemID?.sonoicNonEmptyTrimmed else {
                continue
            }

            items[index].artworkURL = try? await fetchCatalogArtworkURL(
                path: "playlists",
                id: catalogID,
                width: 400,
                height: 400
            )
        }

        return AppleMusicItemMetadataPage(items: items, nextOffset: response.nextOffset)
    }

    func fetchLibraryArtists(limit: Int, offset: Int? = nil) async throws -> AppleMusicItemMetadataPage {
        let response = try await fetchLibraryResponse(path: "artists", limit: limit, offset: offset)
        var artists = response.data.map { artist in
            AppleMusicItemMetadata(
                serviceItemID: artist.id,
                catalogItemID: artist.catalogItemID,
                libraryItemID: artist.libraryItemID,
                title: artist.attributes?.name ?? "Unknown Artist",
                subtitle: "Artist",
                artworkURL: artist.attributes?.artwork?.sizedURL(width: 400, height: 400),
                externalURL: artist.attributes?.url,
                kind: .artist,
                origin: .library
            )
        }

        let artworkFallbackIndices = artists.indices
            .filter { artists[$0].artworkURL == nil }
            .prefix(Self.artistArtworkFallbackLimit)

        for index in artworkFallbackIndices {
            try Task.checkCancellation()
            artists[index].artworkURL = try? await fetchCatalogArtistArtworkURL(
                artistName: artists[index].title,
                width: 400,
                height: 400
            )
        }

        return AppleMusicItemMetadataPage(items: artists, nextOffset: response.nextOffset)
    }

    func fetchLibrarySongs(limit: Int, offset: Int? = nil) async throws -> AppleMusicItemMetadataPage {
        let response = try await fetchLibraryResponse(path: "songs", limit: limit, offset: offset)
        let items = response.data.map { song in
            let artistName = song.attributes?.artistName
            let albumName = song.attributes?.albumName

            return AppleMusicItemMetadata(
                serviceItemID: song.id,
                catalogItemID: song.catalogItemID,
                libraryItemID: song.libraryItemID,
                title: song.attributes?.name ?? "Unknown Song",
                subtitle: albumName.map { albumName in
                    [artistName, albumName].compactMap(\.self).joined(separator: " • ")
                } ?? artistName,
                artworkURL: song.attributes?.artwork?.sizedURL(width: 400, height: 400),
                externalURL: song.attributes?.url,
                kind: .song,
                origin: .library,
                duration: song.attributes?.duration
            )
        }

        return AppleMusicItemMetadataPage(items: items, nextOffset: response.nextOffset)
    }

    func fetchRecentlyAdded(limit: Int) async throws -> [AppleMusicItemMetadata] {
        let response = try await fetchResourceResponse(path: "/v1/me/library/recently-added")
        return Array(response.data.compactMap { resource in
            AppleMusicItemMetadata.metadata(from: resource, origin: .library)
        }.prefix(limit))
    }

    private func fetchLibraryResponse(path: String, limit: Int, offset: Int? = nil) async throws -> AppleMusicLibraryResponse {
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let offset {
            queryItems.append(URLQueryItem(name: "offset", value: "\(offset)"))
        }

        return try await fetchDecoded(path: "/v1/me/library/\(path)", queryItems: queryItems)
    }

    private func fetchCatalogArtistArtworkURL(
        artistName: String,
        width: Int,
        height: Int
    ) async throws -> String? {
        let searchResponse: AppleMusicCatalogSearchResponse = try await fetchDecoded(
            path: "/v1/catalog/\(try await storefrontCountryCode())/search",
            queryItems: [
                URLQueryItem(name: "term", value: artistName),
                URLQueryItem(name: "types", value: "artists"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        return searchResponse.results.artists?.data.first?.attributes?.artwork?.sizedURL(width: width, height: height)
    }

    private func fetchCatalogArtworkURL(
        path: String,
        id: String,
        width: Int,
        height: Int
    ) async throws -> String? {
        let response: AppleMusicLibraryResponse = try await fetchDecoded(
            path: "/v1/catalog/\(try await storefrontCountryCode())/\(path)/\(id)"
        )
        return response.data.first?.attributes?.artwork?.sizedURL(width: width, height: height)
    }
}
