import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class SonoicModel {
    @ObservationIgnored static let manualPlayTransitionGraceInterval: TimeInterval = 3
    @ObservationIgnored static let homeRecentPlayLimit = 12
    @ObservationIgnored static let recentSourceSearchLimit = 8
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
    @ObservationIgnored var sharedStorePersistTask: Task<Void, Never>?
    @ObservationIgnored var pendingSharedExternalControlState: SonoicExternalControlState?
    @ObservationIgnored var lastPersistedSharedWidgetPresentation: SonoicExternalControlState.WidgetPresentation?
    @ObservationIgnored var lastSharedStorePersistAt: Date?
    @ObservationIgnored var appleMusicLibraryLoadTasks: [SonoicAppleMusicLibraryDestination: Task<Void, Never>] = [:]
    @ObservationIgnored var appleMusicBrowseLoadTasks: [SonoicAppleMusicBrowseDestination: Task<Void, Never>] = [:]
    @ObservationIgnored var appleMusicItemDetailLoadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var appleMusicRecentlyAddedLoadTask: Task<Void, Never>?
    @ObservationIgnored var isManualTransportCommandInFlight = false
    @ObservationIgnored var isManualVolumeCommandInFlight = false
    @ObservationIgnored var pendingManualVolumeLevel: Int?
    @ObservationIgnored var pendingRoomVolumeLevels: [String: Int] = [:]
    @ObservationIgnored var isRoomVolumeRefreshInFlight = false
    @ObservationIgnored var isHomeFavoritesRefreshing = false
    @ObservationIgnored var manualPlayTransitionGraceDeadline: Date?
    @ObservationIgnored var isManualPlayTransitionAwaitingConfirmation = false
    @ObservationIgnored var backgroundExecutionIdentifier: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored let sonosDiscoveryBrowser: SonosBonjourBrowser
    @ObservationIgnored var discoverySnapshotTask: Task<Void, Never>?
    @ObservationIgnored let sharedStore: SonoicSharedStore?
    @ObservationIgnored let settingsStore: SonoicSettingsStore
    @ObservationIgnored let deviceInfoClient: SonosDeviceInfoClient
    @ObservationIgnored let zoneGroupTopologyClient: SonosZoneGroupTopologyClient
    @ObservationIgnored let renderingControlClient: SonosRenderingControlClient
    @ObservationIgnored let groupRenderingControlClient: SonosGroupRenderingControlClient
    @ObservationIgnored let htControlClient: SonosHTControlClient
    @ObservationIgnored let avTransportClient: SonosAVTransportClient
    @ObservationIgnored let nowPlayingClient: SonosNowPlayingClient
    @ObservationIgnored let queueClient: SonosQueueClient
    @ObservationIgnored let favoritesClient: SonosFavoritesClient
    @ObservationIgnored let musicServicesClient: SonosMusicServicesClient
    @ObservationIgnored let appleMusicCatalogSearchClient: SonoicAppleMusicCatalogSearchClient
    @ObservationIgnored let nowPlayableSessionController: SonoicNowPlayableSessionController

    var selectedTab: RootTab = .home
    var manualSonosHost: String {
        didSet {
            settingsStore.saveManualSonosHost(manualSonosHost)
            manualHostRefreshStatus = .idle
            manualHostIdentityStatus = .idle
            manualHostTopologyStatus = .idle
            manualHostLastSuccessfulRefreshAt = nil
            queueState = .idle
            homeFavoritesState = .idle
            homeTheaterState = .idle
            homeTheaterTVDiagnostics = .empty
            roomVolumeState = .idle
            isQueueRefreshing = false
            isQueueMutating = false
            isHomeTheaterRefreshing = false
            isHomeTheaterMutating = false
            mutatingRoomVolumeIDs = []
            pendingRoomVolumeLevels = [:]
            queueOperationErrorDetail = nil
            queueDiagnostics = .empty
            groupControlErrorDetail = nil
            homeTheaterOperationErrorDetail = nil
            roomVolumeOperationErrorDetail = nil
            nowPlayingDiagnostics = .empty
            sonosMusicServiceProbeState = .idle
            resetManualHostIdentity()
            stopManualHostRefreshLoop()
            scheduleBackgroundPlayerRefreshIfPossible()
            persistSharedExternalControlState(forceImmediate: true)
        }
    }
    var manualHostRefreshStatus: SonosManualHostRefreshStatus = .idle
    var manualHostIdentityStatus: SonosRoomDataStatus = .idle
    var manualHostTopologyStatus: SonosRoomDataStatus = .idle
    var queueState: SonosQueueState = .idle
    var homeFavoritesState: SonosFavoritesState = .idle
    var homeTheaterState: SonosHomeTheaterState = .idle
    var homeTheaterTVDiagnostics = SonosHomeTheaterTVDiagnostics.empty
    var roomVolumeState: SonosRoomVolumeState = .idle
    var recentPlays: [SonoicRecentPlayItem] = []
    var recentSourceSearches: [SonoicRecentSourceSearch] = []
    var sourceSearchStates: [String: SonoicSourceSearchState] = [:]
    var appleMusicLibraryStates: [SonoicAppleMusicLibraryDestination: SonoicAppleMusicLibraryState] = [:]
    var appleMusicBrowseStates: [SonoicAppleMusicBrowseDestination: SonoicAppleMusicBrowseState] = [:]
    var appleMusicItemDetailStates: [String: SonoicAppleMusicItemDetailState] = [:]
    var appleMusicRecentlyAddedState = SonoicAppleMusicRecentlyAddedState()
    var appleMusicAuthorizationState = SonoicAppleMusicAuthorizationState.unknown
    var appleMusicServiceDetails = SonoicAppleMusicServiceDetails.idle
    var appleMusicRequestReadiness = SonoicAppleMusicRequestReadiness.idle
    var musicKitDiagnostics = SonoicMusicKitDiagnostics.current
    var sonosMusicServiceProbeState = SonosMusicServiceProbeState.idle
    var isQueueRefreshing = false
    var isQueueClearing = false
    var isQueueMutating = false
    var isGroupControlRefreshing = false
    var groupControlMutatingPlayerID: String?
    var isHomeTheaterRefreshing = false
    var isHomeTheaterMutating = false
    var mutatingRoomVolumeIDs: Set<String> = []
    var queueOperationErrorDetail: String?
    var queueDiagnostics = SonosQueueDiagnostics.empty
    var groupControlErrorDetail: String?
    var homeTheaterOperationErrorDetail: String?
    var roomVolumeOperationErrorDetail: String?
    var discoveredBonjourServices: [SonosBonjourBrowser.Service] = []
    var discoveredPlayers: [SonosDiscoveredPlayer] = []
    var discoveredGroups: [SonosDiscoveredGroup] = []
    var isSonosDiscoveryRefreshing = false
    var discoveryErrorDetail: String?
    var lastSonosDiscoveryRefreshAt: Date?
    var selectingDiscoveredPlayerID: String?

    var activeTarget = SonoicModel.unconfiguredTarget {
        didSet {
            if oldValue != activeTarget {
                queueState = .idle
                queueOperationErrorDetail = nil
                queueDiagnostics = .empty
                isQueueRefreshing = false
                isQueueClearing = false
                isQueueMutating = false
            }

            persistSharedExternalControlState()
        }
    }

    var nowPlayingObservedAt = Date()
    var nowPlayingDiagnostics = SonosNowPlayingDiagnostics.empty

    var nowPlaying = SonosNowPlayingSnapshot.unconfigured {
        didSet {
            nowPlayingObservedAt = .now
            recordRecentPlayIfNeeded(nowPlaying)
            persistSharedExternalControlState()
        }
    }

    var externalVolume = SonoicExternalControlState.Volume(level: 24, isMuted: false) {
        didSet {
            persistSharedExternalControlState()
        }
    }

    var roomDiscoveryStatus: SonosRoomDiscoveryStatus {
        if let discoveryErrorDetail = discoveryErrorDetail?.sonoicNonEmptyTrimmed {
            return .failed(discoveryErrorDetail)
        }

        if hasDiscoveredPlayers {
            return .ready
        }

        if !discoveredBonjourServices.isEmpty {
            return .resolving
        }

        return .scanning
    }

    var roomListItems: [SonosRoomListItem] {
        let selectedDiscoveredGroup = selectedDiscoveredGroup
        var items = discoveredPlayers.map { player in
            var item = player.roomListItem
            item.isActive = activeTarget.kind == .group
                ? false
                : isDiscoveredPlayerSelected(player)
            return item
        }

        let hasActiveSelection = activeTarget.kind == .group
            ? selectedDiscoveredGroup != nil
            : items.contains(where: \.isActive)

        if hasManualSonosHost,
           !hasActiveSelection
        {
            items.insert(
                SonosRoomListItem(
                    activeTarget: activeTarget,
                    source: .manualFallback,
                    isActive: true
                ),
                at: 0
            )
        }

        return items
    }

    var homeServices: [SonosServiceDescriptor] {
        var orderedServices = homeFavoritesState.snapshot?.services ?? []
        let currentSourceService = SonosServiceCatalog.descriptor(named: nowPlaying.sourceName)

        if let currentSourceService,
           !orderedServices.contains(currentSourceService)
        {
            orderedServices.append(currentSourceService)
        }

        return orderedServices
    }

    init() {
        settingsStore = SonoicSettingsStore()
        let sonosControlTransport = SonosControlTransport()
        sonosDiscoveryBrowser = SonosBonjourBrowser()
        deviceInfoClient = SonosDeviceInfoClient(transport: sonosControlTransport)
        zoneGroupTopologyClient = SonosZoneGroupTopologyClient(transport: sonosControlTransport)
        renderingControlClient = SonosRenderingControlClient(transport: sonosControlTransport)
        groupRenderingControlClient = SonosGroupRenderingControlClient(transport: sonosControlTransport)
        htControlClient = SonosHTControlClient(transport: sonosControlTransport)
        avTransportClient = SonosAVTransportClient(transport: sonosControlTransport)
        nowPlayingClient = SonosNowPlayingClient(transport: sonosControlTransport)
        queueClient = SonosQueueClient(transport: sonosControlTransport)
        favoritesClient = SonosFavoritesClient(transport: sonosControlTransport)
        musicServicesClient = SonosMusicServicesClient(transport: sonosControlTransport)
        appleMusicCatalogSearchClient = SonoicAppleMusicCatalogSearchClient()
        nowPlayableSessionController = SonoicNowPlayableSessionController()
        manualSonosHost = settingsStore.loadManualSonosHost()
        recentPlays = settingsStore.loadRecentPlays()
        recentSourceSearches = settingsStore.loadRecentSourceSearches()
        appleMusicAuthorizationState = appleMusicCatalogSearchClient.currentAuthorizationState()

        do {
            sharedStore = try SonoicSharedStore()
        } catch {
            sharedStore = nil
            assertionFailure("Unable to create the shared App Group store: \(error)")
        }

        resetManualHostIdentity()
        persistSharedExternalControlState()
        configureNowPlayableSessionController()
        configureSonosDiscoveryBrowser()
    }
}
