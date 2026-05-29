import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicModelCloudFirstStateTests {
    @Test
    func injectedSettingsStoreLoadsAndPersistsManualHost() throws {
        let (model, store) = try makeModel(savedManualHost: "192.0.2.10")

        #expect(model.manualSonosHost == "192.0.2.10")

        model.manualSonosHost = "192.0.2.11"

        #expect(store.loadManualSonosHost() == "192.0.2.11")
    }

    @Test
    func cloudCommandModeWithoutCommandTargetDoesNotUseManualHostFallback() throws {
        let (model, _) = try makeModel(
            savedManualHost: "192.0.2.10",
            sonosControlAPISettings: SonosControlAPISettings(
                mode: .preferred,
                selectedHouseholdID: "household-1",
                selectedGroupID: nil
            )
        )
        model.sonosControlAPIState.authorizationStatus = .ready
        model.activeTarget = SonosActiveTarget(
            id: "manual-room",
            name: "Manual Room",
            householdName: "Manual Room",
            kind: .room,
            memberNames: ["Manual Room"]
        )
        model.nowPlaying = SonosNowPlayingSnapshot(
            title: "Playable",
            artistName: "Sonoic",
            albumTitle: nil,
            sourceName: "Apple Music",
            playbackState: .playing
        )

        #expect(model.nowPlaying.canTogglePlayback)
        #expect(!model.canControlManualPlayback)
        #expect(!model.allowsLocalManualTransportCommands)
        #expect(model.externalControlState.availability == .unavailable)

        model.sonosControlAPIState = .disabled

        #expect(model.canControlManualPlayback)
        #expect(model.allowsLocalManualTransportCommands)
    }

    @Test
    func cloudExternalControlStateUsesCloudFreshnessWhenItIsNewest() throws {
        let (model, _) = try makeModel(
            savedManualHost: "192.0.2.10",
            sonosControlAPISettings: SonosControlAPISettings(
                mode: .preferred,
                selectedHouseholdID: "household-1",
                selectedGroupID: "group-1"
            )
        )
        let manualUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let cloudUpdatedAt = Date(timeIntervalSince1970: 1_800_000_120)
        model.sonosControlAPIState.authorizationStatus = .ready
        model.sonosControlAPIState.lastUpdatedAt = cloudUpdatedAt
        model.manualHostLastSuccessfulRefreshAt = manualUpdatedAt
        model.manualHostRefreshStatus = .updated(manualUpdatedAt)
        model.nowPlayingObservedAt = Date(timeIntervalSince1970: 1_800_000_060)
        model.activeTarget = SonosActiveTarget(
            id: "group-1",
            name: "Kitchen",
            householdName: "Kitchen",
            kind: .group,
            memberNames: ["Kitchen"]
        )

        #expect(model.externalControlState.availability == .ready)
        #expect(model.externalControlState.updatedAt == cloudUpdatedAt)
    }

    @Test
    func changingManualHostClearsCloudQueueSeekAndExternalState() throws {
        let (model, store) = try makeModel(savedManualHost: "192.0.2.10")
        let payload = playbackPayload(id: "payload-1")
        model.activeTarget = SonosActiveTarget(
            id: "living-room",
            name: "Living Room",
            householdName: "Home",
            kind: .room,
            memberNames: []
        )
        model.nowPlaying = SonosNowPlayingSnapshot(
            title: "Cloud First",
            artistName: "Sonoic",
            albumTitle: nil,
            sourceName: "Apple Music",
            playbackState: .playing,
            elapsedTime: 12,
            duration: 180
        )
        model.queueState = .loaded(queueSnapshot())
        model.isQueueRefreshing = true
        model.isQueueMutating = true
        model.sonosControlAPICloudQueueSessionID = "session-1"
        model.sonosControlAPICloudQueueGroupID = "group-1"
        model.sonosControlAPICloudQueueVersion = "version-1"
        model.sonosControlAPICloudQueueItemIDs = ["item-1"]
        model.sonosControlAPICloudQueueVersionMismatchLogKey = "group-1|version-2"
        model.manualSeekConfirmationDeadline = Date().addingTimeInterval(5)
        model.manualSeekTargetElapsedTime = 42
        model.manualSeekContentKey = "uri:x-sonos-http:track.m4a"
        model.manualPlaybackContextPayload = payload
        model.manualQueueContextPayloads = [payload]
        model.manualRecentPlaybackContextPayload = payload

        model.manualSonosHost = ""

        #expect(store.loadManualSonosHost() == "")
        #expect(model.queueState == .idle)
        #expect(!model.isQueueRefreshing)
        #expect(!model.isQueueMutating)
        #expect(model.sonosControlAPICloudQueueSessionID == nil)
        #expect(model.sonosControlAPICloudQueueGroupID == nil)
        #expect(model.sonosControlAPICloudQueueVersion == nil)
        #expect(model.sonosControlAPICloudQueueItemIDs == nil)
        #expect(model.sonosControlAPICloudQueueTracks == nil)
        #expect(model.sonosControlAPICloudQueueVersionMismatchLogKey == nil)
        #expect(model.manualSeekConfirmationDeadline == nil)
        #expect(model.manualSeekTargetElapsedTime == nil)
        #expect(model.manualSeekContentKey == nil)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
        #expect(model.manualRecentPlaybackContextPayload == nil)
        #expect(model.externalControlState.widgetPresentation == SonoicExternalControlState.unconfigured.widgetPresentation)
    }

    @Test
    func cloudAuthorizationUnavailableClearsCloudQueueAndExternalAvailability() throws {
        let (model, _) = try makeModel(
            savedManualHost: "192.0.2.10",
            sonosControlAPISettings: SonosControlAPISettings(
                mode: .preferred,
                selectedHouseholdID: "household-1",
                selectedGroupID: "group-1"
            )
        )
        let payload = playbackPayload(id: "payload-1")
        model.sonosControlAPIState.authorizationStatus = .ready
        model.manualHostRefreshStatus = .updated(Date())
        model.activeTarget = SonosActiveTarget(
            id: "group-1",
            name: "Kitchen",
            householdName: "Kitchen",
            kind: .group,
            memberNames: ["Kitchen"]
        )
        model.nowPlaying = SonosNowPlayingSnapshot(
            title: "Cloud Queue",
            artistName: "Sonoic",
            albumTitle: nil,
            sourceName: "Apple Music",
            playbackState: .playing,
            elapsedTime: 12,
            duration: 180
        )
        model.queueState = .loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(
                        id: "item-1",
                        title: "One",
                        artistName: nil,
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: 180
                    )
                ],
                currentItemIndex: 0,
                sourceURI: "sonoic-cloud-queue:queue-1"
            )
        )
        model.isQueueRefreshing = true
        model.isQueueMutating = true
        model.sonosControlAPICloudQueueSessionID = "session-1"
        model.sonosControlAPICloudQueueGroupID = "group-1"
        model.sonosControlAPICloudQueueVersion = "version-1"
        model.sonosControlAPICloudQueueItemIDs = ["item-1"]
        model.sonosControlAPICloudQueueVersionMismatchLogKey = "group-1|version-2"
        model.manualSeekConfirmationDeadline = Date().addingTimeInterval(5)
        model.manualSeekTargetElapsedTime = 42
        model.manualSeekContentKey = "uri:x-sonos-http:track.m4a"
        model.manualPlaybackContextPayload = payload
        model.manualQueueContextPayloads = [payload]
        model.manualRecentPlaybackContextPayload = payload

        model.markSonosControlAPIAuthorizationUnavailable("Expired")

        #expect(model.sonosControlAPIState.authorizationStatus == .notConfigured)
        #expect(model.canControlManualPlayback == false)
        #expect(model.queueState == .idle)
        #expect(model.isQueueRefreshing == false)
        #expect(model.isQueueMutating == false)
        #expect(model.sonosControlAPICloudQueueSessionID == nil)
        #expect(model.sonosControlAPICloudQueueGroupID == nil)
        #expect(model.sonosControlAPICloudQueueVersion == nil)
        #expect(model.sonosControlAPICloudQueueItemIDs == nil)
        #expect(model.sonosControlAPICloudQueueTracks == nil)
        #expect(model.sonosControlAPICloudQueueVersionMismatchLogKey == nil)
        #expect(model.manualSeekConfirmationDeadline == nil)
        #expect(model.manualSeekTargetElapsedTime == nil)
        #expect(model.manualSeekContentKey == nil)
        #expect(model.manualPlaybackContextPayload == nil)
        #expect(model.manualQueueContextPayloads == nil)
        #expect(model.manualRecentPlaybackContextPayload == nil)
        #expect(model.externalControlState.availability == .unavailable)
    }

    private func makeModel(
        savedManualHost: String = "",
        sonosControlAPISettings: SonosControlAPISettings = .disabled
    ) throws -> (SonoicModel, SonoicSettingsStore) {
        let suiteName = "SonoicModelCloudFirstStateTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = SonoicSettingsStore(userDefaults: userDefaults)
        store.saveManualSonosHost(savedManualHost)
        store.saveSonosControlAPISettings(sonosControlAPISettings)
        return (
            SonoicModel(
                settingsStore: store,
                startInitialSonosControlAPICloudRefresh: false
            ),
            store
        )
    }

    private func queueSnapshot() -> SonosQueueSnapshot {
        SonosQueueSnapshot(
            items: [
                SonosQueueItem(
                    id: "item-1",
                    title: "One",
                    artistName: nil,
                    albumTitle: nil,
                    artworkURL: nil,
                    duration: 180
                )
            ],
            currentItemIndex: 0,
            sourceURI: "x-rincon-queue:RINCON_00000000000001400#0"
        )
    }

    private func playbackPayload(id: String) -> SonosPlayablePayload {
        SonosPlayablePayload(
            id: id,
            title: "Cloud First",
            subtitle: nil,
            artworkURL: nil,
            service: .appleMusic,
            uri: "x-sonos-http:track-\(id).m4a",
            metadataXML: "<DIDL-Lite></DIDL-Lite>",
            kind: .item,
            launchMode: .direct,
            duration: 180
        )
    }
}
