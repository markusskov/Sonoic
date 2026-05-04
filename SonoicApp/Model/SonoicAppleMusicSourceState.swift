import Foundation

enum SonoicAppleMusicLibraryDestination: String, CaseIterable, Identifiable, Equatable {
    case playlists
    case artists
    case albums
    case songs

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .playlists:
            "Playlists"
        case .artists:
            "Artists"
        case .albums:
            "Albums"
        case .songs:
            "Songs"
        }
    }

    var subtitle: String {
        switch self {
        case .playlists:
            "Saved Apple Music playlists"
        case .artists:
            "Saved Apple Music artists"
        case .albums:
            "Saved Apple Music albums"
        case .songs:
            "Saved Apple Music songs"
        }
    }

    var systemImage: String {
        switch self {
        case .playlists:
            "music.note.list"
        case .artists:
            "music.mic"
        case .albums:
            "rectangle.stack"
        case .songs:
            "music.note"
        }
    }

    var initialLoadLimit: Int {
        switch self {
        case .playlists, .albums:
            24
        case .artists, .songs:
            50
        }
    }
}

enum SonoicAppleMusicBrowseDestination: String, CaseIterable, Identifiable, Equatable {
    case popularRecommendations
    case categories
    case playlistsForYou
    case appleMusicPlaylists
    case newReleases
    case radioShows

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .popularRecommendations:
            "Popular Recommendations"
        case .categories:
            "Categories"
        case .playlistsForYou:
            "Playlists Created for You"
        case .appleMusicPlaylists:
            "Apple Music Playlists"
        case .newReleases:
            "New Releases"
        case .radioShows:
            "Radio Shows"
        }
    }

    var subtitle: String {
        switch self {
        case .popularRecommendations:
            "Editorial and listener-driven picks"
        case .categories:
            "Browse moods, genres, and activity lanes"
        case .playlistsForYou:
            "Personalized mixes when recommendations are wired"
        case .appleMusicPlaylists:
            "Curated playlists from Apple Music"
        case .newReleases:
            "Fresh albums and singles by service"
        case .radioShows:
            "Apple Music radio and hosted shows"
        }
    }

    var systemImage: String {
        switch self {
        case .popularRecommendations:
            "sparkles"
        case .categories:
            "square.grid.2x2"
        case .playlistsForYou:
            "person.crop.circle.badge.checkmark"
        case .appleMusicPlaylists:
            "music.note.list"
        case .newReleases:
            "calendar.badge.plus"
        case .radioShows:
            "dot.radiowaves.left.and.right"
        }
    }
}

struct SonoicAppleMusicLibraryState: Equatable {
    var destination: SonoicAppleMusicLibraryDestination
    var items: [SonoicSourceItem]
    var status: SonoicLoadStatus
    var lastUpdatedAt: Date?
    var nextOffset: Int?

    init(
        destination: SonoicAppleMusicLibraryDestination,
        items: [SonoicSourceItem] = [],
        status: SonoicLoadStatus = .idle,
        lastUpdatedAt: Date? = nil,
        nextOffset: Int? = nil
    ) {
        self.destination = destination
        self.items = items
        self.status = status
        self.lastUpdatedAt = lastUpdatedAt
        self.nextOffset = nextOffset
    }

    var isLoading: Bool {
        status.isLoading
    }

    var failureDetail: String? {
        status.failureDetail
    }

    var canLoadMore: Bool {
        nextOffset != nil
    }
}

struct SonoicAppleMusicRecentlyAddedState: Equatable {
    var items: [SonoicSourceItem]
    var status: SonoicLoadStatus
    var lastUpdatedAt: Date?

    init(
        items: [SonoicSourceItem] = [],
        status: SonoicLoadStatus = .idle,
        lastUpdatedAt: Date? = nil
    ) {
        self.items = items
        self.status = status
        self.lastUpdatedAt = lastUpdatedAt
    }

    var isLoading: Bool {
        status.isLoading
    }

    var failureDetail: String? {
        status.failureDetail
    }
}

struct SonoicAppleMusicBrowseState: Equatable {
    var destination: SonoicAppleMusicBrowseDestination
    var sections: [SonoicSourceItemDetailSection]
    var genres: [SonoicAppleMusicGenreItem]
    var status: SonoicLoadStatus
    var lastUpdatedAt: Date?

    init(
        destination: SonoicAppleMusicBrowseDestination,
        sections: [SonoicSourceItemDetailSection] = [],
        genres: [SonoicAppleMusicGenreItem] = [],
        status: SonoicLoadStatus = .idle,
        lastUpdatedAt: Date? = nil
    ) {
        self.destination = destination
        self.sections = sections
        self.genres = genres
        self.status = status
        self.lastUpdatedAt = lastUpdatedAt
    }

    var isLoading: Bool {
        status.isLoading
    }

    var failureDetail: String? {
        status.failureDetail
    }
}

struct SonoicAppleMusicGenreItem: Identifiable, Equatable {
    var id: String
    var title: String

    var subtitle: String {
        "Apple Music category"
    }
}
