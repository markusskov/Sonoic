import Foundation

enum SonosRoomDataStatus: Equatable {
    case idle
    case loading
    case resolved
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            true
        } else {
            false
        }
    }

    var isResolved: Bool {
        if case .resolved = self {
            true
        } else {
            false
        }
    }

    var failureDetail: String? {
        guard case let .failed(detail) = self else {
            return nil
        }

        return detail
    }
}
