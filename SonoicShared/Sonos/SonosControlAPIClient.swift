import Foundation

struct SonosControlAPIClient {
    private let transport: SonosControlAPITransport

    init(transport: SonosControlAPITransport = SonosControlAPITransport()) {
        self.transport = transport
    }

    func households(accessToken: String) async throws -> SonosControlAPIHouseholdsResponse {
        try await transport.get(
            "/households",
            accessToken: accessToken
        )
    }

    func groups(
        householdID: String,
        accessToken: String
    ) async throws -> SonosControlAPIGroupsResponse {
        try await transport.get(
            "/households/\(householdID)/groups",
            accessToken: accessToken
        )
    }

    func favorites(
        householdID: String,
        accessToken: String
    ) async throws -> SonosControlAPIFavoritesResponse {
        try await transport.get(
            "/households/\(householdID)/favorites",
            accessToken: accessToken
        )
    }

    func playlists(
        householdID: String,
        accessToken: String
    ) async throws -> SonosControlAPIPlaylistsResponse {
        try await transport.get(
            "/households/\(householdID)/playlists",
            accessToken: accessToken
        )
    }

    func loadFavorite(
        groupID: String,
        favoriteID: String,
        accessToken: String
    ) async throws {
        try await transport.post(
            "/groups/\(groupID)/favorites",
            accessToken: accessToken,
            body: SonosControlAPILoadFavoriteRequest(favoriteId: favoriteID)
        )
    }

    func loadPlaylist(
        groupID: String,
        playlistID: String,
        accessToken: String
    ) async throws {
        try await transport.post(
            "/groups/\(groupID)/playlists",
            accessToken: accessToken,
            body: SonosControlAPILoadPlaylistRequest(playlistId: playlistID)
        )
    }
}
