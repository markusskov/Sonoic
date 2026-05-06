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

struct SonosSeekDiagnostics: Equatable {
    enum Status: Equatable {
        case idle
        case pending
        case succeeded
        case failed

        var title: String {
            switch self {
            case .idle:
                "Idle"
            case .pending:
                "Pending"
            case .succeeded:
                "Succeeded"
            case .failed:
                "Failed"
            }
        }
    }

    var status: Status
    var requestedAt: Date?
    var host: String?
    var target: TimeInterval?
    var observed: TimeInterval?
    var errorDetail: String?

    static let empty = SonosSeekDiagnostics(
        status: .idle,
        requestedAt: nil,
        host: nil,
        target: nil,
        observed: nil,
        errorDetail: nil
    )
}
