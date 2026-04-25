import Foundation
import MusicKit

struct SonoicAppleMusicCatalogSearchClient {
    enum ClientError: LocalizedError {
        case unauthorized(MusicAuthorization.Status)

        var errorDescription: String? {
            switch self {
            case let .unauthorized(status):
                "Apple Music access is \(status.sonoicDisplayName.lowercased())."
            }
        }
    }

    func searchCatalog(term: String) async throws -> [SonoicSourceItem] {
        guard MusicAuthorization.currentStatus == .authorized else {
            let status = await MusicAuthorization.request()
            guard status == .authorized else {
                throw ClientError.unauthorized(status)
            }

            return try await searchCatalog(term: term)
        }

        var request = MusicCatalogSearchRequest(
            term: term,
            types: [Song.self, Album.self]
        )
        request.limit = 8

        let response = try await request.response()
        let songs = response.songs.map { song in
            SonoicSourceItem.catalogMetadata(
                id: "song-\(song.id)",
                title: song.title,
                subtitle: song.albumTitle.map { "\(song.artistName) • \($0)" } ?? song.artistName,
                artworkURL: song.artwork?.url(width: 400, height: 400)?.absoluteString,
                service: .appleMusic
            )
        }
        let albums = response.albums.map { album in
            SonoicSourceItem.catalogMetadata(
                id: "album-\(album.id)",
                title: album.title,
                subtitle: album.artistName,
                artworkURL: album.artwork?.url(width: 400, height: 400)?.absoluteString,
                service: .appleMusic
            )
        }

        return Array((songs + albums).prefix(8))
    }
}

private extension MusicAuthorization.Status {
    nonisolated var sonoicDisplayName: String {
        switch self {
        case .notDetermined:
            "Not Determined"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .authorized:
            "Authorized"
        @unknown default:
            "Unavailable"
        }
    }
}
