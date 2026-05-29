import Foundation
import Testing
@testable import Sonoic

struct SonosPlaybackCommandRouteTests {
    @Test
    func localModeUsesManualHostAndAllowsLocalCommands() {
        let route = Self.route(mode: .off, hasManualHost: true)

        #expect(!route.routesCommandsToSonosControlAPI)
        #expect(route.allowsLocalManualTransportCommands)
        #expect(route.hasActiveSonosControlTarget)
        #expect(route.canControlManualPlayback)
        #expect(route.canSendPrimarySourcePlaybackCommands)
    }

    @Test
    func cloudModeWithReadySelectedGroupUsesCloudCommandTarget() {
        let route = Self.route(
            mode: .preferred,
            authorizationStatus: .ready,
            selectedGroupID: " group-1 ",
            hasManualHost: true
        )

        #expect(route.routesCommandsToSonosControlAPI)
        #expect(!route.allowsLocalManualTransportCommands)
        #expect(route.selectedGroupID == "group-1")
        #expect(route.hasSonosControlAPICommandTarget)
        #expect(route.hasActiveSonosControlTarget)
        #expect(route.canControlManualPlayback)
    }

    @Test
    func cloudModeWithoutSelectedGroupBlocksManualHostFallback() {
        let route = Self.route(
            mode: .preferred,
            authorizationStatus: .ready,
            selectedGroupID: nil,
            hasManualHost: true
        )

        #expect(route.routesCommandsToSonosControlAPI)
        #expect(!route.allowsLocalManualTransportCommands)
        #expect(!route.hasSonosControlAPICommandTarget)
        #expect(!route.hasActiveSonosControlTarget)
        #expect(!route.canControlManualPlayback)
        #expect(!route.canSendPrimarySourcePlaybackCommands)
    }

    @Test
    func cloudModeWithExpiredAuthorizationBlocksCommandsButKeepsResolvedTarget() {
        let route = Self.route(
            mode: .preferred,
            authorizationStatus: .expired,
            selectedGroupID: "group-1",
            hasManualHost: true
        )

        #expect(route.routesCommandsToSonosControlAPI)
        #expect(!route.allowsLocalManualTransportCommands)
        #expect(!route.hasSonosControlAPICommandTarget)
        #expect(!route.hasActiveSonosControlTarget)
        #expect(route.hasResolvedSonosPlaybackTarget)
    }

    @Test
    func cloudModeCanResolveConfiguredActiveTargetWithoutCommandTarget() {
        let route = Self.route(
            mode: .fallback,
            authorizationStatus: .ready,
            selectedGroupID: nil,
            hasManualHost: false,
            hasConfiguredActiveTarget: true
        )

        #expect(route.routesCommandsToSonosControlAPI)
        #expect(!route.hasSonosControlAPICommandTarget)
        #expect(!route.hasActiveSonosControlTarget)
        #expect(route.hasResolvedSonosPlaybackTarget)
    }

    private static func route(
        mode: SonosControlAPIMode,
        authorizationStatus: SonosControlAPIState.AuthorizationStatus = .notConfigured,
        selectedGroupID: String? = nil,
        hasManualHost: Bool = false,
        hasConfiguredActiveTarget: Bool = false
    ) -> SonosPlaybackCommandRoute {
        SonosPlaybackCommandRoute(
            sonosControlAPIState: SonosControlAPIState(
                settings: SonosControlAPISettings(
                    mode: mode,
                    selectedHouseholdID: nil,
                    selectedGroupID: selectedGroupID
                ),
                authorizationStatus: authorizationStatus,
                lastErrorDetail: nil,
                lastCommandDescription: nil,
                lastUpdatedAt: nil
            ),
            hasManualHost: hasManualHost,
            hasConfiguredActiveTarget: hasConfiguredActiveTarget
        )
    }
}
