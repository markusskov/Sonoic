enum SonosConnectionState: Equatable {
    enum ControlPath: String, Equatable {
        case localNetwork

        var title: String {
            switch self {
            case .localNetwork:
                "Local Network"
            }
        }
    }

    case ready(ControlPath)
    case connecting(ControlPath)
    case stale(ControlPath)
    case unavailable(ControlPath)

    var controlPath: ControlPath {
        switch self {
        case let .ready(controlPath),
            let .connecting(controlPath),
            let .stale(controlPath),
            let .unavailable(controlPath):
            controlPath
        }
    }

    var title: String {
        switch self {
        case .ready:
            "Connected"
        case .connecting:
            "Connecting"
        case .stale:
            "Stale"
        case .unavailable:
            "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .ready:
            "Sonoic can send commands straight to the selected Sonos target over Wi-Fi."
        case .connecting:
            "Sonoic is looking for the selected Sonos target on the local network."
        case .stale:
            "Sonoic is showing the last known Sonos state while it tries to reconnect."
        case .unavailable:
            "The selected Sonos target is not reachable on the local network right now."
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            "checkmark.circle.fill"
        case .connecting:
            "dot.radiowaves.left.and.right"
        case .stale:
            "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .unavailable:
            "wifi.slash"
        }
    }
}
