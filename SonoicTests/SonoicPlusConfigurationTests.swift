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
    func plusStateCopyExplainsDisabledAndFailureStates() {
        let disabled = SonoicPlusState.notConfigured
        let failed = SonoicPlusState(
            status: .failed("Purchases could not be restored. Check your network connection."),
            entitlementIdentifier: "plus",
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(disabled.settingsStatusTitle == "Disabled")
        #expect(disabled.settingsDetail == "Plus purchases are not enabled in this build.")
        #expect(failed.settingsStatusTitle == "Unavailable")
        #expect(failed.settingsDetail == "Purchases could not be restored. Check your network connection.")
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
