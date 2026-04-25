import Foundation

struct SonoicSource: Identifiable, Equatable {
    enum Status: String, Equatable {
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
            return isCurrent ? "Playing now" : "Available in Sonoic"
        }

        return parts.joined(separator: " • ")
    }
}

enum SonoicPlaybackCapability: Equatable {
    case sonosNative(SonosFavoriteItem)
    case metadataOnly
    case unsupported

    var canPlay: Bool {
        if case .sonosNative = self {
            true
        } else {
            false
        }
    }
}

struct SonoicSourceItem: Identifiable, Equatable {
    enum Origin: String, Equatable {
        case catalogSearch
        case favorite
        case recentPlay
    }

    var id: String
    var title: String
    var subtitle: String?
    var artworkURL: String?
    var artworkIdentifier: String?
    var service: SonosServiceDescriptor
    var origin: Origin
    var playbackCapability: SonoicPlaybackCapability

    init(
        id: String,
        title: String,
        subtitle: String?,
        artworkURL: String?,
        artworkIdentifier: String?,
        service: SonosServiceDescriptor,
        origin: Origin,
        playbackCapability: SonoicPlaybackCapability
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.artworkIdentifier = artworkIdentifier
        self.service = service
        self.origin = origin
        self.playbackCapability = playbackCapability
    }

    init(favorite: SonosFavoriteItem) {
        let playableFavorite = favorite.playbackURI.sonoicNonEmptyTrimmed.map { playbackURI in
            SonosFavoriteItem(
                id: favorite.id,
                title: favorite.title,
                subtitle: favorite.subtitle,
                artworkURL: favorite.artworkURL,
                service: favorite.service,
                playbackURI: playbackURI,
                playbackMetadataXML: favorite.playbackMetadataXML,
                kind: favorite.kind
            )
        }

        self.init(
            id: "favorite-\(favorite.id)",
            title: favorite.title,
            subtitle: favorite.subtitle ?? favorite.service?.name,
            artworkURL: favorite.artworkURL,
            artworkIdentifier: nil,
            service: favorite.service ?? .genericStreaming,
            origin: .favorite,
            playbackCapability: playableFavorite.map(SonoicPlaybackCapability.sonosNative) ?? .unsupported
        )
    }

    init(recentPlay: SonoicRecentPlayItem) {
        self.init(
            id: "recent-\(recentPlay.id)",
            title: recentPlay.title,
            subtitle: recentPlay.subtitle ?? recentPlay.sourceName,
            artworkURL: recentPlay.artworkURL,
            artworkIdentifier: recentPlay.artworkIdentifier,
            service: recentPlay.service ?? .genericStreaming,
            origin: .recentPlay,
            playbackCapability: recentPlay.replayFavorite.map(SonoicPlaybackCapability.sonosNative) ?? .metadataOnly
        )
    }

    static func catalogSearchPlaceholder(
        query: String,
        service: SonosServiceDescriptor
    ) -> SonoicSourceItem? {
        guard let normalizedQuery = query.sonoicNonEmptyTrimmed else {
            return nil
        }

        return SonoicSourceItem(
            id: "catalog-\(service.id)-\(normalizedQuery.lowercased())",
            title: normalizedQuery,
            subtitle: "\(service.name) catalog search",
            artworkURL: nil,
            artworkIdentifier: nil,
            service: service,
            origin: .catalogSearch,
            playbackCapability: .metadataOnly
        )
    }
}
