import Foundation

struct SonoicPlusConfiguration: Equatable {
    let revenueCatAPIKey: String?
    let entitlementIdentifier: String

    var isConfigured: Bool {
        revenueCatAPIKey != nil
    }

    static func load(from bundle: Bundle = .main) -> SonoicPlusConfiguration {
        SonoicPlusConfiguration(
            revenueCatAPIKey: bundle.sonoicTrimmedString(forInfoDictionaryKey: "RevenueCatAPIKey"),
            entitlementIdentifier: bundle.sonoicTrimmedString(forInfoDictionaryKey: "SonoicPlusEntitlementIdentifier")
                ?? SonoicPlusState.defaultEntitlementIdentifier
        )
    }
}

private extension Bundle {
    func sonoicTrimmedString(forInfoDictionaryKey key: String) -> String? {
        guard let rawValue = object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
