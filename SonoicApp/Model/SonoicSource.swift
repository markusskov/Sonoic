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
            "Playable on Sonos"
        case .metadataOnly:
            "Metadata Only"
        case .unsupported:
            "Unsupported"
        }
    }

    var disabledReason: String? {
        switch self {
        case .sonosNative:
            nil
        case .metadataOnly:
            "Sonoic can show this item, but needs a Sonos-native playback payload before it can start playback."
        case .unsupported:
            "This item does not include enough Sonos playback data."
        }
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
    var service: SonosServiceDescriptor
    var origin: Origin
    var kind: Kind
    var playbackCapability: SonoicPlaybackCapability

    init(
        id: String,
        title: String,
        subtitle: String?,
        artworkURL: String?,
        artworkIdentifier: String?,
        serviceItemID: String? = nil,
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
        service: SonosServiceDescriptor
    ) -> SonoicSourceItem {
        SonoicSourceItem(
            id: "catalog-\(service.id)-\(id)",
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            artworkIdentifier: nil,
            serviceItemID: id,
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
        origin: Origin
    ) -> SonoicSourceItem {
        SonoicSourceItem(
            id: "\(origin.rawValue)-\(SonosServiceDescriptor.appleMusic.id)-\(kind.rawValue)-\(id)",
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            artworkIdentifier: nil,
            serviceItemID: id,
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
    var items: [SonoicSourceItem]
    var status: Status

    init(
        query: String = "",
        service: SonosServiceDescriptor,
        items: [SonoicSourceItem]? = nil,
        status: Status = .idle
    ) {
        self.query = query
        self.items = items ?? []
        self.status = status
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

    init(
        destination: SonoicAppleMusicLibraryDestination,
        items: [SonoicSourceItem] = [],
        status: Status = .idle
    ) {
        self.destination = destination
        self.items = items
        self.status = status
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

    init(
        item: SonoicSourceItem,
        sections: [SonoicAppleMusicItemDetailSection] = [],
        status: Status = .idle
    ) {
        self.item = item
        self.sections = sections
        self.status = status
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
