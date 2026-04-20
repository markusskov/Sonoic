import Foundation

struct SonosFavoriteItem: Identifiable, Equatable {
    let id: String
    var title: String
    var subtitle: String?
    var artworkURL: String?
    var service: SonosServiceDescriptor?
    var playbackURI: String
    var playbackMetadataXML: String?
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
}
