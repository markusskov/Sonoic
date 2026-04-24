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
            "Sonoic is scanning your local network for Sonos speakers through Bonjour."
        case .resolving:
            "Sonoic found Sonos speakers and is loading room names, models, and bonded setup."
        case .ready:
            "Tap a room below to make it the active player throughout Sonoic."
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
