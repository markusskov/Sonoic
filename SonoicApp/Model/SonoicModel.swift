import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class SonoicModel {
    @ObservationIgnored static let manualPlayTransitionGraceInterval: TimeInterval = 3
    @ObservationIgnored var isSceneActive = false
    @ObservationIgnored var manualHostRefreshTask: Task<Void, Never>?
    @ObservationIgnored var manualHostDeferredSyncTask: Task<Void, Never>?
    @ObservationIgnored var manualPlayConfirmationRetryTask: Task<Void, Never>?
    @ObservationIgnored var isManualTransportCommandInFlight = false
    @ObservationIgnored var manualPlayTransitionGraceDeadline: Date?
    @ObservationIgnored var isManualPlayTransitionAwaitingConfirmation = false
    @ObservationIgnored var backgroundExecutionIdentifier: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored let sharedStore: SonoicSharedStore?
    @ObservationIgnored let settingsStore: SonoicSettingsStore
    @ObservationIgnored let renderingControlClient: SonosRenderingControlClient
    @ObservationIgnored let avTransportClient: SonosAVTransportClient
    @ObservationIgnored let nowPlayingClient: SonosNowPlayingClient
    @ObservationIgnored let nowPlayableSessionController: SonoicNowPlayableSessionController

    var selectedTab: RootTab = .home
    var manualSonosHost: String {
        didSet {
            settingsStore.saveManualSonosHost(manualSonosHost)
            manualHostRefreshStatus = .idle
            stopManualHostRefreshLoop()
            scheduleBackgroundPlayerRefreshIfPossible()
            persistSharedExternalControlState()
        }
    }
    var manualHostRefreshStatus: SonosManualHostRefreshStatus = .idle

    var activeTarget = SonosActiveTarget(
        id: "living-room",
        name: "Living Room",
        householdName: "Markus's Sonos",
        kind: .room,
        memberNames: ["Living Room"]
    ) {
        didSet {
            persistSharedExternalControlState()
        }
    }

    var connectionState: SonosConnectionState = .ready(.localNetwork) {
        didSet {
            persistSharedExternalControlState()
        }
    }

    var nowPlayingObservedAt = Date()

    var nowPlaying = SonosNowPlayingSnapshot(
        title: "Unwritten",
        artistName: "Natasha Bedingfield",
        albumTitle: "Unwritten",
        sourceName: "Apple Music",
        playbackState: .playing
    ) {
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

    init() {
        settingsStore = SonoicSettingsStore()
        let sonosControlTransport = SonosControlTransport()
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

        persistSharedExternalControlState()
        configureNowPlayableSessionController()
    }
}
