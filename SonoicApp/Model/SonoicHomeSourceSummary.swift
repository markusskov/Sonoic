import Foundation

struct SonoicHomeSourceSummary: Identifiable, Equatable {
    var service: SonosServiceDescriptor
    var favoriteCount: Int
    var collectionCount: Int
    var recentCount: Int
    var isCurrent: Bool

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
