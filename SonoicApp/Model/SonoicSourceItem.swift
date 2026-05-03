import Foundation

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
    var hasVerifiedPayloadIDMatch = false

    var id: String {
        payload.id
    }

    var verifiedFavoriteObjectID: String? {
        hasVerifiedPayloadIDMatch ? payload.id : nil
    }
}

struct SonoicSourceItemReference: Hashable, Sendable {
    var serviceID: String
    var catalogID: String?
    var libraryID: String?
    var kind: SonoicSourceItem.Kind

    init(
        serviceID: String,
        catalogID: String?,
        libraryID: String?,
        kind: SonoicSourceItem.Kind
    ) {
        self.serviceID = serviceID
        self.catalogID = catalogID
        self.libraryID = libraryID
        self.kind = kind
    }

    static func appleMusic(
        catalogID: String?,
        libraryID: String?,
        kind: SonoicSourceItem.Kind
    ) -> SonoicSourceItemReference {
        SonoicSourceItemReference(
            serviceID: SonosServiceDescriptor.appleMusic.id,
            catalogID: catalogID,
            libraryID: libraryID,
            kind: kind
        )
    }

    func routedID(for origin: SonoicSourceItem.Origin) -> String? {
        switch origin {
        case .catalogSearch:
            catalogID ?? libraryID
        case .library:
            libraryID ?? catalogID
        case .favorite, .recentPlay:
            libraryID ?? catalogID
        }
    }

    func detailCacheKey(for origin: SonoicSourceItem.Origin) -> String {
        [
            serviceID,
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
    var sourceReference: SonoicSourceItemReference?
    var externalURL: String?
    var service: SonosServiceDescriptor
    var origin: Origin
    var kind: Kind
    var playbackCapability: SonoicPlaybackCapability
    var duration: TimeInterval?

    var sourceDetailCacheKey: String {
        sourceReference?.detailCacheKey(for: origin) ?? id
    }

    init(
        id: String,
        title: String,
        subtitle: String?,
        artworkURL: String?,
        artworkIdentifier: String?,
        serviceItemID: String? = nil,
        sourceReference: SonoicSourceItemReference? = nil,
        externalURL: String? = nil,
        service: SonosServiceDescriptor,
        origin: Origin,
        kind: Kind = .unknown,
        playbackCapability: SonoicPlaybackCapability,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.artworkIdentifier = artworkIdentifier
        self.serviceItemID = serviceItemID
        self.sourceReference = sourceReference
        self.externalURL = externalURL
        self.service = service
        self.origin = origin
        self.kind = kind
        self.playbackCapability = playbackCapability
        self.duration = duration
    }

    init(favorite: SonosFavoriteItem) {
        let parsedReference = Self.appleMusicServiceReference(from: favorite.playbackURI)
        let kind = parsedReference?.kind ?? SonoicSourceItem.Kind(favoriteKind: favorite.kind)
        let serviceItemID = parsedReference?.id
        let sourceReference = favorite.service?.kind == .appleMusic ? SonoicSourceItemReference.appleMusic(
            catalogID: serviceItemID,
            libraryID: nil,
            kind: kind
        ) : nil

        self.init(
            id: "favorite-\(favorite.id)",
            title: favorite.title,
            subtitle: favorite.subtitle ?? favorite.service?.name,
            artworkURL: favorite.artworkURL,
            artworkIdentifier: nil,
            serviceItemID: serviceItemID,
            sourceReference: sourceReference,
            service: favorite.service ?? .genericStreaming,
            origin: .favorite,
            kind: kind,
            playbackCapability: favorite.playablePayload.map(SonoicPlaybackCapability.sonosNative) ?? .unsupported
        )
    }

    init(recentPlay: SonoicRecentPlayItem) {
        let playablePayload = recentPlay.replayFavorite?.playablePayload
        let parsedReference = recentPlay.playbackURI.flatMap(Self.appleMusicServiceReference)
        let kind = recentPlay.sourceItemKindRawValue.flatMap(SonoicSourceItem.Kind.init(rawValue:))
            ?? parsedReference?.kind
            ?? SonoicSourceItem.Kind(favoriteKind: recentPlay.favoriteKind)
        let serviceItemID = recentPlay.sourceItemID ?? recentPlay.appleMusicCatalogID ?? parsedReference?.id
        let catalogID = recentPlay.appleMusicCatalogID
            ?? (recentPlay.appleMusicLibraryID == nil ? serviceItemID : nil)
        let sourceReference = recentPlay.service?.kind == .appleMusic ? SonoicSourceItemReference.appleMusic(
            catalogID: catalogID,
            libraryID: recentPlay.appleMusicLibraryID,
            kind: kind
        ) : nil

        self.init(
            id: "recent-\(recentPlay.id)",
            title: recentPlay.title,
            subtitle: recentPlay.subtitle ?? recentPlay.sourceName,
            artworkURL: recentPlay.artworkURL,
            artworkIdentifier: recentPlay.artworkIdentifier,
            serviceItemID: serviceItemID,
            sourceReference: sourceReference,
            service: recentPlay.service ?? .genericStreaming,
            origin: .recentPlay,
            kind: kind,
            playbackCapability: playablePayload.map(SonoicPlaybackCapability.sonosNative) ?? .metadataOnly
        )
    }

    private static func appleMusicServiceReference(from uri: String) -> (id: String, kind: SonoicSourceItem.Kind)? {
        let normalizedURI = uri.replacingOccurrences(of: "&amp;", with: "&")
        let lowercasedURI = normalizedURI.lowercased()
        let prefixes = [
            ("playlist%3a", SonoicSourceItem.Kind.playlist),
            ("album%3a", SonoicSourceItem.Kind.album),
            ("artist%3a", SonoicSourceItem.Kind.artist),
            ("song%3a", SonoicSourceItem.Kind.song),
        ]

        for (prefix, kind) in prefixes {
            guard let prefixRange = lowercasedURI.range(of: prefix) else {
                continue
            }

            let valueStartOffset = lowercasedURI.distance(from: lowercasedURI.startIndex, to: prefixRange.upperBound)
            let valueStartIndex = normalizedURI.index(normalizedURI.startIndex, offsetBy: valueStartOffset)
            let valueAfterPrefix = normalizedURI[valueStartIndex...]
            guard let id = valueAfterPrefix
                .split(separator: "?", maxSplits: 1)
                .first
                .map(String.init)?
                .removingPercentEncoding?
                .sonoicNonEmptyTrimmed
            else {
                return nil
            }

            return (id, kind)
        }

        return nil
    }

    static func catalogMetadata(
        id: String,
        title: String,
        subtitle: String?,
        artworkURL: String?,
        kind: Kind,
        service: SonosServiceDescriptor,
        externalURL: String? = nil,
        duration: TimeInterval? = nil
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
            playbackCapability: .metadataOnly,
            duration: duration
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
        externalURL: String? = nil,
        duration: TimeInterval? = nil
    ) -> SonoicSourceItem {
        SonoicSourceItem(
            id: "\(origin.rawValue)-\(SonosServiceDescriptor.appleMusic.id)-\(kind.rawValue)-\(id)",
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            artworkIdentifier: nil,
            serviceItemID: id,
            sourceReference: SonoicSourceItemReference.appleMusic(
                catalogID: catalogID,
                libraryID: libraryID,
                kind: kind
            ),
            externalURL: externalURL,
            service: .appleMusic,
            origin: origin,
            kind: kind,
            playbackCapability: .metadataOnly,
            duration: duration
        )
    }
}

private extension SonoicSourceItem.Kind {
    init(favoriteKind: SonosFavoriteItem.Kind?) {
        switch favoriteKind {
        case .collection:
            self = .playlist
        case .item, .none:
            self = .song
        }
    }
}
