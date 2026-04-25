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

    func searchCatalog(term: String) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw ClientError.unauthorized(MusicAuthorization.currentStatus)
        }

        do {
            return try await requestGate.searchCatalog(term: term, limit: 8).map(sourceItem)
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

    private func mappedMusicKitError(_ error: Error) -> Error {
        if error.localizedDescription.localizedCaseInsensitiveContains("developer token") {
            return ClientError.missingDeveloperTokenSetup(MusicKitRequestFailure(error))
        }

        return error
    }

    private func sourceItem(from metadata: AppleMusicItemMetadata) -> SonoicSourceItem {
        SonoicSourceItem.catalogMetadata(
            id: metadata.id,
            title: metadata.title,
            subtitle: metadata.subtitle,
            artworkURL: metadata.artworkURL,
            kind: metadata.kind.sonoicKind,
            service: .appleMusic
        )
    }
}

private actor SonoicMusicKitRequestGate {
    func fetchServiceDetails() async throws -> AppleMusicServiceMetadata {
        let subscription = try await MusicSubscription.current
        let storefrontCountryCode = try await MusicDataRequest.currentCountryCode

        return AppleMusicServiceMetadata(
            storefrontCountryCode: storefrontCountryCode,
            canPlayCatalogContent: subscription.canPlayCatalogContent,
            canBecomeSubscriber: subscription.canBecomeSubscriber,
            hasCloudLibraryEnabled: subscription.hasCloudLibraryEnabled
        )
    }

    func searchCatalog(term: String, limit: Int) async throws -> [AppleMusicItemMetadata] {
        var request = MusicCatalogSearchRequest(
            term: term,
            types: [Song.self, Album.self]
        )
        request.limit = limit

        let response = try await request.response()
        let songs = response.songs.map { song in
            AppleMusicItemMetadata(
                id: "song-\(song.id)",
                title: song.title,
                subtitle: song.albumTitle.map { "\(song.artistName) • \($0)" } ?? song.artistName,
                artworkURL: song.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .song
            )
        }
        let albums = response.albums.map { album in
            AppleMusicItemMetadata(
                id: "album-\(album.id)",
                title: album.title,
                subtitle: album.artistName,
                artworkURL: album.artwork?.url(width: 400, height: 400)?.absoluteString,
                kind: .album
            )
        }

        return Array((songs + albums).prefix(limit))
    }

    func fetchLibraryAlbums(limit: Int) async throws -> [AppleMusicItemMetadata] {
        let response = try await fetchLibraryResponse(path: "albums", limit: limit)
        return response.data.map { album in
            AppleMusicItemMetadata(
                id: "library-album-\(album.id)",
                title: album.attributes?.name ?? "Unknown Album",
                subtitle: album.attributes?.artistName,
                artworkURL: album.attributes?.artwork?.sizedURL(width: 400, height: 400),
                kind: .album
            )
        }
    }

    func fetchLibraryPlaylists(limit: Int) async throws -> [AppleMusicItemMetadata] {
        let response = try await fetchLibraryResponse(path: "playlists", limit: limit)
        return response.data.map { playlist in
            AppleMusicItemMetadata(
                id: "library-playlist-\(playlist.id)",
                title: playlist.attributes?.name ?? "Unknown Playlist",
                subtitle: playlist.attributes?.curatorName,
                artworkURL: playlist.attributes?.artwork?.sizedURL(width: 400, height: 400),
                kind: .playlist
            )
        }
    }

    func fetchLibraryArtists(limit: Int) async throws -> [AppleMusicItemMetadata] {
        let response = try await fetchLibraryResponse(path: "artists", limit: limit)
        return response.data.map { artist in
            AppleMusicItemMetadata(
                id: "library-artist-\(artist.id)",
                title: artist.attributes?.name ?? "Unknown Artist",
                subtitle: "Artist",
                artworkURL: artist.attributes?.artwork?.sizedURL(width: 400, height: 400),
                kind: .artist
            )
        }
    }

    func fetchLibrarySongs(limit: Int) async throws -> [AppleMusicItemMetadata] {
        let response = try await fetchLibraryResponse(path: "songs", limit: limit)
        return response.data.map { song in
            let artistName = song.attributes?.artistName
            let albumName = song.attributes?.albumName

            return AppleMusicItemMetadata(
                id: "library-song-\(song.id)",
                title: song.attributes?.name ?? "Unknown Song",
                subtitle: albumName.map { albumName in
                    [artistName, albumName].compactMap(\.self).joined(separator: " • ")
                } ?? artistName,
                artworkURL: song.attributes?.artwork?.sizedURL(width: 400, height: 400),
                kind: .song
            )
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
}

private struct AppleMusicServiceMetadata: Sendable {
    var storefrontCountryCode: String
    var canPlayCatalogContent: Bool
    var canBecomeSubscriber: Bool
    var hasCloudLibraryEnabled: Bool
}

private struct AppleMusicItemMetadata: Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var artworkURL: String?
    var kind: AppleMusicItemKind
}

private enum AppleMusicItemKind: Sendable {
    case album
    case artist
    case playlist
    case song

    var sonoicKind: SonoicSourceItem.Kind {
        switch self {
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
}

private nonisolated struct AppleMusicLibraryResponse: Decodable {
    var data: [AppleMusicLibraryResource]
}

private nonisolated struct AppleMusicLibraryResource: Decodable {
    var id: String
    var attributes: AppleMusicLibraryAttributes?
}

private nonisolated struct AppleMusicLibraryAttributes: Decodable {
    var name: String?
    var artistName: String?
    var albumName: String?
    var curatorName: String?
    var artwork: AppleMusicLibraryArtwork?
}

private nonisolated struct AppleMusicLibraryArtwork: Decodable {
    var url: String?

    func sizedURL(width: Int, height: Int) -> String? {
        url?
            .replacingOccurrences(of: "{w}", with: "\(width)")
            .replacingOccurrences(of: "{h}", with: "\(height)")
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
