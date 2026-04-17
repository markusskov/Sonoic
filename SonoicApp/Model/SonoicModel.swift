import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class SonoicModel {
    @ObservationIgnored static let manualPlayTransitionGraceInterval: TimeInterval = 3
    @ObservationIgnored static let unconfiguredTarget = SonosActiveTarget(
        id: "unconfigured-room",
        name: "No Room Loaded",
        householdName: "",
        kind: .room,
        memberNames: []
    )
    // Room identity and bonded topology are low-churn metadata. Keep them on the
    // same lightweight cadence and rely on explicit refreshes for immediate updates.
    @ObservationIgnored static let manualHostRoomMetadataRefreshInterval: TimeInterval = 60
    @ObservationIgnored var isSceneActive = false
    @ObservationIgnored var resolvedManualHostIdentityHost: String?
    @ObservationIgnored var resolvedManualHostTopologyHost: String?
    @ObservationIgnored var manualHostIdentityLastRefreshAt: Date?
    @ObservationIgnored var manualHostTopologyLastRefreshAt: Date?
    @ObservationIgnored var manualHostRefreshTask: Task<Void, Never>?
    @ObservationIgnored var manualHostDeferredSyncTask: Task<Void, Never>?
    @ObservationIgnored var manualPlayConfirmationRetryTask: Task<Void, Never>?
    @ObservationIgnored var manualHostLastSuccessfulRefreshAt: Date?
    @ObservationIgnored var lastReloadedWidgetPresentation: SonoicExternalControlState.WidgetPresentation?
    @ObservationIgnored var isManualTransportCommandInFlight = false
    @ObservationIgnored var manualPlayTransitionGraceDeadline: Date?
    @ObservationIgnored var isManualPlayTransitionAwaitingConfirmation = false
    @ObservationIgnored var backgroundExecutionIdentifier: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored let sharedStore: SonoicSharedStore?
    @ObservationIgnored let settingsStore: SonoicSettingsStore
    @ObservationIgnored let deviceInfoClient: SonosDeviceInfoClient
    @ObservationIgnored let zoneGroupTopologyClient: SonosZoneGroupTopologyClient
    @ObservationIgnored let renderingControlClient: SonosRenderingControlClient
    @ObservationIgnored let avTransportClient: SonosAVTransportClient
    @ObservationIgnored let nowPlayingClient: SonosNowPlayingClient
    @ObservationIgnored let nowPlayableSessionController: SonoicNowPlayableSessionController

    var selectedTab: RootTab = .home
    var manualSonosHost: String {
        didSet {
            settingsStore.saveManualSonosHost(manualSonosHost)
            manualHostRefreshStatus = .idle
            manualHostIdentityStatus = .idle
            manualHostTopologyStatus = .idle
            manualHostLastSuccessfulRefreshAt = nil
            resetManualHostIdentity()
            stopManualHostRefreshLoop()
            scheduleBackgroundPlayerRefreshIfPossible()
            persistSharedExternalControlState()
        }
    }
    var manualHostRefreshStatus: SonosManualHostRefreshStatus = .idle
    var manualHostIdentityStatus: SonosRoomDataStatus = .idle
    var manualHostTopologyStatus: SonosRoomDataStatus = .idle

    var activeTarget = SonoicModel.unconfiguredTarget {
        didSet {
            persistSharedExternalControlState()
        }
    }

    var nowPlayingObservedAt = Date()

    var nowPlaying = SonosNowPlayingSnapshot.unconfigured {
        didSet {
            nowPlayingObservedAt = .now
            persistSharedExternalControlState()
        }
    }

    var externalVolume = SonoicExternalControlState.Volume(level: 24, isMuted: false) {
        didSet {
            persistSharedExternalControlState()
        }
    }

    var roomDiscoveryStatus: SonosRoomDiscoveryStatus {
        hasManualSonosHost ? .manualFallback : .setupRequired
    }

    var roomListItems: [SonosRoomListItem] {
        guard hasManualSonosHost else {
            return []
        }

        return [
            SonosRoomListItem(
                activeTarget: activeTarget,
                source: .manualFallback,
                isActive: true
            )
        ]
    }

    init() {
        settingsStore = SonoicSettingsStore()
        let sonosControlTransport = SonosControlTransport()
        deviceInfoClient = SonosDeviceInfoClient(transport: sonosControlTransport)
        zoneGroupTopologyClient = SonosZoneGroupTopologyClient(transport: sonosControlTransport)
        renderingControlClient = SonosRenderingControlClient(transport: sonosControlTransport)
        avTransportClient = SonosAVTransportClient(transport: sonosControlTransport)
        nowPlayingClient = SonosNowPlayingClient(transport: sonosControlTransport)
        nowPlayableSessionController = SonoicNowPlayableSessionController()
        manualSonosHost = settingsStore.loadManualSonosHost()

        do {
            sharedStore = try SonoicSharedStore()
        } catch {
            sharedStore = nil
            assertionFailure("Unable to create the shared App Group store: \(error)")
        }

        resetManualHostIdentity()
        persistSharedExternalControlState()
        configureNowPlayableSessionController()
    }
}
