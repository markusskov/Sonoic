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

    func playbackStatus(
        groupID: String,
        accessToken: String
    ) async throws -> SonosControlAPIPlaybackStatus {
        try await transport.get(
            "/groups/\(groupID)/playback",
            accessToken: accessToken
        )
    }

    func play(groupID: String, accessToken: String) async throws {
        try await transport.post(
            "/groups/\(groupID)/playback/play",
            accessToken: accessToken
        )
    }

    func pause(groupID: String, accessToken: String) async throws {
        try await transport.post(
            "/groups/\(groupID)/playback/pause",
            accessToken: accessToken
        )
    }

    func togglePlayPause(groupID: String, accessToken: String) async throws {
        try await transport.post(
            "/groups/\(groupID)/playback/togglePlayPause",
            accessToken: accessToken
        )
    }

    func skipToNextTrack(groupID: String, accessToken: String) async throws {
        try await transport.post(
            "/groups/\(groupID)/playback/skipToNextTrack",
            accessToken: accessToken
        )
    }

    func skipToPreviousTrack(groupID: String, accessToken: String) async throws {
        try await transport.post(
            "/groups/\(groupID)/playback/skipToPreviousTrack",
            accessToken: accessToken
        )
    }

    func seek(
        groupID: String,
        positionMillis: Int,
        itemID: String?,
        accessToken: String
    ) async throws {
        try await transport.post(
            "/groups/\(groupID)/playback/seek",
            accessToken: accessToken,
            body: SonosControlAPISeekRequest(
                positionMillis: max(0, positionMillis),
                itemId: itemID?.sonoicNonEmptyTrimmed
            )
        )
    }

    func seekRelative(
        groupID: String,
        deltaMillis: Int,
        itemID: String?,
        accessToken: String
    ) async throws {
        try await transport.post(
            "/groups/\(groupID)/playback/seekRelative",
            accessToken: accessToken,
            body: SonosControlAPISeekRelativeRequest(
                deltaMillis: deltaMillis,
                itemId: itemID?.sonoicNonEmptyTrimmed
            )
        )
    }
}
