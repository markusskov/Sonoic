import Foundation

enum SonosMetadataHeuristics {
    static func isGenericQueueTitle(_ title: String) -> Bool {
        switch title.lowercased() {
        case "queue", "sonos queue", "playback queue":
            true
        default:
            false
        }
    }

    static func isQueueContainerURI(_ uri: String?) -> Bool {
        guard let normalizedURI = uri?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        return normalizedURI.hasPrefix("x-rincon-queue:")
            || normalizedURI.hasPrefix("x-rincon-cpcontainer:")
    }
}
