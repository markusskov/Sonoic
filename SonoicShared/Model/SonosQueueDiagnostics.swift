import Foundation

struct SonosQueueDiagnostics: Equatable {
    var observedAt: Date?
    var currentURI: String?
    var itemCount: Int?
    var lastRefreshErrorDetail: String?
    var lastMutationErrorDetail: String?

    var currentURIOwnership: SonosPlaybackSourceOwnership {
        SonosPlaybackSourceOwnership(uri: currentURI)
    }

    static let empty = SonosQueueDiagnostics(
        observedAt: nil,
        currentURI: nil,
        itemCount: nil,
        lastRefreshErrorDetail: nil,
        lastMutationErrorDetail: nil
    )
}
