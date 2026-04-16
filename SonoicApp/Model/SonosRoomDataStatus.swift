import Foundation

enum SonosRoomDataStatus: Equatable {
    case idle
    case loading
    case resolved
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "Waiting to Resolve"
        case .loading:
            "Resolving"
        case .resolved:
            "Resolved"
        case .failed:
            "Resolution Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "clock"
        case .loading:
            "arrow.clockwise"
        case .resolved:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

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
