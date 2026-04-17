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
}
