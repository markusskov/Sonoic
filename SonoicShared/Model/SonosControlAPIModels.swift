import Foundation

enum SonosControlAPIMode: String, Codable, CaseIterable, Equatable {
    case off
    case diagnosticsOnly
    case fallback
    case preferred

    var canSendCommands: Bool {
        self == .fallback || self == .preferred
    }
}

struct SonosControlAPISettings: Codable, Equatable {
    var mode: SonosControlAPIMode
    var selectedHouseholdID: String?
    var selectedGroupID: String?

    static let disabled = SonosControlAPISettings(
        mode: .off,
        selectedHouseholdID: nil,
        selectedGroupID: nil
    )
}

struct SonosControlAPIState: Equatable {
    enum AuthorizationStatus: Equatable {
        case notConfigured
        case ready
        case expired
    }

    var settings: SonosControlAPISettings
    var authorizationStatus: AuthorizationStatus
    var lastErrorDetail: String?
    var lastCommandDescription: String?
    var lastUpdatedAt: Date?

    static let disabled = SonosControlAPIState(
        settings: .disabled,
        authorizationStatus: .notConfigured,
        lastErrorDetail: nil,
        lastCommandDescription: nil,
        lastUpdatedAt: nil
    )

    var canSendCommands: Bool {
        settings.mode.canSendCommands && authorizationStatus == .ready
    }
}

struct SonosControlAPITargetIdentity: Codable, Equatable {
    var householdID: String
    var groupID: String
    var playerID: String?
    var coordinatorPlayerID: String?
    var updatedAt: Date
}

struct SonosControlAPIHouseholdsResponse: Codable, Equatable {
    var households: [SonosControlAPIHousehold]
}

struct SonosControlAPIHousehold: Codable, Equatable, Identifiable {
    var id: String
}

struct SonosControlAPIGroupsResponse: Codable, Equatable {
    var groups: [SonosControlAPIGroup]
    var players: [SonosControlAPIPlayer]
}

struct SonosControlAPIGroup: Codable, Equatable, Identifiable {
    var id: String
    var name: String?
    var coordinatorId: String?
    var playerIds: [String]
}

struct SonosControlAPIPlayer: Codable, Equatable, Identifiable {
    var id: String
    var name: String?
    var roomName: String?
    var deviceIds: [String]?
}

struct SonosControlAPIFavoritesResponse: Codable, Equatable {
    var version: String?
    var favorites: [SonosControlAPIFavorite]
}

struct SonosControlAPIFavorite: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var description: String?
    var imageUrl: String?
    var service: SonosControlAPIService?
}

struct SonosControlAPIPlaylistsResponse: Codable, Equatable {
    var version: String?
    var playlists: [SonosControlAPIPlaylist]
}

struct SonosControlAPIPlaylist: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var type: String?
    var trackCount: Int?
}

struct SonosControlAPIService: Codable, Equatable {
    var id: String?
    var name: String?
}

enum SonosControlAPIPlaybackState: String, Codable, Equatable {
    case idle = "PLAYBACK_STATE_IDLE"
    case buffering = "PLAYBACK_STATE_BUFFERING"
    case paused = "PLAYBACK_STATE_PAUSED"
    case playing = "PLAYBACK_STATE_PLAYING"
}

struct SonosControlAPIPlaybackStatus: Codable, Equatable {
    var playbackState: SonosControlAPIPlaybackState
    var isDucking: Bool?
    var queueVersion: String?
    var itemId: String?
    var positionMillis: Int?
    var previousItemId: String?
    var previousPositionMillis: Int?
    var playModes: SonosControlAPIPlayModes?
    var availablePlaybackActions: SonosControlAPIPlaybackActions?
}

struct SonosControlAPIPlayModes: Codable, Equatable {
    var repeatEnabled: Bool?
    var repeatOne: Bool?
    var shuffle: Bool?
    var crossfade: Bool?

    enum CodingKeys: String, CodingKey {
        case repeatEnabled = "repeat"
        case repeatOne
        case shuffle
        case crossfade
    }
}

struct SonosControlAPIPlaybackActions: Codable, Equatable {
    var canSkip: Bool?
    var canSkipBack: Bool?
    var canSeek: Bool?
    var canPause: Bool?
    var canStop: Bool?
    var canRepeat: Bool?
    var canRepeatOne: Bool?
    var canCrossfade: Bool?
    var canShuffle: Bool?
}

struct SonosControlAPILoadFavoriteRequest: Codable, Equatable {
    var favoriteId: String
}

struct SonosControlAPILoadPlaylistRequest: Codable, Equatable {
    var playlistId: String
}

struct SonosControlAPISeekRequest: Codable, Equatable {
    var positionMillis: Int
    var itemId: String?
}

struct SonosControlAPISeekRelativeRequest: Codable, Equatable {
    var deltaMillis: Int
    var itemId: String?
}

struct SonosControlAPIErrorResponse: Codable, Equatable {
    var errorCode: String?
    var reason: String?
    var message: String?
}
