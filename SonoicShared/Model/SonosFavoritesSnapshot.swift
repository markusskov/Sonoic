import Foundation

struct SonosFavoriteItem: Identifiable, Equatable {
    enum Kind: String, Codable, Equatable {
        case item
        case collection
    }

    let id: String
    var title: String
    var subtitle: String?
    var artworkURL: String?
    var service: SonosServiceDescriptor?
    var playbackURI: String
    var playbackMetadataXML: String?
    var kind: Kind = .item

    var isCollectionLike: Bool {
        if kind == .collection {
            return true
        }

        let normalizedURI = playbackURI.lowercased()
        return normalizedURI.contains("container")
            || normalizedURI.contains("playlist")
            || normalizedURI.contains("station")
            || normalizedURI.contains("radio")
            || normalizedURI.contains("album")
    }
}

struct SonosFavoritesSnapshot: Equatable {
    var items: [SonosFavoriteItem]

    var services: [SonosServiceDescriptor] {
        var seenServiceIDs: Set<String> = []

        return items.compactMap { item in
            guard let service = item.service,
                  seenServiceIDs.insert(service.id).inserted
            else {
                return nil
            }

            return service
        }
    }

    var collectionItems: [SonosFavoriteItem] {
        items.filter(\.isCollectionLike)
    }
}
