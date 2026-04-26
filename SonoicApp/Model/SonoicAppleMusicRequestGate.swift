import Foundation
@preconcurrency import MusicKit

actor SonoicMusicKitRequestGate {
    private static let artistArtworkFallbackLimit = 12

    private var cachedStorefrontCountryCode: String?

    func fetchServiceDetails() async throws -> AppleMusicServiceMetadata {
        let subscription = try await MusicSubscription.current
        let storefrontCountryCode = try await storefrontCountryCode()

        return AppleMusicServiceMetadata(
            storefrontCountryCode: storefrontCountryCode,
            canPlayCatalogContent: subscription.canPlayCatalogContent,
            canBecomeSubscriber: subscription.canBecomeSubscriber,
            hasCloudLibraryEnabled: subscription.hasCloudLibraryEnabled
        )
    }

    func searchCatalog(
        term: String,
        scope: SonoicSourceSearchScope = .all,
        limit: Int,
        totalLimit: Int
    ) async throws -> [AppleMusicItemMetadata] {
        var request = MusicCatalogSearchRequest(
            term: term,
            types: musicCatalogSearchTypes(for: scope)
        )
        request.limit = limit

        let response = try await request.response()
        let songs = response.songs.map { song in
            AppleMusicItemMetadata(
                serviceItemID: song.id.rawValue,
                catalogItemID: song.id.rawValue,
                libraryItemID: nil,
                title: song.title,
                subtitle: song.albumTitle.map { "\(song.artistName) • \($0)" } ?? song.artistName,
                artworkURL: song.artwork?.url(width: 400, height: 400)?.absoluteString,
                externalURL: song.url?.absoluteString,
                kind: .song,
                origin: .catalogSearch
            )
        }
        let albums = response.albums.map { album in
            AppleMusicItemMetadata(
                serviceItemID: album.id.rawValue,
                catalogItemID: album.id.rawValue,
                libraryItemID: nil,
                title: album.title,
                subtitle: album.artistName,
                artworkURL: album.artwork?.url(width: 400, height: 400)?.absoluteString,
                externalURL: album.url?.absoluteString,
                kind: .album,
                origin: .catalogSearch
            )
        }
        let artists = response.artists.map { artist in
            AppleMusicItemMetadata(
                serviceItemID: artist.id.rawValue,
                catalogItemID: artist.id.rawValue,
                libraryItemID: nil,
                title: artist.name,
                subtitle: "Artist",
                artworkURL: artist.artwork?.url(width: 400, height: 400)?.absoluteString,
                externalURL: artist.url?.absoluteString,
                kind: .artist,
                origin: .catalogSearch
            )
        }
        let playlists = response.playlists.map { playlist in
            AppleMusicItemMetadata(
                serviceItemID: playlist.id.rawValue,
                catalogItemID: playlist.id.rawValue,
                libraryItemID: nil,
                title: playlist.name,
                subtitle: playlist.curatorName,
                artworkURL: playlist.artwork?.url(width: 400, height: 400)?.absoluteString,
                externalURL: playlist.url?.absoluteString,
                kind: .playlist,
                origin: .catalogSearch
            )
        }

        if scope == .all {
            return AppleMusicSearchResultBalancer.groupedItems(
                groups: [artists, songs, albums, playlists],
                itemLimitPerGroup: limit,
                totalLimit: totalLimit
            )
        }

        return Array((songs + albums + artists + playlists).prefix(totalLimit))
    }

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
        let items = response.data.map { playlist in
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
                origin: .library
            )
        }

        return AppleMusicItemMetadataPage(items: items, nextOffset: response.nextOffset)
    }

    func fetchRecentlyAdded(limit: Int) async throws -> [AppleMusicItemMetadata] {
        let response = try await fetchRecentlyAddedResponse()
        return Array(response.data.compactMap { resource in
            metadata(from: resource, origin: .library)
        }.prefix(limit))
    }

    func fetchTopCharts(for destination: SonoicAppleMusicBrowseDestination) async throws -> [AppleMusicItemMetadataSection] {
        let types: String
        switch destination {
        case .appleMusicPlaylists:
            types = "playlists"
        case .popularRecommendations:
            types = "songs,albums,playlists"
        case .categories, .playlistsForYou, .newReleases, .radioShows:
            types = "songs,albums,playlists"
        }

        let chartResponse: AppleMusicChartResponse = try await fetchDecoded(
            path: "/v1/catalog/\(try await storefrontCountryCode())/charts",
            queryItems: [
                URLQueryItem(name: "types", value: types),
                URLQueryItem(name: "chart", value: "most-played"),
                URLQueryItem(name: "limit", value: "10")
            ]
        )
        return chartResponse.results.sections()
    }

    func fetchCatalogGenres(limit: Int) async throws -> [AppleMusicGenreMetadata] {
        let genreResponse: AppleMusicGenreResponse = try await fetchDecoded(
            path: "/v1/catalog/\(try await storefrontCountryCode())/genres",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )
        return genreResponse.data.compactMap { genre in
            guard let name = genre.attributes?.name else {
                return nil
            }

            return AppleMusicGenreMetadata(id: genre.id, title: name)
        }
    }

    func fetchItemDetailSections(for lookup: AppleMusicItemLookup) async throws -> [AppleMusicItemMetadataSection] {
        switch lookup.kind {
        case .album:
            let tracks = try await fetchRelatedItems(
                origin: lookup.origin,
                path: "albums",
                id: lookup.serviceItemID,
                relation: "tracks",
                limit: 40
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
            let tracks = try await fetchRelatedItems(
                origin: lookup.origin,
                path: "playlists",
                id: lookup.serviceItemID,
                relation: "tracks",
                limit: 40
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
        case .song:
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

    private func musicCatalogSearchTypes(for scope: SonoicSourceSearchScope) -> [any MusicCatalogSearchable.Type] {
        switch scope {
        case .all:
            [Song.self, Album.self, Artist.self, Playlist.self]
        case .songs:
            [Song.self]
        case .artists:
            [Artist.self]
        case .albums:
            [Album.self]
        case .playlists:
            [Playlist.self]
        }
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

    private func fetchRelatedItems(
        origin: AppleMusicItemOrigin,
        path: String,
        id: String,
        relation: String,
        limit: Int
    ) async throws -> [AppleMusicItemMetadata] {
        let response: AppleMusicLibraryResponse

        switch origin {
        case .library:
            response = try await fetchLibraryRelationshipResponse(
                path: path,
                id: id,
                relation: relation,
                limit: limit
            )
        case .catalogSearch:
            response = try await fetchCatalogRelationshipResponse(
                path: path,
                id: id,
                relation: relation,
                limit: limit
            )
        }

        return response.data.compactMap { resource in
            metadata(from: resource, origin: origin)
        }
    }

    private func metadata(
        from resource: AppleMusicLibraryResource,
        origin: AppleMusicItemOrigin
    ) -> AppleMusicItemMetadata? {
        AppleMusicItemMetadata.metadata(from: resource, origin: origin)
    }

    private func fetchCatalogRelationshipResponse(
        path: String,
        id: String,
        relation: String,
        limit: Int
    ) async throws -> AppleMusicLibraryResponse {
        let storefrontCountryCode = try await storefrontCountryCode()
        return try await fetchResourceResponse(
            path: "/v1/catalog/\(storefrontCountryCode)/\(path)/\(id)/\(relation)",
            limit: limit
        )
    }

    private func fetchLibraryRelationshipResponse(
        path: String,
        id: String,
        relation: String,
        limit: Int
    ) async throws -> AppleMusicLibraryResponse {
        try await fetchResourceResponse(
            path: "/v1/me/library/\(path)/\(id)/\(relation)",
            limit: limit
        )
    }

    private func fetchRecentlyAddedResponse() async throws -> AppleMusicLibraryResponse {
        try await fetchResourceResponse(path: "/v1/me/library/recently-added")
    }

    private func fetchResourceResponse(path: String, limit: Int? = nil) async throws -> AppleMusicLibraryResponse {
        try await fetchDecoded(
            path: path,
            queryItems: limit.map { [URLQueryItem(name: "limit", value: "\($0)")] } ?? []
        )
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

    private func fetchDecoded<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let request = MusicDataRequest(urlRequest: URLRequest(url: url))
        let response = try await request.response()
        return try JSONDecoder().decode(Response.self, from: response.data)
    }

    private func storefrontCountryCode() async throws -> String {
        if let cachedStorefrontCountryCode {
            return cachedStorefrontCountryCode
        }

        let storefrontCountryCode = try await MusicDataRequest.currentCountryCode
        cachedStorefrontCountryCode = storefrontCountryCode
        return storefrontCountryCode
    }
}
