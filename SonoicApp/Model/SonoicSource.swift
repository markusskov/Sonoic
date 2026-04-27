import Foundation

struct SonoicSource: Identifiable, Equatable {
    enum Status: String, Equatable {
        case availableForSetup
        case visibleThroughSonos
    }

    var service: SonosServiceDescriptor
    var favoriteCount: Int
    var collectionCount: Int
    var recentCount: Int
    var isCurrent: Bool
    var status: Status = .visibleThroughSonos

    var id: String {
        service.id
    }

    var detailText: String {
        var parts: [String] = []

        if favoriteCount == 1 {
            parts.append("1 favorite")
        } else if favoriteCount > 1 {
            parts.append("\(favoriteCount) favorites")
        }

        if collectionCount == 1 {
            parts.append("1 collection")
        } else if collectionCount > 1 {
            parts.append("\(collectionCount) collections")
        }

        if recentCount == 1 {
            parts.append("1 recent play")
        } else if recentCount > 1 {
            parts.append("\(recentCount) recent plays")
        }

        guard !parts.isEmpty else {
            if status == .availableForSetup {
                return "Not connected yet"
            }

            return isCurrent ? "Playing now" : "Available in Sonoic"
        }

        return parts.joined(separator: " • ")
    }
}

enum SonoicPlaybackCapability: Equatable {
    case sonosNative(SonosPlayablePayload)
    case metadataOnly
    case unsupported

    var canPlay: Bool {
        if case .sonosNative = self {
            true
        } else {
            false
        }
    }

    var displayTitle: String {
        switch self {
        case .sonosNative:
            "Ready for Sonos"
        case .metadataOnly:
            "Unavailable"
        case .unsupported:
            "Unavailable"
        }
    }

    var disabledReason: String? {
        switch self {
        case .sonosNative:
            nil
        case .metadataOnly:
            "Needs a Sonos playback match."
        case .unsupported:
            "Missing playback data."
        }
    }
}

struct SonoicSonosPlaybackCandidate: Identifiable, Equatable {
    enum Confidence: String, Equatable {
        case exact
        case likely

        var shortTitle: String {
            switch self {
            case .exact:
                "Favorite Match"
            case .likely:
                "Possible Match"
            }
        }

        var title: String {
            switch self {
            case .exact:
                "Exact Favorite Match"
            case .likely:
                "Likely Favorite Match"
            }
        }

        var badgeTitle: String {
            switch self {
            case .exact:
                "Favorite match"
            case .likely:
                "Possible favorite match"
            }
        }
    }

    var payload: SonosPlayablePayload
    var confidence: Confidence
    var detail: String

    var id: String {
        payload.id
    }
}

struct SonoicAppleMusicItemIdentity: Hashable, Sendable {
    var catalogID: String?
    var libraryID: String?
    var kind: SonoicSourceItem.Kind

    var primaryID: String? {
        catalogID ?? libraryID
    }

    func routedID(for origin: SonoicSourceItem.Origin) -> String? {
        switch origin {
        case .catalogSearch:
            catalogID ?? libraryID
        case .library:
            libraryID ?? catalogID
        case .favorite, .recentPlay:
            primaryID
        }
    }

    func detailCacheKey(for origin: SonoicSourceItem.Origin) -> String {
        [
            "apple-music",
            origin.rawValue,
            kind.rawValue,
            catalogID ?? "no-catalog-id",
            libraryID ?? "no-library-id"
        ].joined(separator: ":")
    }
}

struct SonoicSourceItem: Identifiable, Equatable {
    enum Origin: String, Equatable, Sendable {
        case catalogSearch
        case favorite
        case library
        case recentPlay
    }

    enum Kind: String, Equatable, Sendable {
        case album
        case artist
        case playlist
        case song
        case station
        case unknown

        var title: String {
            switch self {
            case .album:
                "Album"
            case .artist:
                "Artist"
            case .playlist:
                "Playlist"
            case .song:
                "Song"
            case .station:
                "Station"
            case .unknown:
                "Item"
            }
        }

        var systemImage: String {
            switch self {
            case .album:
                "rectangle.stack"
            case .artist:
                "music.mic"
            case .playlist:
                "music.note.list"
            case .song:
                "music.note"
            case .station:
                "dot.radiowaves.left.and.right"
            case .unknown:
                "music.note"
            }
        }
    }

    var id: String
    var title: String
    var subtitle: String?
    var artworkURL: String?
    var artworkIdentifier: String?
    var serviceItemID: String?
    var appleMusicIdentity: SonoicAppleMusicItemIdentity?
    var externalURL: String?
    var service: SonosServiceDescriptor
    var origin: Origin
    var kind: Kind
    var playbackCapability: SonoicPlaybackCapability

    var appleMusicDetailCacheKey: String {
        appleMusicIdentity?.detailCacheKey(for: origin) ?? id
    }

    init(
        id: String,
        title: String,
        subtitle: String?,
        artworkURL: String?,
        artworkIdentifier: String?,
        serviceItemID: String? = nil,
        appleMusicIdentity: SonoicAppleMusicItemIdentity? = nil,
        externalURL: String? = nil,
        service: SonosServiceDescriptor,
        origin: Origin,
        kind: Kind = .unknown,
        playbackCapability: SonoicPlaybackCapability
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.artworkIdentifier = artworkIdentifier
        self.serviceItemID = serviceItemID
        self.appleMusicIdentity = appleMusicIdentity
        self.externalURL = externalURL
        self.service = service
        self.origin = origin
        self.kind = kind
        self.playbackCapability = playbackCapability
    }

    init(favorite: SonosFavoriteItem) {
        self.init(
            id: "favorite-\(favorite.id)",
            title: favorite.title,
            subtitle: favorite.subtitle ?? favorite.service?.name,
            artworkURL: favorite.artworkURL,
            artworkIdentifier: nil,
            service: favorite.service ?? .genericStreaming,
            origin: .favorite,
            kind: favorite.isCollectionLike ? .playlist : .unknown,
            playbackCapability: favorite.playablePayload.map(SonoicPlaybackCapability.sonosNative) ?? .unsupported
        )
    }

    init(recentPlay: SonoicRecentPlayItem) {
        let playablePayload = recentPlay.replayFavorite?.playablePayload

        self.init(
            id: "recent-\(recentPlay.id)",
            title: recentPlay.title,
            subtitle: recentPlay.subtitle ?? recentPlay.sourceName,
            artworkURL: recentPlay.artworkURL,
            artworkIdentifier: recentPlay.artworkIdentifier,
            service: recentPlay.service ?? .genericStreaming,
            origin: .recentPlay,
            kind: .unknown,
            playbackCapability: playablePayload.map(SonoicPlaybackCapability.sonosNative) ?? .metadataOnly
        )
    }

    static func catalogMetadata(
        id: String,
        title: String,
        subtitle: String?,
        artworkURL: String?,
        kind: Kind,
        service: SonosServiceDescriptor,
        externalURL: String? = nil
    ) -> SonoicSourceItem {
        SonoicSourceItem(
            id: "catalog-\(service.id)-\(id)",
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            artworkIdentifier: nil,
            serviceItemID: id,
            externalURL: externalURL,
            service: service,
            origin: .catalogSearch,
            kind: kind,
            playbackCapability: .metadataOnly
        )
    }

    static func appleMusicMetadata(
        id: String,
        title: String,
        subtitle: String?,
        artworkURL: String?,
        kind: Kind,
        origin: Origin,
        catalogID: String? = nil,
        libraryID: String? = nil,
        externalURL: String? = nil
    ) -> SonoicSourceItem {
        SonoicSourceItem(
            id: "\(origin.rawValue)-\(SonosServiceDescriptor.appleMusic.id)-\(kind.rawValue)-\(id)",
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            artworkIdentifier: nil,
            serviceItemID: id,
            appleMusicIdentity: SonoicAppleMusicItemIdentity(
                catalogID: catalogID,
                libraryID: libraryID,
                kind: kind
            ),
            externalURL: externalURL,
            service: .appleMusic,
            origin: origin,
            kind: kind,
            playbackCapability: .metadataOnly
        )
    }
}

struct SonoicSourceSearchState: Equatable {
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var query: String
    var scope: SonoicSourceSearchScope
    var items: [SonoicSourceItem]
    var status: Status
    var lastUpdatedAt: Date?

    init(
        query: String = "",
        service: SonosServiceDescriptor,
        scope: SonoicSourceSearchScope = .all,
        items: [SonoicSourceItem]? = nil,
        status: Status = .idle,
        lastUpdatedAt: Date? = nil
    ) {
        self.query = query
        self.scope = scope
        self.items = items ?? []
        self.status = status
        self.lastUpdatedAt = lastUpdatedAt
    }

    var hasQuery: Bool {
        query.sonoicNonEmptyTrimmed != nil
    }

    var isSearching: Bool {
        status == .loading
    }

    var failureDetail: String? {
        if case let .failed(detail) = status {
            detail
        } else {
            nil
        }
    }
}

struct SonoicSourceItemPage: Equatable {
    var items: [SonoicSourceItem]
    var nextOffset: Int?
}

enum SonoicSourceSearchScope: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case songs
    case artists
    case albums
    case playlists

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            "All"
        case .songs:
            "Songs"
        case .artists:
            "Artists"
        case .albums:
            "Albums"
        case .playlists:
            "Playlists"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "magnifyingglass"
        case .songs:
            "music.note"
        case .artists:
            "music.mic"
        case .albums:
            "rectangle.stack"
        case .playlists:
            "music.note.list"
        }
    }

    var resultSubtitle: String {
        switch self {
        case .all:
            "Apple Music metadata only. Sonoic still needs Sonos-native payloads before playback."
        case .songs:
            "Song metadata only. Sonoic enables playback only when it finds a Sonos-native payload."
        case .artists:
            "Artist metadata only. Use artist pages to browse related songs and albums."
        case .albums:
            "Album metadata only. Open an album to inspect tracks."
        case .playlists:
            "Playlist metadata only. Open a playlist to inspect tracks."
        }
    }
}

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
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var destination: SonoicAppleMusicLibraryDestination
    var items: [SonoicSourceItem]
    var status: Status
    var lastUpdatedAt: Date?
    var nextOffset: Int?

    init(
        destination: SonoicAppleMusicLibraryDestination,
        items: [SonoicSourceItem] = [],
        status: Status = .idle,
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
        status == .loading
    }

    var failureDetail: String? {
        if case let .failed(detail) = status {
            detail
        } else {
            nil
        }
    }

    var canLoadMore: Bool {
        nextOffset != nil
    }
}

struct SonoicAppleMusicRecentlyAddedState: Equatable {
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var items: [SonoicSourceItem]
    var status: Status
    var lastUpdatedAt: Date?

    init(
        items: [SonoicSourceItem] = [],
        status: Status = .idle,
        lastUpdatedAt: Date? = nil
    ) {
        self.items = items
        self.status = status
        self.lastUpdatedAt = lastUpdatedAt
    }

    var isLoading: Bool {
        status == .loading
    }

    var failureDetail: String? {
        if case let .failed(detail) = status {
            detail
        } else {
            nil
        }
    }
}

struct SonoicAppleMusicBrowseState: Equatable {
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var destination: SonoicAppleMusicBrowseDestination
    var sections: [SonoicAppleMusicItemDetailSection]
    var genres: [SonoicAppleMusicGenreItem]
    var status: Status
    var lastUpdatedAt: Date?

    init(
        destination: SonoicAppleMusicBrowseDestination,
        sections: [SonoicAppleMusicItemDetailSection] = [],
        genres: [SonoicAppleMusicGenreItem] = [],
        status: Status = .idle,
        lastUpdatedAt: Date? = nil
    ) {
        self.destination = destination
        self.sections = sections
        self.genres = genres
        self.status = status
        self.lastUpdatedAt = lastUpdatedAt
    }

    var isLoading: Bool {
        status == .loading
    }

    var failureDetail: String? {
        if case let .failed(detail) = status {
            detail
        } else {
            nil
        }
    }
}

struct SonoicAppleMusicGenreItem: Identifiable, Equatable {
    var id: String
    var title: String

    var subtitle: String {
        "Apple Music category"
    }
}

struct SonoicAppleMusicItemDetailState: Equatable {
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var item: SonoicSourceItem
    var sections: [SonoicAppleMusicItemDetailSection]
    var status: Status
    var lastUpdatedAt: Date?

    init(
        item: SonoicSourceItem,
        sections: [SonoicAppleMusicItemDetailSection] = [],
        status: Status = .idle,
        lastUpdatedAt: Date? = nil
    ) {
        self.item = item
        self.sections = sections
        self.status = status
        self.lastUpdatedAt = lastUpdatedAt
    }

    var isLoading: Bool {
        status == .loading
    }

    var failureDetail: String? {
        if case let .failed(detail) = status {
            detail
        } else {
            nil
        }
    }
}

struct SonoicAppleMusicItemDetailSection: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String?
    var items: [SonoicSourceItem]

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        items: [SonoicSourceItem]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.items = items
    }
}
