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
        sourceOwnership(for: uri).isQueueBacked
    }

    static func isPlaybackContainerURI(_ uri: String?) -> Bool {
        switch sourceOwnership(for: uri) {
        case .sonosQueue, .serviceContainer:
            true
        case .unavailable,
             .directServiceStream,
             .groupCoordinator,
             .tvAudio,
             .lineIn,
             .musicLibrary,
             .webStream,
             .unknown:
            false
        }
    }

    static func sourceOwnership(for uri: String?) -> SonosPlaybackSourceOwnership {
        SonosPlaybackSourceOwnership(uri: uri)
    }
}
