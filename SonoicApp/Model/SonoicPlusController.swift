import Foundation
import RevenueCat

@MainActor
final class SonoicPlusController {
    private let configuration: SonoicPlusConfiguration
    private var isConfigured = false

    init(configuration: SonoicPlusConfiguration = .load()) {
        self.configuration = configuration
    }

    func configureIfPossible() -> SonoicPlusState {
        guard let apiKey = configuration.revenueCatAPIKey else {
            return notConfiguredState
        }

        guard !isConfigured else {
            return SonoicPlusState(
                status: .refreshing,
                entitlementIdentifier: configuration.entitlementIdentifier,
                updatedAt: nil
            )
        }

        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
        isConfigured = true

        return SonoicPlusState(
            status: .refreshing,
            entitlementIdentifier: configuration.entitlementIdentifier,
            updatedAt: nil
        )
    }

    func refreshState() async -> SonoicPlusState {
        guard configuration.isConfigured else {
            return notConfiguredState
        }

        _ = configureIfPossible()

        do {
            let customerInfo = try await customerInfo()
            return state(from: customerInfo)
        } catch {
            return failedState(error)
        }
    }

    func restorePurchases() async -> SonoicPlusState {
        guard configuration.isConfigured else {
            return notConfiguredState
        }

        _ = configureIfPossible()

        do {
            let customerInfo = try await restoreCustomerInfo()
            return state(from: customerInfo)
        } catch {
            return failedState(error)
        }
    }

    private var notConfiguredState: SonoicPlusState {
        SonoicPlusState(
            status: .notConfigured,
            entitlementIdentifier: configuration.entitlementIdentifier,
            updatedAt: nil
        )
    }

    private func customerInfo() async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.getCustomerInfo { customerInfo, error in
                if let customerInfo {
                    continuation.resume(returning: customerInfo)
                } else {
                    continuation.resume(throwing: error ?? SonoicPlusError.customerInfoUnavailable)
                }
            }
        }
    }

    private func restoreCustomerInfo() async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.restorePurchases { customerInfo, error in
                if let customerInfo {
                    continuation.resume(returning: customerInfo)
                } else {
                    continuation.resume(throwing: error ?? SonoicPlusError.customerInfoUnavailable)
                }
            }
        }
    }

    private func state(from customerInfo: CustomerInfo) -> SonoicPlusState {
        let isUnlocked = customerInfo
            .entitlements[configuration.entitlementIdentifier]?
            .isActive == true

        return SonoicPlusState(
            status: isUnlocked ? .unlocked : .available,
            entitlementIdentifier: configuration.entitlementIdentifier,
            updatedAt: .now
        )
    }

    private func failedState(_ error: Error) -> SonoicPlusState {
        SonoicPlusState(
            status: .failed(error.localizedDescription),
            entitlementIdentifier: configuration.entitlementIdentifier,
            updatedAt: .now
        )
    }
}

private enum SonoicPlusError: LocalizedError {
    case customerInfoUnavailable

    var errorDescription: String? {
        switch self {
        case .customerInfoUnavailable:
            "RevenueCat did not return customer information."
        }
    }
}
