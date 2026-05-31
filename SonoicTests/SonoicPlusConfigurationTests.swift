import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicPlusConfigurationTests {
    @Test
    func loadsTrimmedRevenueCatSettingsFromBundle() throws {
        let bundle = try makeBundle(
            info: [
                "RevenueCatAPIKey": "  revenuecat-public-key  ",
                "SonoicPlusEntitlementIdentifier": "  beta-plus  "
            ]
        )

        let configuration = SonoicPlusConfiguration.load(from: bundle)

        #expect(configuration.revenueCatAPIKey == "revenuecat-public-key")
        #expect(configuration.entitlementIdentifier == "beta-plus")
        #expect(configuration.isConfigured)
    }

    @Test
    func treatsBlankOrUnresolvedRevenueCatSettingsAsDisabled() throws {
        let bundle = try makeBundle(
            info: [
                "RevenueCatAPIKey": "$(REVENUECAT_API_KEY)",
                "SonoicPlusEntitlementIdentifier": "  "
            ]
        )

        let configuration = SonoicPlusConfiguration.load(from: bundle)

        #expect(configuration.revenueCatAPIKey == nil)
        #expect(configuration.entitlementIdentifier == SonoicPlusState.defaultEntitlementIdentifier)
        #expect(!configuration.isConfigured)
    }

    @Test
    func plusStateCopyExplainsDisabledSandboxAndFailureStates() {
        let disabled = SonoicPlusState.notConfigured
        let available = SonoicPlusState(
            status: .available,
            entitlementIdentifier: "plus",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let unlocked = SonoicPlusState(
            status: .unlocked,
            entitlementIdentifier: "plus",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let failed = SonoicPlusState(
            status: .failed("Purchases could not be restored. Check your network connection."),
            entitlementIdentifier: "plus",
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(disabled.settingsStatusTitle == "Disabled")
        #expect(disabled.settingsDetail == "Plus purchases are not enabled in this build.")
        #expect(disabled.purchaseRecoveryDetail?.contains("RevenueCat public SDK key") == true)
        #expect(disabled.purchaseRecoveryDetail?.contains("entitlement 'plus'") == true)
        #expect(available.purchaseRecoveryDetail?.contains("RevenueCat") == true)
        #expect(available.purchaseRecoveryDetail?.contains("TestFlight") == true)
        #expect(available.purchaseRecoveryDetail?.contains("sandbox") == true)
        #expect(available.purchaseRecoveryDetail?.contains("Apple ID") == true)
        #expect(unlocked.purchaseRecoveryDetail == "Your Plus entitlement is active for this Apple ID.")
        #expect(failed.settingsStatusTitle == "Unavailable")
        #expect(failed.settingsDetail == "Purchases could not be restored. Check your network connection.")
        #expect(failed.purchaseRecoveryDetail?.contains("Purchases could not be restored.") == true)
        #expect(failed.purchaseRecoveryDetail?.contains("Settings > Advanced") == true)
        #expect(failed.purchaseRecoveryDetail?.contains("redacted Support Summary") == true)
        #expect(failed.purchaseRecoveryDetail?.contains("App Store or RevenueCat account details") == true)
    }

    private func makeBundle(info: [String: String]) throws -> Bundle {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SonoicPlusConfigurationTests-\(UUID().uuidString)")
            .appendingPathExtension("bundle")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        var plist: [String: String] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "SonoicPlusConfigurationTests",
            "CFBundleIdentifier": "com.markusskov.Sonoic.PlusConfigurationTests.\(UUID().uuidString)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "SonoicPlusConfigurationTests",
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1"
        ]
        plist.merge(info) { _, new in new }

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: url.appendingPathComponent("Info.plist"))
        return try #require(Bundle(path: url.path))
    }
}
