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
            "Disabled"
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
            "Plus purchases are not enabled in this build."
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

    var purchaseRecoveryDetail: String? {
        switch status {
        case .notConfigured:
            "Plus purchases are disabled for this build. TestFlight purchase validation requires a RevenueCat public SDK key and entitlement '\(entitlementIdentifier)'."
        case .refreshing:
            "Checking Plus entitlement status."
        case .available:
            "Purchases and restores are handled by the App Store through RevenueCat. TestFlight builds use Apple's sandbox for the Apple ID that installed TestFlight."
        case .unlocked:
            "Your Plus entitlement is active for this Apple ID."
        case .failed(let message):
            "\(message) If you report this from TestFlight, include the redacted Support Summary from Settings > Advanced instead of App Store or RevenueCat account details."
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
