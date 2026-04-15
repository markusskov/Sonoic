import Foundation

enum SonosManualHostRefreshStatus: Equatable {
    case idle
    case refreshing
    case updated(Date)
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "Ready to refresh"
        case .refreshing:
            "Refreshing from player"
        case .updated:
            "Player state updated"
        case .failed:
            "Refresh failed"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "dot.radiowaves.left.and.right"
        case .refreshing:
            "arrow.clockwise"
        case .updated:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var detail: String? {
        guard case let .failed(message) = self else {
            return nil
        }

        return message
    }

    var updatedAt: Date? {
        guard case let .updated(date) = self else {
            return nil
        }

        return date
    }

    var isRefreshing: Bool {
        if case .refreshing = self {
            true
        } else {
            false
        }
    }
}
