import Foundation

enum SonosRoomDiscoveryStatus: Equatable {
    case scanning
    case resolving
    case ready
    case failed(String)

    var title: String {
        switch self {
        case .scanning:
            "Scanning for Rooms"
        case .resolving:
            "Loading Household"
        case .ready:
            "Rooms Ready"
        case .failed:
            "Discovery Failed"
        }
    }

    var detail: String {
        switch self {
        case .scanning:
            "Searching nearby rooms."
        case .resolving:
            "Loading rooms."
        case .ready:
            "Tap to switch rooms."
        case let .failed(detail):
            detail
        }
    }

    var systemImage: String {
        switch self {
        case .scanning:
            "dot.radiowaves.left.and.right"
        case .resolving:
            "arrow.triangle.2.circlepath"
        case .ready:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var isLoading: Bool {
        switch self {
        case .scanning, .resolving:
            true
        case .ready, .failed:
            false
        }
    }
}
