import Foundation
@preconcurrency import MusicKit

struct SonoicAppleMusicCatalogSearchClient {
    enum ClientError: LocalizedError {
        case unauthorized(MusicAuthorization.Status)
        case missingDeveloperTokenSetup(MusicKitRequestFailure)

        var errorDescription: String? {
            switch self {
            case let .unauthorized(status):
                let appStatus = SonoicAppleMusicAuthorizationState.Status(status)
                return "Apple Music access is \(appStatus.sonoicDisplayName.lowercased())."
            case let .missingDeveloperTokenSetup(failure):
                return """
                MusicKit could not receive Apple's automatic developer token for this bundle. Confirm MusicKit is enabled for com.markusskov.Sonoic in Apple Developer, then rebuild after the App ID has propagated.

                \(failure.displayDetail)
                """
            }
        }
    }

    private let requestGate = SonoicMusicKitRequestGate()

    func currentAuthorizationState() -> SonoicAppleMusicAuthorizationState {
        SonoicAppleMusicAuthorizationState(status: SonoicAppleMusicAuthorizationState.Status(MusicAuthorization.currentStatus))
    }

    func requestAuthorizationState() async -> SonoicAppleMusicAuthorizationState {
        let status = await MusicAuthorization.request()
        return SonoicAppleMusicAuthorizationState(status: SonoicAppleMusicAuthorizationState.Status(status))
    }

    func fetchServiceDetails() async throws -> SonoicAppleMusicServiceDetails {
        do {
            let metadata = try await requestGate.fetchServiceDetails()

            return .loaded(
                storefrontCountryCode: metadata.storefrontCountryCode,
                canPlayCatalogContent: metadata.canPlayCatalogContent,
                canBecomeSubscriber: metadata.canBecomeSubscriber,
                hasCloudLibraryEnabled: metadata.hasCloudLibraryEnabled
            )
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func searchCatalog(
        term: String,
        scope: SonoicSourceSearchScope = .all
    ) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.searchCatalog(term: term, scope: scope, limit: 12).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchLibraryAlbums(limit: Int = 24) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.fetchLibraryAlbums(limit: limit).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchLibraryPlaylists(limit: Int = 24) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.fetchLibraryPlaylists(limit: limit).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchLibraryArtists(limit: Int = 50) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.fetchLibraryArtists(limit: limit).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchLibrarySongs(limit: Int = 50) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.fetchLibrarySongs(limit: limit).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchRecentlyAdded(limit: Int = 10) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.fetchRecentlyAdded(limit: limit).map(sourceItem)
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchBrowseState(for destination: SonoicAppleMusicBrowseDestination) async throws -> SonoicAppleMusicBrowseState {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            switch destination {
            case .popularRecommendations, .appleMusicPlaylists:
                let sections = try await requestGate.fetchTopCharts(for: destination).map { section in
                    SonoicAppleMusicItemDetailSection(
                        id: section.id,
                        title: section.title,
                        subtitle: section.subtitle,
                        items: section.items.map(sourceItem)
                    )
                }
                return SonoicAppleMusicBrowseState(
                    destination: destination,
                    sections: sections,
                    status: .loaded
                )
            case .categories:
                let genres = try await requestGate.fetchCatalogGenres(limit: 24).map { genre in
                    SonoicAppleMusicGenreItem(id: genre.id, title: genre.title)
                }
                return SonoicAppleMusicBrowseState(
                    destination: destination,
                    genres: genres,
                    status: .loaded
                )
            case .playlistsForYou, .newReleases, .radioShows:
                return SonoicAppleMusicBrowseState(destination: destination, status: .loaded)
            }
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    func fetchItemDetailSections(for item: SonoicSourceItem) async throws -> [SonoicAppleMusicItemDetailSection] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        guard let serviceItemID = item.serviceItemID else {
            return []
        }
        guard let kind = appleMusicKind(for: item.kind),
              let origin = appleMusicOrigin(for: item.origin)
        else {
            return []
        }
        let lookup = AppleMusicItemLookup(
            serviceItemID: serviceItemID,
            title: item.title,
            kind: kind,
            origin: origin
        )

        do {
            return try await requestGate.fetchItemDetailSections(for: lookup).map { section in
                SonoicAppleMusicItemDetailSection(
                    id: section.id,
                    title: section.title,
                    subtitle: section.subtitle,
                    items: section.items.map(sourceItem)
                )
            }
        } catch {
            throw mappedMusicKitError(error)
        }
    }

    private func mappedMusicKitError(_ error: Error) -> Error {
        if error.localizedDescription.localizedCaseInsensitiveContains("developer token") {
            return ClientError.missingDeveloperTokenSetup(MusicKitRequestFailure(error))
        }

        return error
    }

    private func sourceItem(from metadata: AppleMusicItemMetadata) -> SonoicSourceItem {
        SonoicSourceItem.appleMusicMetadata(
            id: metadata.serviceItemID,
            title: metadata.title,
            subtitle: metadata.subtitle,
            artworkURL: metadata.artworkURL,
            kind: sourceKind(for: metadata.kind),
            origin: sourceOrigin(for: metadata.origin)
        )
    }

    private func appleMusicKind(for sourceKind: SonoicSourceItem.Kind) -> AppleMusicItemKind? {
        switch sourceKind {
        case .album:
            .album
        case .artist:
            .artist
        case .playlist:
            .playlist
        case .song:
            .song
        case .station, .unknown:
            nil
        }
    }

    private func appleMusicOrigin(for sourceOrigin: SonoicSourceItem.Origin) -> AppleMusicItemOrigin? {
        switch sourceOrigin {
        case .catalogSearch:
            .catalogSearch
        case .library:
            .library
        case .favorite, .recentPlay:
            nil
        }
    }

    private func sourceKind(for appleMusicKind: AppleMusicItemKind) -> SonoicSourceItem.Kind {
        switch appleMusicKind {
        case .album:
            .album
        case .artist:
            .artist
        case .playlist:
            .playlist
        case .song:
            .song
        }
    }

    private func sourceOrigin(for appleMusicOrigin: AppleMusicItemOrigin) -> SonoicSourceItem.Origin {
        switch appleMusicOrigin {
        case .catalogSearch:
            .catalogSearch
        case .library:
            .library
        }
    }
}

private actor SonoicMusicKitRequestGate {
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
        limit: Int
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
                title: song.title,
                subtitle: song.albumTitle.map { "\(song.artistName) • \($0)" } ?? song.artistName,
                artworkURL: song.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .song,
                origin: .catalogSearch
            )
        }
        let albums = response.albums.map { album in
            AppleMusicItemMetadata(
                serviceItemID: album.id.rawValue,
                title: album.title,
                subtitle: album.artistName,
                artworkURL: album.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .album,
                origin: .catalogSearch
            )
        }
        let artists = response.artists.map { artist in
            AppleMusicItemMetadata(
                serviceItemID: artist.id.rawValue,
                title: artist.name,
                subtitle: "Artist",
                artworkURL: artist.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .artist,
                origin: .catalogSearch
            )
        }
        let playlists = response.playlists.map { playlist in
            AppleMusicItemMetadata(
                serviceItemID: playlist.id.rawValue,
                title: playlist.name,
                subtitle: playlist.curatorName,
                artworkURL: playlist.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .playlist,
                origin: .catalogSearch
            )
        }

        return Array((songs + albums + artists + playlists).prefix(limit))
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

    func fetchLibraryAlbums(limit: Int) async throws -> [AppleMusicItemMetadata] {
        let response = try await fetchLibraryResponse(path: "albums", limit: limit)
        return response.data.map { album in
            AppleMusicItemMetadata(
                serviceItemID: album.id,
                title: album.attributes?.name ?? "Unknown Album",
                subtitle: album.attributes?.artistName,
                artworkURL: album.attributes?.artwork?.sizedURL(width: 400, height: 400),
                kind: .album,
                origin: .library
            )
        }
    }

    func fetchLibraryPlaylists(limit: Int) async throws -> [AppleMusicItemMetadata] {
        let response = try await fetchLibraryResponse(path: "playlists", limit: limit)
        return response.data.map { playlist in
            AppleMusicItemMetadata(
                serviceItemID: playlist.id,
                title: playlist.attributes?.name ?? "Unknown Playlist",
                subtitle: playlist.attributes?.curatorName,
                artworkURL: playlist.attributes?.artwork?.sizedURL(width: 400, height: 400),
                kind: .playlist,
                origin: .library
            )
        }
    }

    func fetchLibraryArtists(limit: Int) async throws -> [AppleMusicItemMetadata] {
        let response = try await fetchLibraryResponse(path: "artists", limit: limit)
        var artists = response.data.map { artist in
            AppleMusicItemMetadata(
                serviceItemID: artist.id,
                title: artist.attributes?.name ?? "Unknown Artist",
                subtitle: "Artist",
                artworkURL: artist.attributes?.artwork?.sizedURL(width: 400, height: 400),
                kind: .artist,
                origin: .library
            )
        }

        for index in artists.indices where artists[index].artworkURL == nil {
            artists[index].artworkURL = try await fetchCatalogArtistArtworkURL(
                artistName: artists[index].title,
                width: 400,
                height: 400
            )
        }

        return artists
    }

    func fetchLibrarySongs(limit: Int) async throws -> [AppleMusicItemMetadata] {
        let response = try await fetchLibraryResponse(path: "songs", limit: limit)
        return response.data.map { song in
            let artistName = song.attributes?.artistName
            let albumName = song.attributes?.albumName

            return AppleMusicItemMetadata(
                serviceItemID: song.id,
                title: song.attributes?.name ?? "Unknown Song",
                subtitle: albumName.map { albumName in
                    [artistName, albumName].compactMap(\.self).joined(separator: " • ")
                } ?? artistName,
                artworkURL: song.attributes?.artwork?.sizedURL(width: 400, height: 400),
                kind: .song,
                origin: .library
            )
        }
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

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = "/v1/catalog/\(try await storefrontCountryCode())/charts"
        components.queryItems = [
            URLQueryItem(name: "types", value: types),
            URLQueryItem(name: "chart", value: "most-played"),
            URLQueryItem(name: "limit", value: "10")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let request = MusicDataRequest(urlRequest: URLRequest(url: url))
        let response = try await request.response()
        let chartResponse = try JSONDecoder().decode(AppleMusicChartResponse.self, from: response.data)
        return chartResponse.results.sections()
    }

    func fetchCatalogGenres(limit: Int) async throws -> [AppleMusicGenreMetadata] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = "/v1/catalog/\(try await storefrontCountryCode())/genres"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let request = MusicDataRequest(urlRequest: URLRequest(url: url))
        let response = try await request.response()
        let genreResponse = try JSONDecoder().decode(AppleMusicGenreResponse.self, from: response.data)
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
            let results = try await searchCatalog(term: lookup.title, limit: 16)
            let songs = Array(results.filter { $0.kind == .song }.prefix(8))
            let albums = Array(results.filter { $0.kind == .album }.prefix(8))
            var sections: [AppleMusicItemMetadataSection] = []

            if !songs.isEmpty {
                sections.append(
                    AppleMusicItemMetadataSection(
                        id: "songs",
                        title: "Songs",
                        items: songs
                    )
                )
            }

            if !albums.isEmpty {
                sections.append(
                    AppleMusicItemMetadataSection(
                        id: "albums",
                        title: "Albums",
                        items: albums
                    )
                )
            }

            return sections
        case .song:
            return []
        }
    }

    private func fetchLibraryResponse(path: String, limit: Int) async throws -> AppleMusicLibraryResponse {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = "/v1/me/library/\(path)"
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let request = MusicDataRequest(urlRequest: URLRequest(url: url))
        let response = try await request.response()
        return try JSONDecoder().decode(AppleMusicLibraryResponse.self, from: response.data)
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
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = path
        components.queryItems = limit.map { [URLQueryItem(name: "limit", value: "\($0)")] }

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let request = MusicDataRequest(urlRequest: URLRequest(url: url))
        let response = try await request.response()
        return try JSONDecoder().decode(AppleMusicLibraryResponse.self, from: response.data)
    }

    private func fetchCatalogArtistArtworkURL(
        artistName: String,
        width: Int,
        height: Int
    ) async throws -> String? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        components.path = "/v1/catalog/\(try await storefrontCountryCode())/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: artistName),
            URLQueryItem(name: "types", value: "artists"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let request = MusicDataRequest(urlRequest: URLRequest(url: url))
        let response = try await request.response()
        let searchResponse = try JSONDecoder().decode(AppleMusicCatalogSearchResponse.self, from: response.data)
        return searchResponse.results.artists?.data.first?.attributes?.artwork?.sizedURL(width: width, height: height)
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

struct MusicKitRequestFailure: Equatable {
    var domain: String
    var code: Int
    var message: String

    init(_ error: Error) {
        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        message = nsError.localizedDescription
    }

    nonisolated var displayDetail: String {
        "\(domain) \(code): \(message)"
    }
}

extension SonoicAppleMusicAuthorizationState.Status {
    nonisolated init(_ musicAuthorizationStatus: MusicAuthorization.Status) {
        switch musicAuthorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .authorized:
            self = .authorized
        @unknown default:
            self = .unavailable
        }
    }

    nonisolated var sonoicDisplayName: String {
        switch self {
        case .notDetermined:
            "Not Determined"
        case .requesting:
            "Requesting"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .authorized:
            "Authorized"
        case .unavailable:
            "Unavailable"
        @unknown default:
            "Unavailable"
        }
    }
}
