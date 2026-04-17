import Foundation

enum SonosQueueState: Equatable {
    case idle
    case loading
    case unavailable(String)
    case loaded(SonosQueueSnapshot)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            true
        } else {
            false
        }
    }

    var snapshot: SonosQueueSnapshot? {
        guard case let .loaded(snapshot) = self else {
            return nil
        }

        return snapshot
    }
}
