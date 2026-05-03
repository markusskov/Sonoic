import Foundation
@preconcurrency import MusicKit

extension SonoicMusicKitRequestGate {
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
                origin: .catalogSearch,
                duration: song.duration
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
}
