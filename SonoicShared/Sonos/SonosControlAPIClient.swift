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

    func playbackMetadata(
        groupID: String,
        accessToken: String
    ) async throws -> SonosControlAPIMetadataStatus {
        try await transport.get(
            "/groups/\(groupID)/playbackMetadata",
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

    func createPlaybackSession(
        groupID: String,
        appID: String,
        appContext: String,
        accountID: String?,
        customData: String?,
        accessToken: String
    ) async throws -> SonosControlAPISessionStatus {
        try await transport.post(
            "/groups/\(groupID)/playbackSession",
            accessToken: accessToken,
            body: SonosControlAPICreateSessionRequest(
                appId: appID,
                appContext: appContext,
                accountId: accountID?.sonoicNonEmptyTrimmed,
                customData: customData?.sonoicNonEmptyTrimmed
            )
        )
    }

    func loadCloudQueue(
        sessionID: String,
        request: SonosControlAPILoadCloudQueueRequest,
        accessToken: String
    ) async throws {
        try await transport.post(
            "/sessions/\(sessionID)/playbackSession/loadCloudQueue",
            accessToken: accessToken,
            body: request
        )
    }

    func skipToItem(
        sessionID: String,
        itemID: String,
        queueVersion: String?,
        positionMillis: Int?,
        playOnCompletion: Bool?,
        trackMetadata: SonosControlAPITrack?,
        accessToken: String
    ) async throws {
        try await transport.post(
            "/sessions/\(sessionID)/playbackSession/skipToItem",
            accessToken: accessToken,
            body: SonosControlAPISkipToItemRequest(
                itemId: itemID,
                queueVersion: queueVersion?.sonoicNonEmptyTrimmed,
                positionMillis: positionMillis.map { max(0, $0) },
                playOnCompletion: playOnCompletion,
                trackMetadata: trackMetadata
            )
        )
    }

    func refreshCloudQueue(sessionID: String, accessToken: String) async throws {
        try await transport.post(
            "/sessions/\(sessionID)/playbackSession/refreshCloudQueue",
            accessToken: accessToken
        )
    }
}
