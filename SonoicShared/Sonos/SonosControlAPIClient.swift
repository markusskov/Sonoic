import Foundation

struct SonosControlAPIClient {
    private let transport: SonosControlAPITransport

    init(transport: SonosControlAPITransport = SonosControlAPITransport()) {
        self.transport = transport
    }

    static func playbackSessionCommandPath(sessionID: String, command: String) -> String {
        "/playbackSessions/\(sessionID)/playbackSession/\(command)"
    }

    func fetchCloudSnapshot(tokenSet: SonosOAuthTokenSet) async throws -> SonosControlAPICloudSnapshot {
        let householdsResponse = try await households(accessToken: tokenSet.accessToken)
        var groupsByHouseholdID: [String: SonosControlAPIGroupSnapshot] = [:]
        var favoritesByHouseholdID: [String: [SonosControlAPIFavorite]] = [:]
        var playlistsByHouseholdID: [String: [SonosControlAPIPlaylist]] = [:]
        var contentFetchDiagnosticsByHouseholdID: [String: SonosControlAPICloudContentFetchDiagnostics] = [:]

        for household in householdsResponse.households {
            let groupsResponse = try await groups(
                householdID: household.id,
                accessToken: tokenSet.accessToken
            )
            groupsByHouseholdID[household.id] = SonosControlAPIGroupSnapshot(
                groups: groupsResponse.groups,
                players: groupsResponse.players
            )

            var contentDiagnostics = SonosControlAPICloudContentFetchDiagnostics()
            do {
                let favoritesResponse = try await favorites(
                    householdID: household.id,
                    accessToken: tokenSet.accessToken
                )
                favoritesByHouseholdID[household.id] = favoritesResponse.favorites
                contentDiagnostics.favorites = .loaded(
                    count: favoritesResponse.favorites.count,
                    version: favoritesResponse.version
                )
            } catch {
                contentDiagnostics.favorites = Self.cloudContentFetchFailure(from: error)
            }

            do {
                let playlistsResponse = try await playlists(
                    householdID: household.id,
                    accessToken: tokenSet.accessToken
                )
                playlistsByHouseholdID[household.id] = playlistsResponse.playlists
                contentDiagnostics.playlists = .loaded(
                    count: playlistsResponse.playlists.count,
                    version: playlistsResponse.version
                )
            } catch {
                contentDiagnostics.playlists = Self.cloudContentFetchFailure(from: error)
            }
            contentFetchDiagnosticsByHouseholdID[household.id] = contentDiagnostics
        }

        return SonosControlAPICloudSnapshot(
            households: householdsResponse.households,
            groupsByHouseholdID: groupsByHouseholdID,
            favoritesByHouseholdID: favoritesByHouseholdID,
            playlistsByHouseholdID: playlistsByHouseholdID,
            contentFetchDiagnosticsByHouseholdID: contentFetchDiagnosticsByHouseholdID
        )
    }

    private static func cloudContentFetchFailure(
        from error: Error
    ) -> SonosControlAPICloudContentFetchResult {
        let isAuthorizationFailure: Bool
        if let transportError = error as? SonosControlAPITransport.TransportError {
            isAuthorizationFailure = transportError.isAuthorizationFailure
        } else {
            isAuthorizationFailure = false
        }

        return .failed(
            detail: Self.cloudContentFetchFailureDetail(from: error),
            isAuthorizationFailure: isAuthorizationFailure
        )
    }

    private static func cloudContentFetchFailureDetail(from error: Error) -> String {
        if let decodingError = error as? DecodingError {
            return decodingError.sonoicControlAPIDebugDescription
        }

        return error.localizedDescription
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

    func groupVolume(
        groupID: String,
        accessToken: String
    ) async throws -> SonosControlAPIVolumeState {
        try await transport.get(
            "/groups/\(groupID)/groupVolume",
            accessToken: accessToken
        )
    }

    func setGroupVolume(
        groupID: String,
        level: Int,
        accessToken: String
    ) async throws {
        try await transport.post(
            "/groups/\(groupID)/groupVolume",
            accessToken: accessToken,
            body: SonosControlAPISetVolumeRequest(volume: min(max(level, 0), 100))
        )
    }

    func setGroupMute(
        groupID: String,
        isMuted: Bool,
        accessToken: String
    ) async throws {
        try await transport.post(
            "/groups/\(groupID)/groupVolume/mute",
            accessToken: accessToken,
            body: SonosControlAPISetMuteRequest(muted: isMuted)
        )
    }

    func playerVolume(
        playerID: String,
        accessToken: String
    ) async throws -> SonosControlAPIVolumeState {
        try await transport.get(
            "/players/\(playerID)/playerVolume",
            accessToken: accessToken
        )
    }

    func setPlayerVolume(
        playerID: String,
        level: Int,
        accessToken: String
    ) async throws {
        try await transport.post(
            "/players/\(playerID)/playerVolume",
            accessToken: accessToken,
            body: SonosControlAPISetVolumeRequest(volume: min(max(level, 0), 100))
        )
    }

    func setPlayerMute(
        playerID: String,
        isMuted: Bool,
        accessToken: String
    ) async throws {
        try await transport.post(
            "/players/\(playerID)/playerVolume/mute",
            accessToken: accessToken,
            body: SonosControlAPISetMuteRequest(muted: isMuted)
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
            Self.playbackSessionCommandPath(sessionID: sessionID, command: "loadCloudQueue"),
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
            Self.playbackSessionCommandPath(sessionID: sessionID, command: "skipToItem"),
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

    func seekPlaybackSession(
        sessionID: String,
        itemID: String,
        positionMillis: Int,
        accessToken: String
    ) async throws {
        try await transport.post(
            Self.playbackSessionCommandPath(sessionID: sessionID, command: "seek"),
            accessToken: accessToken,
            body: SonosControlAPISeekRequest(
                positionMillis: max(0, positionMillis),
                itemId: itemID.sonoicNonEmptyTrimmed
            )
        )
    }

    func refreshCloudQueue(sessionID: String, accessToken: String) async throws {
        try await transport.post(
            Self.playbackSessionCommandPath(sessionID: sessionID, command: "refreshCloudQueue"),
            accessToken: accessToken
        )
    }
}

private extension DecodingError {
    nonisolated var sonoicControlAPIDebugDescription: String {
        switch self {
        case let .keyNotFound(key, context):
            return "Decoding missing key '\(key.stringValue)' at '\(context.sonoicControlAPICodingPathDescription)': \(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "Decoding missing value '\(String(describing: type))' at '\(context.sonoicControlAPICodingPathDescription)': \(context.debugDescription)"
        case let .typeMismatch(type, context):
            return "Decoding type mismatch '\(String(describing: type))' at '\(context.sonoicControlAPICodingPathDescription)': \(context.debugDescription)"
        case let .dataCorrupted(context):
            return "Decoding corrupted data at '\(context.sonoicControlAPICodingPathDescription)': \(context.debugDescription)"
        @unknown default:
            return localizedDescription
        }
    }
}

private extension DecodingError.Context {
    nonisolated var sonoicControlAPICodingPathDescription: String {
        guard !codingPath.isEmpty else {
            return "$"
        }

        return codingPath.map(\.stringValue).joined(separator: ".")
    }
}
