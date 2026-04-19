import Foundation

enum SonosRoomDiscoveryStatus: Equatable {
    case setupRequired
    case manualFallback

    var title: String {
        switch self {
        case .setupRequired:
            "Discovery Needs Setup"
        case .manualFallback:
            "Manual Room Fallback"
        }
    }

    var detail: String {
        switch self {
        case .setupRequired:
            "Sonoic still needs a manual player in Settings before it can show the current room. Future discovery will replace that one-host bootstrap flow."
        case .manualFallback:
            "Sonoic is currently deriving the active room from your configured player. Real discovery will expand this into a household room list and grouping surface."
        }
    }

    var systemImage: String {
        switch self {
        case .setupRequired:
            "dot.radiowaves.left.and.right"
        case .manualFallback:
            "wave.3.right.circle"
        }
    }
}
