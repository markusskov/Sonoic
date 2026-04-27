import Foundation

struct SonosNowPlayingDiagnostics: Equatable {
    var currentURI: String?
    var trackURI: String?
    var rawDuration: String?
    var rawElapsedTime: String?
    var hasTrackMetadata: Bool
    var hasSourceMetadata: Bool
    var usedFallbackSnapshot: Bool

    var currentURIOwnership: SonosPlaybackSourceOwnership {
        SonosMetadataHeuristics.sourceOwnership(for: currentURI)
    }

    var trackURIOwnership: SonosPlaybackSourceOwnership {
        SonosMetadataHeuristics.sourceOwnership(for: trackURI)
    }

    static let empty = SonosNowPlayingDiagnostics(
        currentURI: nil,
        trackURI: nil,
        rawDuration: nil,
        rawElapsedTime: nil,
        hasTrackMetadata: false,
        hasSourceMetadata: false,
        usedFallbackSnapshot: false
    )
}
