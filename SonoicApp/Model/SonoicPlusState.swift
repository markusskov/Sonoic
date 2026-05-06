import Foundation

struct SonoicPlusState: Equatable {
    enum Status: Equatable {
        case notConfigured
        case refreshing
        case available
        case unlocked
        case failed(String)
    }

    var status: Status
    var entitlementIdentifier: String
    var updatedAt: Date?

    static let defaultEntitlementIdentifier = "plus"

    static var notConfigured: SonoicPlusState {
        SonoicPlusState(
            status: .notConfigured,
            entitlementIdentifier: defaultEntitlementIdentifier,
            updatedAt: nil
        )
    }

    var isUnlocked: Bool {
        status == .unlocked
    }

    var settingsStatusTitle: String {
        switch status {
        case .notConfigured:
            "Not Configured"
        case .refreshing:
            "Checking"
        case .available:
            "Available"
        case .unlocked:
            "Unlocked"
        case .failed:
            "Unavailable"
        }
    }

    var settingsDetail: String? {
        switch status {
        case .notConfigured:
            "RevenueCat is ready for setup."
        case .refreshing:
            nil
        case .available:
            "Support development and personalize Sonoic."
        case .unlocked:
            "Thank you for supporting Sonoic."
        case .failed(let message):
            message
        }
    }

    var systemImage: String {
        switch status {
        case .notConfigured:
            "sparkles"
        case .refreshing:
            "arrow.clockwise"
        case .available:
            "sparkles"
        case .unlocked:
            "checkmark.seal.fill"
        case .failed:
            "exclamationmark.triangle"
        }
    }
}
