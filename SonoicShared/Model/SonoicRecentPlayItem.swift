import Foundation

struct SonoicRecentPlayItem: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var artistName: String?
    var albumTitle: String?
    var sourceName: String
    var artworkURL: String?
    var artworkIdentifier: String?
    var service: SonosServiceDescriptor?
    var lastPlayedAt: Date
    var playbackURI: String?
    var playbackMetadataXML: String?
    var favoriteKind: SonosFavoriteItem.Kind?

    init(
        id: String,
        title: String,
        artistName: String?,
        albumTitle: String?,
        sourceName: String,
        artworkURL: String?,
        artworkIdentifier: String?,
        service: SonosServiceDescriptor?,
        lastPlayedAt: Date,
        playbackURI: String? = nil,
        playbackMetadataXML: String? = nil,
        favoriteKind: SonosFavoriteItem.Kind? = nil
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.sourceName = sourceName
        self.artworkURL = artworkURL
        self.artworkIdentifier = artworkIdentifier
        self.service = service
        self.lastPlayedAt = lastPlayedAt
        self.playbackURI = playbackURI
        self.playbackMetadataXML = playbackMetadataXML
        self.favoriteKind = favoriteKind
    }

    init?(snapshot: SonosNowPlayingSnapshot, observedAt: Date) {
        guard let title = snapshot.title.sonoicNonEmptyTrimmed,
              !Self.ignoredTitles.contains(title.lowercased())
        else {
            return nil
        }

        let sourceName = snapshot.sourceName.sonoicNonEmptyTrimmed ?? "Unknown Source"
        guard !Self.ignoredSourceNames.contains(sourceName.lowercased()) else {
            return nil
        }

        self.init(
            id: Self.fingerprint(
                title: title,
                artistName: snapshot.artistName,
                albumTitle: snapshot.albumTitle,
                sourceName: sourceName
            ),
            title: title,
            artistName: snapshot.artistName?.sonoicNonEmptyTrimmed,
            albumTitle: snapshot.albumTitle?.sonoicNonEmptyTrimmed,
            sourceName: sourceName,
            artworkURL: snapshot.artworkURL?.sonoicNonEmptyTrimmed,
            artworkIdentifier: snapshot.artworkIdentifier?.sonoicNonEmptyTrimmed,
            service: SonosServiceCatalog.descriptor(named: sourceName),
            lastPlayedAt: observedAt
        )
    }

    init(favorite: SonosFavoriteItem, playedAt: Date) {
        let sourceName = favorite.service?.name ?? "Sonos Favorite"

        self.init(
            id: Self.fingerprint(
                title: favorite.title,
                artistName: favorite.subtitle,
                albumTitle: nil,
                sourceName: sourceName
            ),
            title: favorite.title,
            artistName: favorite.subtitle,
            albumTitle: nil,
            sourceName: sourceName,
            artworkURL: favorite.artworkURL?.sonoicNonEmptyTrimmed,
            artworkIdentifier: nil,
            service: favorite.service,
            lastPlayedAt: playedAt,
            playbackURI: favorite.playbackURI,
            playbackMetadataXML: favorite.playbackMetadataXML,
            favoriteKind: favorite.kind
        )
    }

    var subtitle: String? {
        var parts: [String] = []

        if let artistName = artistName?.sonoicNonEmptyTrimmed {
            parts.append(artistName)
        }

        if let albumTitle = albumTitle?.sonoicNonEmptyTrimmed, !parts.contains(albumTitle) {
            parts.append(albumTitle)
        }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " • ")
    }

    var canReplay: Bool {
        playbackURI.sonoicNonEmptyTrimmed != nil
    }

    var isVisibleInHomeHistory: Bool {
        service != nil
    }

    var homeHistoryIdentity: String {
        Self.historyIdentity(
            title: title,
            artistName: artistName,
            albumTitle: albumTitle
        )
    }

    var replayFavorite: SonosFavoriteItem? {
        guard let playbackURI = playbackURI?.sonoicNonEmptyTrimmed else {
            return nil
        }

        return SonosFavoriteItem(
            id: id,
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            service: service,
            playbackURI: playbackURI,
            playbackMetadataXML: playbackMetadataXML,
            kind: favoriteKind ?? .item
        )
    }

    func matchesHomeHistoryIdentity(of otherItem: SonoicRecentPlayItem) -> Bool {
        homeHistoryIdentity == otherItem.homeHistoryIdentity
    }

    func enriched(with newerItem: SonoicRecentPlayItem) -> SonoicRecentPlayItem {
        SonoicRecentPlayItem(
            id: id,
            title: newerItem.title,
            artistName: newerItem.artistName ?? artistName,
            albumTitle: newerItem.albumTitle ?? albumTitle,
            sourceName: newerItem.sourceName,
            artworkURL: newerItem.artworkURL ?? artworkURL,
            artworkIdentifier: newerItem.artworkIdentifier ?? artworkIdentifier,
            service: newerItem.service ?? service,
            lastPlayedAt: newerItem.lastPlayedAt,
            playbackURI: newerItem.playbackURI ?? playbackURI,
            playbackMetadataXML: newerItem.playbackMetadataXML ?? playbackMetadataXML,
            favoriteKind: newerItem.favoriteKind ?? favoriteKind
        )
    }

    private static let ignoredTitles: Set<String> = [
        "no player connected",
        "unknown track"
    ]

    private static let ignoredSourceNames: Set<String> = [
        "open rooms to choose a player"
    ]

    private static func fingerprint(
        title: String,
        artistName: String?,
        albumTitle: String?,
        sourceName: String
    ) -> String {
        [
            title.sonoicTrimmed.lowercased(),
            artistName?.sonoicTrimmed.lowercased() ?? "",
            albumTitle?.sonoicTrimmed.lowercased() ?? "",
            sourceName.sonoicTrimmed.lowercased()
        ]
        .joined(separator: "|")
    }

    private static func historyIdentity(
        title: String,
        artistName: String?,
        albumTitle: String?
    ) -> String {
        [
            title.sonoicTrimmed.lowercased(),
            artistName?.sonoicTrimmed.lowercased() ?? "",
            albumTitle?.sonoicTrimmed.lowercased() ?? ""
        ]
        .joined(separator: "|")
    }
}
