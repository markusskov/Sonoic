import Foundation

struct SonosControlAPIAuthorizationState: Equatable {
    enum Status: Equatable {
        case notConfigured
        case disconnected
        case connecting
        case connected(expiresAt: Date)
        case expired
        case failed(String)
    }

    var status: Status

    static let notConfigured = SonosControlAPIAuthorizationState(status: .notConfigured)
    static let disconnected = SonosControlAPIAuthorizationState(status: .disconnected)

    var isConnected: Bool {
        if case .connected = status {
            return true
        }

        return false
    }

    var isConnecting: Bool {
        if case .connecting = status {
            return true
        }

        return false
    }

    var canConnect: Bool {
        switch status {
        case .disconnected, .expired, .failed:
            true
        case .notConfigured, .connecting, .connected:
            false
        }
    }

    var title: String {
        switch status {
        case .notConfigured:
            "Setup Needed"
        case .disconnected:
            "Not Connected"
        case .connecting:
            "Connecting"
        case .connected:
            "Connected"
        case .expired:
            "Expired"
        case .failed:
            "Needs Attention"
        }
    }

    var detail: String? {
        switch status {
        case .notConfigured:
            "OAuth broker settings are missing."
        case .disconnected:
            nil
        case .connecting:
            nil
        case let .connected(expiresAt):
            "Token expires \(expiresAt.formatted(.dateTime.hour().minute()))"
        case .expired:
            "Connect again to refresh Sonos access."
        case let .failed(detail):
            detail
        }
    }

    var systemImage: String {
        switch status {
        case .notConfigured:
            "exclamationmark.triangle"
        case .disconnected:
            "person.crop.circle.badge.plus"
        case .connecting:
            "arrow.triangle.2.circlepath"
        case .connected:
            "checkmark.circle.fill"
        case .expired:
            "clock.badge.exclamationmark"
        case .failed:
            "xmark.circle.fill"
        }
    }
}
