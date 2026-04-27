import Foundation

struct SonosPlayablePayload: Identifiable, Equatable {
    enum Kind: String, Codable, Equatable {
        case item
        case collection
    }

    enum LaunchMode: String, Codable, Equatable {
        case direct
        case queueNext
    }

    let id: String
    var title: String
    var subtitle: String?
    var artworkURL: String?
    var service: SonosServiceDescriptor?
    var uri: String
    var metadataXML: String?
    var kind: Kind
    var launchMode: LaunchMode

    var validationFailureReason: String? {
        do {
            _ = try SonosPlayablePayloadPreparer().prepare(self)
            return nil
        } catch let failure as SonosPlayablePayloadPreparer.Failure {
            return failure.localizedDescription
        } catch {
            return error.localizedDescription
        }
    }

    var isValidForLaunch: Bool {
        validationFailureReason == nil
    }

    func withLaunchMode(_ launchMode: LaunchMode) -> SonosPlayablePayload {
        SonosPlayablePayload(
            id: id,
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            service: service,
            uri: uri,
            metadataXML: metadataXML,
            kind: kind,
            launchMode: launchMode
        )
    }

    init(
        id: String,
        title: String,
        subtitle: String?,
        artworkURL: String?,
        service: SonosServiceDescriptor?,
        uri: String,
        metadataXML: String?,
        kind: Kind = .item,
        launchMode: LaunchMode = .direct
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.service = service
        self.uri = uri
        self.metadataXML = metadataXML
        self.kind = kind
        self.launchMode = launchMode
    }

    init?(favorite: SonosFavoriteItem) {
        guard let uri = favorite.playbackURI.sonoicNonEmptyTrimmed else {
            return nil
        }

        self.init(
            id: favorite.id,
            title: favorite.title,
            subtitle: favorite.subtitle,
            artworkURL: favorite.artworkURL,
            service: favorite.service,
            uri: uri,
            metadataXML: favorite.playbackMetadataXML,
            kind: SonosPlayablePayload.Kind(favoriteKind: favorite.kind)
        )
    }
}

private extension SonosPlayablePayload.Kind {
    init(favoriteKind: SonosFavoriteItem.Kind) {
        switch favoriteKind {
        case .item:
            self = .item
        case .collection:
            self = .collection
        }
    }
}
