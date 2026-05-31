import Foundation
import Testing
@testable import Sonoic

@MainActor
struct SonoicModelSonosControlAPITests {
    @Test
    func cloudCommandFailuresRollbackOptimisticState() async throws {
        let directPlayback = try Self.makeModel()
        defer {
            try? directPlayback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: directPlayback.networkStubID)
        }
        Self.configureCloudCommandTarget(on: directPlayback.model)
        let previousNowPlaying = Self.nowPlayingSnapshot(title: "Before Play", playbackState: .paused)
        let previousNowPlayingObservedAt = Date(timeIntervalSince1970: 123)
        directPlayback.model.nowPlaying = previousNowPlaying
        directPlayback.model.nowPlayingObservedAt = previousNowPlayingObservedAt
        directPlayback.model.sonosControlAPICloudQueueRuntimeState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-before",
            groupID: "group-1",
            queueVersion: "queue-before",
            itemIDs: ["item-before"]
        )

        Self.stubNetwork(for: directPlayback.networkStubID) { request in
            try Self.httpResponse(
                for: request,
                statusCode: 401,
                body: #"{"message":"Injected authorization failure"}"#
            )
        }

        let didPlay = await directPlayback.model.playSonosControlAPIPlaybackIfAvailable()

        #expect(didPlay == false)
        #expect(directPlayback.model.nowPlaying == previousNowPlaying)
        #expect(directPlayback.model.nowPlayingObservedAt == previousNowPlayingObservedAt)
        #expect(directPlayback.model.sonosControlAPIState.authorizationStatus == .expired)
        #expect(directPlayback.model.sonosControlAPIAuthorizationState.status == .expired)
        #expect(directPlayback.model.sonosControlAPICloudQueueRuntimeState == .empty)
        #expect(directPlayback.model.isManualTransportCommandInFlight == false)
        #expect(directPlayback.model.isManualPlayTransitionAwaitingConfirmation == false)

        let cloudQueue = try Self.makeModel()
        defer {
            try? cloudQueue.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: cloudQueue.networkStubID)
        }
        Self.configureCloudCommandTarget(on: cloudQueue.model)
        let previousQueueState = SonosQueueState.loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(
                        id: "1",
                        title: "Previous",
                        artistName: "Sonoic",
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: 120
                    )
                ],
                currentItemIndex: 0,
                sourceURI: "x-rincon-queue:RINCON_00000000000001400#0"
            )
        )
        let previousCloudQueueTracks = [
            Self.track(id: "previous-track", name: "Previous Track")
        ]
        let previousPayload = Self.playbackPayload(id: "previous-payload")
        let previousNowPlayingForQueue = Self.nowPlayingSnapshot(title: "Before Queue", playbackState: .playing)
        cloudQueue.model.queueState = previousQueueState
        cloudQueue.model.nowPlaying = previousNowPlayingForQueue
        cloudQueue.model.manualPlaybackContextPayload = previousPayload
        cloudQueue.model.manualQueueContextPayloads = [previousPayload]
        cloudQueue.model.manualRecentPlaybackContextPayload = previousPayload
        let previousCloudQueueRuntimeState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-before",
            groupID: "group-before",
            queueVersion: "queue-before",
            itemIDs: ["item-before"],
            tracks: previousCloudQueueTracks
        )
        cloudQueue.model.sonosControlAPICloudQueueRuntimeState = previousCloudQueueRuntimeState

        Self.stubNetwork(for: cloudQueue.networkStubID) { request in
            try Self.httpResponse(
                for: request,
                statusCode: 500,
                body: #"{"message":"Injected cloud queue failure"}"#
            )
        }

        let didLoadQueue = await cloudQueue.model.playSonosControlAPICloudQueueIfAvailable(
            parentItem: Self.playlistItem(),
            plan: Self.playlistPlan()
        )

        #expect(didLoadQueue == false)
        #expect(cloudQueue.model.queueState == previousQueueState)
        #expect(cloudQueue.model.nowPlaying == previousNowPlayingForQueue)
        #expect(cloudQueue.model.manualPlaybackContextPayload == previousPayload)
        #expect(cloudQueue.model.manualQueueContextPayloads == [previousPayload])
        #expect(cloudQueue.model.manualRecentPlaybackContextPayload == previousPayload)
        #expect(cloudQueue.model.sonosControlAPICloudQueueRuntimeState == previousCloudQueueRuntimeState)
        #expect(cloudQueue.model.isManualTransportCommandInFlight == false)
        #expect(cloudQueue.model.sonosControlAPIState.authorizationStatus == .ready)
    }

    @Test
    func loadRollbackAuthorizationLossRestoresManualQueueAndClearsContexts() throws {
        let playback = try Self.makeModel()
        defer {
            try? playback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: playback.networkStubID)
        }
        let previousQueueState = SonosQueueState.loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(
                        id: "manual-item-before",
                        title: "Manual Before",
                        artistName: "Sonoic",
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: 120
                    )
                ],
                currentItemIndex: 0,
                sourceURI: "x-rincon-queue:RINCON_00000000000001400#0"
            )
        )
        let previousNowPlaying = Self.nowPlayingSnapshot(title: "Manual Before", playbackState: .playing)
        let previousObservedAt = Date(timeIntervalSince1970: 1_234)
        let previousPayload = Self.playbackPayload(id: "manual-before")
        let previousCloudQueueRuntimeState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-before",
            groupID: "group-before",
            queueVersion: "queue-before",
            itemIDs: ["item-before"]
        )
        playback.model.queueState = previousQueueState
        playback.model.nowPlaying = previousNowPlaying
        playback.model.nowPlayingObservedAt = previousObservedAt
        playback.model.manualPlaybackContextPayload = previousPayload
        playback.model.manualQueueContextPayloads = [previousPayload]
        playback.model.manualRecentPlaybackContextPayload = previousPayload
        playback.model.sonosControlAPICloudQueueRuntimeState = previousCloudQueueRuntimeState
        let rollbackState = SonoicModel.SonosControlAPILoadRollbackState(playback.model)

        let optimisticPayload = Self.playbackPayload(id: "optimistic-load")
        playback.model.queueState = .loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(
                        id: "cloud-item",
                        title: "Cloud Item",
                        artistName: "Sonoic",
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: 180
                    )
                ],
                currentItemIndex: 0,
                sourceURI: "sonoic-cloud-queue:optimistic"
            )
        )
        playback.model.nowPlaying = Self.nowPlayingSnapshot(title: "Optimistic Load", playbackState: .buffering)
        playback.model.nowPlayingObservedAt = Date(timeIntervalSince1970: 9_876)
        playback.model.manualPlaybackContextPayload = optimisticPayload
        playback.model.manualQueueContextPayloads = [optimisticPayload]
        playback.model.manualRecentPlaybackContextPayload = optimisticPayload
        playback.model.sonosControlAPICloudQueueRuntimeState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "optimistic-session",
            groupID: "group-1",
            queueVersion: "optimistic-version",
            itemIDs: ["cloud-item"]
        )

        rollbackState.restoreFailedLoad(
            on: playback.model,
            didLoseAuthorization: true,
            clearManualContextOnAuthorizationLoss: true
        )

        #expect(playback.model.queueState == previousQueueState)
        #expect(playback.model.nowPlaying == previousNowPlaying)
        #expect(playback.model.nowPlayingObservedAt == previousObservedAt)
        #expect(playback.model.manualPlaybackContextPayload == nil)
        #expect(playback.model.manualQueueContextPayloads == nil)
        #expect(playback.model.manualRecentPlaybackContextPayload == nil)
        #expect(playback.model.sonosControlAPICloudQueueRuntimeState == .empty)
    }

    @Test
    func transportCommandSkipsActionWhenAlreadyInFlight() async throws {
        let playback = try Self.makeModel()
        defer {
            try? playback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: playback.networkStubID)
        }
        let previousCommandDescription = playback.model.sonosControlAPIState.lastCommandDescription
        let previousErrorDetail = playback.model.sonosControlAPIState.lastErrorDetail
        let previousUpdatedAt = playback.model.sonosControlAPIState.lastUpdatedAt
        playback.model.isManualTransportCommandInFlight = true
        var didRunAction = false

        let didPerform = await playback.model.performSonosControlAPITransportCommand(
            description: "Cloud duplicate",
            refreshQueueAfterSuccess: true
        ) {
            didRunAction = true
        }

        #expect(didPerform == false)
        #expect(didRunAction == false)
        #expect(playback.model.isManualTransportCommandInFlight == true)
        #expect(playback.model.sonosControlAPIState.lastCommandDescription == previousCommandDescription)
        #expect(playback.model.sonosControlAPIState.lastErrorDetail == previousErrorDetail)
        #expect(playback.model.sonosControlAPIState.lastUpdatedAt == previousUpdatedAt)
    }

    @Test
    func transportCommandClearsStaleRefreshTasksBeforeAction() async throws {
        let playback = try Self.makeModel()
        let staleRefreshTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(60))
        }
        let staleDeferredSyncTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(60))
        }
        let staleConfirmationRetryTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(60))
        }
        defer {
            staleRefreshTask.cancel()
            staleDeferredSyncTask.cancel()
            staleConfirmationRetryTask.cancel()
            playback.model.manualHostRefreshTask?.cancel()
            playback.model.manualHostRefreshTask = nil
            playback.model.manualHostDeferredSyncTask?.cancel()
            playback.model.manualHostDeferredSyncTask = nil
            playback.model.manualPlayConfirmationRetryTask?.cancel()
            playback.model.manualPlayConfirmationRetryTask = nil
            try? playback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: playback.networkStubID)
        }
        Self.configureCloudCommandTarget(on: playback.model)
        playback.model.manualHostRefreshTask = staleRefreshTask
        playback.model.manualHostDeferredSyncTask = staleDeferredSyncTask
        playback.model.manualPlayConfirmationRetryTask = staleConfirmationRetryTask
        let injectedError = NSError(
            domain: "SonoicModelSonosControlAPITests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Injected cleanup failure"]
        )
        var didRunAction = false

        let didPerform = await playback.model.performSonosControlAPITransportCommand(
            description: "Cloud cleanup",
            refreshQueueAfterSuccess: true
        ) {
            didRunAction = true
            #expect(staleRefreshTask.isCancelled)
            #expect(staleDeferredSyncTask.isCancelled)
            #expect(staleConfirmationRetryTask.isCancelled)
            #expect(playback.model.manualHostRefreshTask == nil)
            #expect(playback.model.manualHostDeferredSyncTask == nil)
            #expect(playback.model.manualPlayConfirmationRetryTask == nil)
            throw injectedError
        }

        #expect(didPerform == false)
        #expect(didRunAction)
        #expect(playback.model.manualHostRefreshTask == nil)
        #expect(playback.model.manualHostDeferredSyncTask == nil)
        #expect(playback.model.manualPlayConfirmationRetryTask == nil)
    }

    @Test
    func transportCommandRecordsNonAuthorizationFailureDiagnostics() async throws {
        let playback = try Self.makeModel()
        defer {
            try? playback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: playback.networkStubID)
        }
        Self.configureCloudCommandTarget(on: playback.model)
        let injectedError = NSError(
            domain: "SonoicModelSonosControlAPITests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Injected non-authorization failure"]
        )
        playback.model.manualPlayTransitionGraceDeadline = Date().addingTimeInterval(60)
        playback.model.isManualPlayTransitionAwaitingConfirmation = true
        playback.model.manualSeekConfirmationDeadline = Date().addingTimeInterval(60)
        playback.model.manualSeekTargetElapsedTime = 42
        playback.model.manualSeekContentKey = "uri:x-sonos-http:track.m4a"
        var didRunAction = false

        let didPerform = await playback.model.performSonosControlAPITransportCommand(
            description: "Cloud transient failure",
            refreshQueueAfterSuccess: true
        ) {
            didRunAction = true
            throw injectedError
        }

        #expect(didPerform == false)
        #expect(didRunAction)
        #expect(playback.model.isManualTransportCommandInFlight == false)
        #expect(playback.model.sonosControlAPIState.authorizationStatus == .ready)
        #expect(playback.model.sonosControlAPIState.lastErrorDetail == injectedError.localizedDescription)
        #expect(playback.model.sonosControlAPIState.lastCommandDescription == nil)
        #expect(playback.model.manualHostRefreshStatus == .failed(injectedError.localizedDescription))
        #expect(playback.model.manualPlayTransitionGraceDeadline == nil)
        #expect(playback.model.isManualPlayTransitionAwaitingConfirmation == false)
        #expect(playback.model.manualSeekConfirmationDeadline == nil)
        #expect(playback.model.manualSeekTargetElapsedTime == nil)
        #expect(playback.model.manualSeekContentKey == nil)
    }

    @Test
    func transportCommandRecordsAuthorizationFailureDiagnostics() async throws {
        let playback = try Self.makeModel()
        defer {
            playback.model.manualHostRefreshTask?.cancel()
            playback.model.manualHostRefreshTask = nil
            playback.model.manualHostDeferredSyncTask?.cancel()
            playback.model.manualHostDeferredSyncTask = nil
            try? playback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: playback.networkStubID)
        }
        Self.configureCloudCommandTarget(on: playback.model)
        let injectedError = SonosControlAPITransport.TransportError.httpStatus(401, "Token expired")
        playback.model.manualPlayTransitionGraceDeadline = Date().addingTimeInterval(60)
        playback.model.isManualPlayTransitionAwaitingConfirmation = true
        playback.model.manualSeekConfirmationDeadline = Date().addingTimeInterval(60)
        playback.model.manualSeekTargetElapsedTime = 42
        playback.model.manualSeekContentKey = "uri:x-sonos-http:track.m4a"
        var didRunAction = false

        let didPerform = await playback.model.performSonosControlAPITransportCommand(
            description: "Cloud auth failure",
            refreshQueueAfterSuccess: true
        ) {
            didRunAction = true
            throw injectedError
        }

        #expect(didPerform == false)
        #expect(didRunAction)
        #expect(playback.model.sonosControlAPIState.authorizationStatus == .expired)
        #expect(playback.model.sonosControlAPIAuthorizationState.status == .expired)
        #expect(playback.model.sonosControlAPIState.lastErrorDetail == injectedError.localizedDescription)
        #expect(playback.model.sonosControlAPIState.lastCommandDescription == nil)
        #expect(playback.model.sonosControlAPIState.lastUpdatedAt != nil)
        #expect(playback.model.isManualTransportCommandInFlight == false)
        #expect(playback.model.manualHostRefreshStatus == .failed(injectedError.localizedDescription))
        #expect(playback.model.manualHostRefreshTask == nil)
        #expect(playback.model.manualHostDeferredSyncTask == nil)
        #expect(playback.model.manualPlayTransitionGraceDeadline == nil)
        #expect(playback.model.isManualPlayTransitionAwaitingConfirmation == false)
        #expect(playback.model.manualSeekConfirmationDeadline == nil)
        #expect(playback.model.manualSeekTargetElapsedTime == nil)
        #expect(playback.model.manualSeekContentKey == nil)
    }

    @Test
    func transportCommandRecordsSuccessDiagnosticsAndSchedulesSync() async throws {
        let playback = try Self.makeModel()
        defer {
            playback.model.manualHostDeferredSyncTask?.cancel()
            playback.model.manualHostDeferredSyncTask = nil
            try? playback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: playback.networkStubID)
        }
        Self.configureCloudCommandTarget(on: playback.model)
        playback.model.sonosControlAPIState.lastErrorDetail = "Previous failure"
        playback.model.sonosControlAPIState.lastUpdatedAt = nil
        var didRunAction = false

        let didPerform = await playback.model.performSonosControlAPITransportCommand(
            description: "Cloud success",
            refreshQueueAfterSuccess: true,
            syncDelay: .seconds(60)
        ) {
            didRunAction = true
        }

        #expect(didPerform)
        #expect(didRunAction)
        #expect(playback.model.isManualTransportCommandInFlight == false)
        #expect(playback.model.sonosControlAPIState.lastErrorDetail == nil)
        #expect(playback.model.sonosControlAPIState.lastCommandDescription == "Cloud success")
        #expect(playback.model.sonosControlAPIState.lastUpdatedAt != nil)
        #expect(playback.model.manualHostRefreshStatus == .refreshing)
        #expect(playback.model.manualHostDeferredSyncTask != nil)
    }

    @Test
    func transientCloudQueueLoadFailureRestoresPreviousCloudQueueContext() async throws {
        let cloudQueue = try Self.makeModel()
        defer {
            try? cloudQueue.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: cloudQueue.networkStubID)
        }
        Self.configureCloudCommandTarget(on: cloudQueue.model)
        let previousPayload = Self.playbackPayload(id: "previous-cloud-payload")
        let previousRecentPayload = Self.playbackPayload(id: "previous-cloud-recent")
        let previousNowPlaying = Self.nowPlayingSnapshot(title: "Previous Cloud Queue", playbackState: .playing)
        let previousObservedAt = Date(timeIntervalSince1970: 2_468)
        let previousQueueState = SonosQueueState.loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(
                        id: "cloud-item-before",
                        title: "Cloud Before",
                        artistName: "Sonoic",
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: 180
                    )
                ],
                currentItemIndex: 0,
                sourceURI: "sonoic-cloud-queue:previous"
            )
        )
        let previousCloudQueueRuntimeState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-before",
            groupID: "group-before",
            queueVersion: "queue-before",
            itemIDs: ["cloud-item-before"],
            tracks: [
                Self.track(id: "cloud-item-before", name: "Cloud Before")
            ]
        )
        cloudQueue.model.queueState = previousQueueState
        cloudQueue.model.nowPlaying = previousNowPlaying
        cloudQueue.model.nowPlayingObservedAt = previousObservedAt
        cloudQueue.model.manualPlaybackContextPayload = previousPayload
        cloudQueue.model.manualQueueContextPayloads = [previousPayload]
        cloudQueue.model.manualRecentPlaybackContextPayload = previousRecentPayload
        cloudQueue.model.sonosControlAPICloudQueueRuntimeState = previousCloudQueueRuntimeState

        Self.stubNetwork(for: cloudQueue.networkStubID) { request in
            try Self.httpResponse(
                for: request,
                statusCode: 500,
                body: #"{"message":"Injected transient cloud queue failure"}"#
            )
        }

        let didLoadQueue = await cloudQueue.model.playSonosControlAPICloudQueueIfAvailable(
            parentItem: Self.playlistItem(),
            plan: Self.playlistPlan()
        )

        #expect(didLoadQueue == false)
        #expect(cloudQueue.model.sonosControlAPIState.authorizationStatus == .ready)
        #expect(cloudQueue.model.queueState == previousQueueState)
        #expect(cloudQueue.model.nowPlaying == previousNowPlaying)
        #expect(cloudQueue.model.nowPlayingObservedAt == previousObservedAt)
        #expect(cloudQueue.model.manualPlaybackContextPayload == previousPayload)
        #expect(cloudQueue.model.manualQueueContextPayloads == [previousPayload])
        #expect(cloudQueue.model.manualRecentPlaybackContextPayload == previousRecentPayload)
        #expect(cloudQueue.model.sonosControlAPICloudQueueRuntimeState == previousCloudQueueRuntimeState)
        #expect(cloudQueue.model.isManualTransportCommandInFlight == false)
    }

    @Test
    func cloudSkipFailureRestoresPayloadAndFreshness() async throws {
        let next = try Self.makeModel()
        defer {
            try? next.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: next.networkStubID)
        }
        Self.configureCloudCommandTarget(on: next.model)
        let previousPayload = Self.playbackPayload(id: "current-payload")
        let previousNowPlaying = Self.nowPlayingSnapshot(title: "Before Next", playbackState: .buffering)
        let previousObservedAt = Date(timeIntervalSince1970: 456)
        next.model.manualPlaybackContextPayload = previousPayload
        next.model.nowPlaying = previousNowPlaying
        next.model.nowPlayingObservedAt = previousObservedAt
        Self.stubNetwork(for: next.networkStubID) { request in
            try Self.httpResponse(
                for: request,
                statusCode: 500,
                body: #"{"message":"Injected next failure"}"#
            )
        }

        let didSkipNext = await next.model.skipToNextSonosControlAPITrackIfAvailable()

        #expect(didSkipNext == false)
        #expect(next.model.nowPlaying == previousNowPlaying)
        #expect(next.model.nowPlayingObservedAt == previousObservedAt)
        #expect(next.model.manualPlaybackContextPayload == previousPayload)

        let previous = try Self.makeModel()
        defer {
            try? previous.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: previous.networkStubID)
        }
        Self.configureCloudCommandTarget(on: previous.model)
        previous.model.manualPlaybackContextPayload = previousPayload
        previous.model.nowPlaying = previousNowPlaying
        previous.model.nowPlayingObservedAt = previousObservedAt
        Self.stubNetwork(for: previous.networkStubID) { request in
            try Self.httpResponse(
                for: request,
                statusCode: 500,
                body: #"{"message":"Injected previous failure"}"#
            )
        }

        let didSkipPrevious = await previous.model.skipToPreviousSonosControlAPITrackIfAvailable()

        #expect(didSkipPrevious == false)
        #expect(previous.model.nowPlaying == previousNowPlaying)
        #expect(previous.model.nowPlayingObservedAt == previousObservedAt)
        #expect(previous.model.manualPlaybackContextPayload == previousPayload)
    }

    @Test
    func cloudSkipAuthorizationFailureDoesNotRestorePlaybackContext() async throws {
        let next = try Self.makeModel()
        defer {
            try? next.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: next.networkStubID)
        }
        Self.configureCloudCommandTarget(on: next.model)
        let previousPayload = Self.playbackPayload(id: "current-payload")
        let previousNowPlaying = Self.nowPlayingSnapshot(title: "Before Next", playbackState: .buffering)
        let previousObservedAt = Date(timeIntervalSince1970: 789)
        next.model.manualPlaybackContextPayload = previousPayload
        next.model.nowPlaying = previousNowPlaying
        next.model.nowPlayingObservedAt = previousObservedAt
        Self.stubNetwork(for: next.networkStubID) { request in
            try Self.httpResponse(
                for: request,
                statusCode: 401,
                body: #"{"message":"Injected next authorization failure"}"#
            )
        }

        let didSkipNext = await next.model.skipToNextSonosControlAPITrackIfAvailable()

        #expect(didSkipNext == false)
        #expect(next.model.nowPlaying == previousNowPlaying)
        #expect(next.model.nowPlayingObservedAt == previousObservedAt)
        #expect(next.model.sonosControlAPIState.authorizationStatus == .expired)
        #expect(next.model.sonosControlAPIAuthorizationState.status == .expired)
        #expect(next.model.manualPlaybackContextPayload == nil)
        #expect(next.model.isManualTransportCommandInFlight == false)

        let previous = try Self.makeModel()
        defer {
            try? previous.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: previous.networkStubID)
        }
        Self.configureCloudCommandTarget(on: previous.model)
        previous.model.manualPlaybackContextPayload = previousPayload
        previous.model.nowPlaying = previousNowPlaying
        previous.model.nowPlayingObservedAt = previousObservedAt
        Self.stubNetwork(for: previous.networkStubID) { request in
            try Self.httpResponse(
                for: request,
                statusCode: 401,
                body: #"{"message":"Injected previous authorization failure"}"#
            )
        }

        let didSkipPrevious = await previous.model.skipToPreviousSonosControlAPITrackIfAvailable()

        #expect(didSkipPrevious == false)
        #expect(previous.model.nowPlaying == previousNowPlaying)
        #expect(previous.model.nowPlayingObservedAt == previousObservedAt)
        #expect(previous.model.sonosControlAPIState.authorizationStatus == .expired)
        #expect(previous.model.sonosControlAPIAuthorizationState.status == .expired)
        #expect(previous.model.manualPlaybackContextPayload == nil)
        #expect(previous.model.isManualTransportCommandInFlight == false)
    }

    @Test
    func cloudQueueAuthorizationFailureDoesNotRestoreStaleQueueContext() async throws {
        let cloudQueue = try Self.makeModel()
        defer {
            try? cloudQueue.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: cloudQueue.networkStubID)
        }
        Self.configureCloudCommandTarget(on: cloudQueue.model)
        let previousPayload = Self.playbackPayload(id: "previous-payload")
        cloudQueue.model.queueState = .loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(
                        id: "item-before",
                        title: "Before",
                        artistName: "Sonoic",
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: 180
                    )
                ],
                currentItemIndex: 0,
                sourceURI: "sonoic-cloud-queue:previous"
            )
        )
        cloudQueue.model.manualPlaybackContextPayload = previousPayload
        cloudQueue.model.manualQueueContextPayloads = [previousPayload]
        cloudQueue.model.manualRecentPlaybackContextPayload = previousPayload
        cloudQueue.model.sonosControlAPICloudQueueRuntimeState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-before",
            groupID: "group-before",
            queueVersion: "queue-before",
            itemIDs: ["item-before"],
            tracks: [
                Self.track(id: "previous-track", name: "Previous Track")
            ]
        )

        Self.stubNetwork(for: cloudQueue.networkStubID) { request in
            try Self.httpResponse(
                for: request,
                statusCode: 401,
                body: #"{"message":"Injected cloud queue authorization failure"}"#
            )
        }

        let didLoadQueue = await cloudQueue.model.playSonosControlAPICloudQueueIfAvailable(
            parentItem: Self.playlistItem(),
            plan: Self.playlistPlan()
        )

        #expect(didLoadQueue == false)
        #expect(cloudQueue.model.sonosControlAPIState.authorizationStatus == .expired)
        #expect(cloudQueue.model.sonosControlAPIAuthorizationState.status == .expired)
        #expect(cloudQueue.model.queueState == .idle)
        #expect(cloudQueue.model.manualPlaybackContextPayload == nil)
        #expect(cloudQueue.model.manualQueueContextPayloads == nil)
        #expect(cloudQueue.model.manualRecentPlaybackContextPayload == nil)
        #expect(cloudQueue.model.sonosControlAPICloudQueueRuntimeState == .empty)
        #expect(cloudQueue.model.isManualTransportCommandInFlight == false)
    }

    @Test
    func cloudFavoriteAuthorizationFailureDoesNotRestoreStalePlaybackContext() async throws {
        let favoritePlayback = try Self.makeModel()
        defer {
            try? favoritePlayback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: favoritePlayback.networkStubID)
        }
        Self.configureCloudCommandTarget(
            on: favoritePlayback.model,
            snapshot: Self.cloudSnapshotWithContent(favorites: [Self.cloudFavorite()])
        )
        let previousPayload = Self.playbackPayload(id: "previous-payload")
        let previousNowPlaying = Self.nowPlayingSnapshot(title: "Before Favorite", playbackState: .playing)
        let previousObservedAt = Date(timeIntervalSince1970: 987)
        favoritePlayback.model.queueState = .loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(
                        id: "item-before",
                        title: "Before",
                        artistName: "Sonoic",
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: 180
                    )
                ],
                currentItemIndex: 0,
                sourceURI: "sonoic-cloud-queue:previous"
            )
        )
        favoritePlayback.model.nowPlaying = previousNowPlaying
        favoritePlayback.model.nowPlayingObservedAt = previousObservedAt
        favoritePlayback.model.manualPlaybackContextPayload = previousPayload
        favoritePlayback.model.manualQueueContextPayloads = [previousPayload]
        favoritePlayback.model.manualRecentPlaybackContextPayload = previousPayload
        favoritePlayback.model.sonosControlAPICloudQueueRuntimeState = SonosControlAPICloudQueueRuntimeState(
            sessionID: "session-before",
            groupID: "group-before",
            queueVersion: "queue-before",
            itemIDs: ["item-before"],
            tracks: [
                Self.track(id: "previous-track", name: "Previous Track")
            ]
        )
        Self.stubNetwork(for: favoritePlayback.networkStubID) { request in
            try Self.httpResponse(
                for: request,
                statusCode: 401,
                body: #"{"message":"Injected favorite authorization failure"}"#
            )
        }

        let didLoadFavorite = await favoritePlayback.model.playSonosControlAPIFavoriteIfAvailable(
            Self.favoriteItem()
        )

        #expect(didLoadFavorite == false)
        #expect(favoritePlayback.model.sonosControlAPIState.authorizationStatus == .expired)
        #expect(favoritePlayback.model.sonosControlAPIAuthorizationState.status == .expired)
        #expect(favoritePlayback.model.queueState == .idle)
        #expect(favoritePlayback.model.nowPlaying == previousNowPlaying)
        #expect(favoritePlayback.model.nowPlayingObservedAt == previousObservedAt)
        #expect(favoritePlayback.model.manualPlaybackContextPayload == nil)
        #expect(favoritePlayback.model.manualQueueContextPayloads == nil)
        #expect(favoritePlayback.model.manualRecentPlaybackContextPayload == nil)
        #expect(favoritePlayback.model.sonosControlAPICloudQueueRuntimeState == .empty)
        #expect(favoritePlayback.model.isManualTransportCommandInFlight == false)
    }

    @Test
    func directFavoriteWithoutCloudMatchDoesNotCreateCloudQueue() async throws {
        let favoritePlayback = try Self.makeModel()
        defer {
            try? favoritePlayback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: favoritePlayback.networkStubID)
        }
        Self.configureCloudCommandTarget(on: favoritePlayback.model)
        let previousNowPlaying = Self.nowPlayingSnapshot(title: "Before Favorite", playbackState: .paused)
        let previousQueueState = SonosQueueState.loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(
                        id: "item-before",
                        title: "Before",
                        artistName: "Sonoic",
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: 180
                    )
                ],
                currentItemIndex: 0,
                sourceURI: "x-rincon-queue:RINCON_00000000000001400#0"
            )
        )
        favoritePlayback.model.nowPlaying = previousNowPlaying
        favoritePlayback.model.queueState = previousQueueState
        let recorder = SonoicModelSonosControlAPIRequestRecorder()
        Self.stubNetwork(for: favoritePlayback.networkStubID) { request in
            recorder.record(request)
            return try Self.httpResponse(
                for: request,
                statusCode: 500,
                body: #"{"message":"Unexpected direct favorite network request"}"#
            )
        }

        let didPlay = await favoritePlayback.model.playManualSonosFavorite(Self.favoriteItem())

        #expect(didPlay == false)
        #expect(recorder.paths.isEmpty)
        #expect(favoritePlayback.model.nowPlaying == previousNowPlaying)
        #expect(favoritePlayback.model.queueState == previousQueueState)
        #expect(favoritePlayback.model.manualPlaybackContextPayload == nil)
        #expect(favoritePlayback.model.manualQueueContextPayloads == nil)
        #expect(favoritePlayback.model.manualRecentPlaybackContextPayload == nil)
        #expect(favoritePlayback.model.sonosControlAPICloudQueueRuntimeState == .empty)
    }

    @Test
    func sourceSearchSongUsesQueuePayloadForSingleItemCloudQueuePlayback() async throws {
        let playback = try Self.makeModel()
        defer {
            playback.model.manualHostDeferredSyncTask?.cancel()
            playback.model.manualHostDeferredSyncTask = nil
            try? playback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: playback.networkStubID)
        }
        playback.model.manualSonosHost = "192.0.2.10"
        Self.configureCloudCommandTarget(on: playback.model)
        playback.model.sonosMusicServiceProbeState = SonosMusicServiceProbeState(
            status: .loaded,
            snapshot: Self.appleMusicServiceSnapshot()
        )
        playback.model.nowPlayingDiagnostics = SonosNowPlayingDiagnostics(
            currentURI: nil,
            trackURI: "x-sonos-http:librarytrack%3aexample.m4p?sid=204&flags=8232&sn=7",
            rawDuration: nil,
            rawElapsedTime: nil,
            hasTrackMetadata: false,
            hasSourceMetadata: false,
            usedFallbackSnapshot: false
        )
        let sourceItem = Self.appleMusicSearchSong()
        #expect(try playback.model.sourcePlayablePayload(for: sourceItem, purpose: .directPlay) == nil)
        #expect(try playback.model.sourcePlayablePayload(for: sourceItem, purpose: .queueEntry) == nil)
        #expect(playback.model.canPlaySourceItem(sourceItem))
        let recorder = SonoicModelSonosControlAPIRequestRecorder()
        Self.stubNetwork(for: playback.networkStubID) { request in
            recorder.record(request)
            switch request.url?.path {
            case "/api/sonos/cloud-queues":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: """
                    {
                      "queueId": "queue-1",
                      "queueBaseUrl": "https://sonos.test/cloud-queues/queue-1/v2.3",
                      "contextVersion": "context-1",
                      "queueVersion": "queue-version-1",
                      "startItemId": "queue-start-item",
                      "trackMetadata": null
                    }
                    """
                )
            case "/control/api/v1/groups/group-1/playbackSession":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: #"{"sessionId":"session-1","sessionState":"SESSION_STATE_CONNECTED","sessionCreated":true}"#
                )
            case "/control/api/v1/playbackSessions/session-1/playbackSession/loadCloudQueue":
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: "{}"
                )
            default:
                return try Self.httpResponse(
                    for: request,
                    statusCode: 500,
                    body: #"{"message":"Unexpected endpoint"}"#
                )
            }
        }

        let didPlay = try await playback.model.playSourceItem(sourceItem)
        playback.model.manualHostDeferredSyncTask?.cancel()
        playback.model.manualHostDeferredSyncTask = nil

        let createRequest = try #require(recorder.requests.first { $0.url?.path == "/api/sonos/cloud-queues" })
        let createBody = try Self.cloudQueueCreateRequestBody(from: createRequest)
        let loadRequest = try #require(
            recorder.requests.first { $0.url?.path == "/control/api/v1/playbackSessions/session-1/playbackSession/loadCloudQueue" }
        )
        let loadBody = try Self.loadCloudQueueRequestBody(from: loadRequest)

        #expect(didPlay)
        #expect(recorder.paths == [
            "/api/sonos/cloud-queues",
            "/control/api/v1/groups/group-1/playbackSession",
            "/control/api/v1/playbackSessions/session-1/playbackSession/loadCloudQueue",
        ])
        #expect(createBody.items.count == 1)
        let createdItem = try #require(createBody.items.first)
        #expect(createBody.container.name == "Sweet Jane")
        #expect(createdItem.track?.name == "Sweet Jane")
        #expect(createdItem.track?.id?.objectId == "song:1440857781")
        #expect(loadBody.itemId == "queue-start-item")
        #expect(loadBody.queueVersion == "queue-version-1")
        #expect(playback.model.manualQueueContextPayloads?.first?.uri == "x-sonosapi-hls-static:song%3a1440857781?sid=204&flags=0&sn=7")
        #expect(playback.model.manualPlaybackContextPayload?.uri == "x-sonosapi-hls-static:song%3a1440857781?sid=204&flags=0&sn=7")
        #expect(playback.model.manualRecentPlaybackContextPayload?.uri == "x-sonosapi-hls-static:song%3a1440857781?sid=204&flags=0&sn=7")
        #expect(playback.model.nowPlaying.title == "Sweet Jane")
        let appleMusicProbeRow = try #require(
            playback.model.sonosMusicServiceProbeState.snapshot?.knownServiceRows.first { $0.service == .appleMusic }
        )
        #expect(appleMusicProbeRow.playbackHint?.trackSerials == ["7"])
        #expect(playback.model.sonosControlAPICloudQueueRuntimeState.sessionID == "session-1")
        #expect(playback.model.sonosControlAPICloudQueueRuntimeState.queueVersion == "queue-version-1")
        #expect(playback.model.queueState.snapshot?.items.map(\.title) == ["Sweet Jane"])
    }

    @Test
    func matchedDirectFavoriteUsesControlAPIFavoriteEndpointWithoutCloudQueue() async throws {
        let favoritePlayback = try Self.makeModel()
        defer {
            favoritePlayback.model.manualHostDeferredSyncTask?.cancel()
            favoritePlayback.model.manualHostDeferredSyncTask = nil
            try? favoritePlayback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: favoritePlayback.networkStubID)
        }
        Self.configureCloudCommandTarget(
            on: favoritePlayback.model,
            snapshot: Self.cloudSnapshotWithContent(favorites: [Self.cloudFavorite()])
        )
        favoritePlayback.model.queueState = .loaded(
            SonosQueueSnapshot(
                items: [
                    SonosQueueItem(
                        id: "item-before",
                        title: "Before",
                        artistName: "Sonoic",
                        albumTitle: nil,
                        artworkURL: nil,
                        duration: 180
                    )
                ],
                currentItemIndex: 0,
                sourceURI: "x-rincon-queue:RINCON_00000000000001400#0"
            )
        )
        let recorder = SonoicModelSonosControlAPIRequestRecorder()
        Self.stubNetwork(for: favoritePlayback.networkStubID) { request in
            recorder.record(request)
            if request.url?.path == "/control/api/v1/groups/group-1/favorites" {
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: "{}"
                )
            }

            return try Self.httpResponse(
                for: request,
                statusCode: 500,
                body: #"{"message":"Unexpected non-favorite endpoint"}"#
            )
        }

        let didPlay = await favoritePlayback.model.playManualSonosFavorite(Self.favoriteItem())
        favoritePlayback.model.manualHostDeferredSyncTask?.cancel()
        favoritePlayback.model.manualHostDeferredSyncTask = nil

        let request = try #require(recorder.requests.first)
        let loadFavoriteRequest = try Self.loadFavoriteRequestBody(from: request)
        #expect(didPlay)
        #expect(recorder.paths == ["/control/api/v1/groups/group-1/favorites"])
        #expect(loadFavoriteRequest.favoriteId == "cloud-favorite-1")
        #expect(loadFavoriteRequest.action == .replace)
        #expect(loadFavoriteRequest.playOnCompletion == true)
        #expect(!recorder.paths.contains("/api/sonos/cloud-queues"))
        #expect(favoritePlayback.model.nowPlaying.title == "Cloud Favorite")
        #expect(favoritePlayback.model.nowPlaying.artistName == "Sonoic")
        #expect(favoritePlayback.model.nowPlaying.playbackState == .playing)
        #expect(favoritePlayback.model.manualPlaybackContextPayload == Self.favoriteItem().playablePayload)
        #expect(favoritePlayback.model.manualQueueContextPayloads == nil)
        #expect(favoritePlayback.model.manualRecentPlaybackContextPayload == nil)
        #expect(favoritePlayback.model.sonosControlAPICloudQueueRuntimeState == .empty)
        #expect(favoritePlayback.model.queueState.snapshot?.sourceURI == "x-rincon-queue:RINCON_00000000000001400#0")
        #expect(favoritePlayback.model.queueState.snapshot?.currentItemIndex == nil)
    }

    @Test
    func matchedCollectionFavoriteUsesControlAPIPlaylistEndpointWithAutoplay() async throws {
        let favoritePlayback = try Self.makeModel()
        defer {
            favoritePlayback.model.manualHostDeferredSyncTask?.cancel()
            favoritePlayback.model.manualHostDeferredSyncTask = nil
            try? favoritePlayback.keychainStore.deleteSonosTokenSet()
            SonoicModelSonosControlAPIURLProtocol.removeResponder(id: favoritePlayback.networkStubID)
        }
        Self.configureCloudCommandTarget(
            on: favoritePlayback.model,
            snapshot: Self.cloudSnapshotWithContent(playlists: [Self.cloudPlaylist()])
        )
        let recorder = SonoicModelSonosControlAPIRequestRecorder()
        Self.stubNetwork(for: favoritePlayback.networkStubID) { request in
            recorder.record(request)
            if request.url?.path == "/control/api/v1/groups/group-1/playlists" {
                return try Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    body: "{}"
                )
            }

            return try Self.httpResponse(
                for: request,
                statusCode: 500,
                body: #"{"message":"Unexpected non-playlist endpoint"}"#
            )
        }

        let didPlay = await favoritePlayback.model.playManualSonosFavorite(Self.collectionFavoriteItem())
        favoritePlayback.model.manualHostDeferredSyncTask?.cancel()
        favoritePlayback.model.manualHostDeferredSyncTask = nil

        let request = try #require(recorder.requests.first)
        let loadPlaylistRequest = try Self.loadPlaylistRequestBody(from: request)
        #expect(didPlay)
        #expect(recorder.paths == ["/control/api/v1/groups/group-1/playlists"])
        #expect(loadPlaylistRequest.playlistId == "cloud-playlist-1")
        #expect(loadPlaylistRequest.action == .replace)
        #expect(loadPlaylistRequest.playOnCompletion == true)
        #expect(!recorder.paths.contains("/api/sonos/cloud-queues"))
        #expect(favoritePlayback.model.nowPlaying.title == "Cloud Playlist")
        #expect(favoritePlayback.model.nowPlaying.playbackState == .playing)
        #expect(favoritePlayback.model.manualPlaybackContextPayload == Self.collectionFavoriteItem().playablePayload)
        #expect(favoritePlayback.model.manualQueueContextPayloads == nil)
        #expect(favoritePlayback.model.manualRecentPlaybackContextPayload == nil)
        #expect(favoritePlayback.model.sonosControlAPICloudQueueRuntimeState == .empty)
    }

    private static func makeModel() throws -> (
        model: SonoicModel,
        keychainStore: SonoicKeychainStore,
        networkStubID: String
    ) {
        let keychainStore = SonoicKeychainStore(
            service: "com.markusskov.Sonoic.tests.\(UUID().uuidString)"
        )
        try keychainStore.saveSonosTokenSet(
            SonosOAuthTokenSet(
                accessToken: "access-token",
                refreshToken: nil,
                tokenType: "Bearer",
                scope: nil,
                expiresAt: Date().addingTimeInterval(3_600)
            )
        )

        let userDefaults = try Self.makeUserDefaults()
        let networkStubID = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            SonoicModelSonosControlAPIURLProtocol.testStubHeader: networkStubID
        ]
        configuration.protocolClasses = [SonoicModelSonosControlAPIURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let model = SonoicModel(
            settingsStore: SonoicSettingsStore(userDefaults: userDefaults),
            sonosControlAPIClient: SonosControlAPIClient(
                transport: SonosControlAPITransport(
                    baseURL: try Self.fixtureURL("https://sonos.test/control/api/v1"),
                    urlSession: session
                )
            ),
            sonosOAuthConfiguration: try Self.oauthConfiguration(),
            sonoicCloudQueueClient: SonoicCloudQueueClient(session: session),
            keychainStore: keychainStore,
            startInitialSonosControlAPICloudRefresh: false
        )

        return (model, keychainStore, networkStubID)
    }

    private static func makeUserDefaults() throws -> UserDefaults {
        let suiteName = "SonoicModelSonosControlAPITests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private static func fixtureURL(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    private static func configureCloudCommandTarget(
        on model: SonoicModel,
        snapshot: SonosControlAPICloudSnapshot = Self.cloudSnapshot
    ) {
        model.sonosControlAPIState = SonosControlAPIState(
            settings: SonosControlAPISettings(
                mode: .preferred,
                selectedHouseholdID: "household-1",
                selectedGroupID: "group-1"
            ),
            authorizationStatus: .ready,
            lastErrorDetail: nil,
            lastCommandDescription: nil,
            lastUpdatedAt: nil
        )
        model.sonosControlAPICloudState = SonosControlAPICloudState(status: .verified(snapshot))
        model.activeTarget = SonosActiveTarget(
            id: "group-1",
            name: "Kitchen",
            householdName: "Kitchen",
            kind: .group,
            memberNames: ["Kitchen"]
        )
    }

    private static func stubNetwork(
        for id: String,
        _ responder: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        SonoicModelSonosControlAPIURLProtocol.setResponder(id: id, responder)
    }

    nonisolated private static func httpResponse(
        for request: URLRequest,
        statusCode: Int,
        body: String
    ) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, Data(body.utf8))
    }

    private static func loadFavoriteRequestBody(
        from request: SonoicModelSonosControlAPICapturedRequest
    ) throws -> SonosControlAPILoadFavoriteRequest {
        let body = try #require(request.body)
        return try JSONDecoder().decode(SonosControlAPILoadFavoriteRequest.self, from: body)
    }

    private static func loadPlaylistRequestBody(
        from request: SonoicModelSonosControlAPICapturedRequest
    ) throws -> SonosControlAPILoadPlaylistRequest {
        let body = try #require(request.body)
        return try JSONDecoder().decode(SonosControlAPILoadPlaylistRequest.self, from: body)
    }

    private static func cloudQueueCreateRequestBody(
        from request: SonoicModelSonosControlAPICapturedRequest
    ) throws -> SonoicCloudQueueCreateRequest {
        let body = try #require(request.body)
        return try JSONDecoder().decode(SonoicCloudQueueCreateRequest.self, from: body)
    }

    private static func loadCloudQueueRequestBody(
        from request: SonoicModelSonosControlAPICapturedRequest
    ) throws -> SonosControlAPILoadCloudQueueRequest {
        let body = try #require(request.body)
        return try JSONDecoder().decode(SonosControlAPILoadCloudQueueRequest.self, from: body)
    }

    private static func oauthConfiguration() throws -> SonosOAuthConfiguration {
        SonosOAuthConfiguration(
            clientID: "client-id",
            redirectURI: "https://sonoic.test/callback",
            callbackScheme: "sonoic",
            tokenExchangeURL: try fixtureURL("https://sonoic.test/api/token"),
            tokenRefreshURL: nil,
            authorizationEndpoint: try fixtureURL("https://api.sonos.com/login/v3/oauth"),
            scopes: ["playback-control-all"],
            cloudQueueCreateURL: try fixtureURL("https://sonoic.test/api/sonos/cloud-queues")
        )
    }

    private static var cloudSnapshot: SonosControlAPICloudSnapshot {
        SonosControlAPICloudSnapshot(
            households: [
                SonosControlAPIHousehold(id: "household-1")
            ],
            groupsByHouseholdID: [
                "household-1": SonosControlAPIGroupSnapshot(
                    groups: [
                        SonosControlAPIGroup(
                            id: "group-1",
                            name: "Kitchen",
                            coordinatorId: "player-1",
                            playerIds: ["player-1"]
                        )
                    ],
                    players: [
                        SonosControlAPIPlayer(
                            id: "player-1",
                            name: "Kitchen",
                            roomName: "Kitchen",
                            deviceIds: nil
                        )
                    ]
                )
            ]
        )
    }

    private static func cloudSnapshotWithContent(
        favorites: [SonosControlAPIFavorite] = [],
        playlists: [SonosControlAPIPlaylist] = []
    ) -> SonosControlAPICloudSnapshot {
        SonosControlAPICloudSnapshot(
            households: Self.cloudSnapshot.households,
            groupsByHouseholdID: Self.cloudSnapshot.groupsByHouseholdID,
            favoritesByHouseholdID: ["household-1": favorites],
            playlistsByHouseholdID: ["household-1": playlists]
        )
    }

    private static func cloudFavorite() -> SonosControlAPIFavorite {
        SonosControlAPIFavorite(
            id: "cloud-favorite-1",
            name: "Cloud Favorite",
            description: nil,
            imageUrl: nil,
            service: SonosControlAPIService(id: "204", name: "Apple Music", imageUrl: nil)
        )
    }

    private static func cloudPlaylist() -> SonosControlAPIPlaylist {
        SonosControlAPIPlaylist(
            id: "cloud-playlist-1",
            name: "Cloud Playlist",
            type: nil,
            trackCount: nil
        )
    }

    private static func playlistItem() -> SonoicSourceItem {
        SonoicSourceItem.appleMusicMetadata(
            id: "playlist-1",
            title: "Cloud Queue",
            subtitle: "Sonoic",
            artworkURL: nil,
            kind: .playlist,
            origin: .library,
            catalogID: "playlist-1"
        )
    }

    private static func playlistPlan() -> SonoicSourcePlaylistPlaybackPlan {
        let payload = Self.playbackPayload(id: "queue-track-1")
        let item = SonoicSourceItem(
            id: "queue-track-1",
            title: "Queue Track",
            subtitle: "Sonoic",
            artworkURL: nil,
            artworkIdentifier: nil,
            sourceReference: .appleMusic(
                catalogID: "queue-track-1",
                libraryID: nil,
                kind: .song
            ),
            service: .appleMusic,
            origin: .catalogSearch,
            kind: .song,
            playbackCapability: .sonosNative(payload),
            duration: payload.duration
        )

        return SonoicSourcePlaylistPlaybackPlan(
            payloads: [payload],
            items: [item],
            startingTrackNumber: 1,
            localNowPlayingPayload: payload,
            recentPlaybackPayload: payload
        )
    }

    private static func appleMusicSearchSong() -> SonoicSourceItem {
        SonoicSourceItem.appleMusicMetadata(
            id: "1440857781",
            title: "Sweet Jane",
            subtitle: "Garrett Kato",
            artworkURL: nil,
            kind: .song,
            origin: .catalogSearch,
            catalogID: "1440857781",
            duration: 214
        )
    }

    private static func appleMusicTrackOnlyPlaybackHintSnapshot() -> SonosMusicServiceProbeSnapshot {
        appleMusicServiceSnapshot()
            .includingObservedAccounts(from: [
                SonosMusicServiceObservedValue(
                    value: "x-sonos-http:librarytrack%3aexample.m4p?sid=204&flags=8232&sn=7",
                    origin: .trackURI
                ),
            ])
    }

    private static func appleMusicServiceSnapshot() -> SonosMusicServiceProbeSnapshot {
        SonosMusicServiceProbeSnapshot(
            observedAt: Date(timeIntervalSince1970: 0),
            serviceListVersion: nil,
            services: [
                SonosMusicServiceDescriptor(
                    id: "204",
                    name: "Apple Music",
                    uri: nil,
                    secureURI: nil,
                    containerType: nil,
                    capabilities: nil,
                    authPolicy: nil,
                    presentationMapURI: nil,
                    stringsURI: nil
                ),
            ],
            accounts: []
        )
    }

    private static func favoriteItem() -> SonosFavoriteItem {
        SonosFavoriteItem(
            id: "favorite-1",
            title: "Cloud Favorite",
            subtitle: "Sonoic",
            artworkURL: nil,
            service: .appleMusic,
            playbackURI: "x-sonos-http:favorite-1.m4p",
            playbackMetadataXML: "<DIDL-Lite></DIDL-Lite>",
            kind: .item
        )
    }

    private static func collectionFavoriteItem() -> SonosFavoriteItem {
        SonosFavoriteItem(
            id: "playlist-favorite-1",
            title: "Cloud Playlist",
            subtitle: "Sonoic",
            artworkURL: nil,
            service: .appleMusic,
            playbackURI: "x-rincon-cpcontainer:1006206cplaylist%3acloud-playlist",
            playbackMetadataXML: "<DIDL-Lite></DIDL-Lite>",
            kind: .collection
        )
    }

    private static func playbackPayload(id: String) -> SonosPlayablePayload {
        SonosPlayablePayload(
            id: id,
            title: "Queue Track",
            subtitle: "Sonoic",
            artworkURL: nil,
            service: .appleMusic,
            uri: "x-sonos-http:song:\(id).m4p",
            metadataXML: "<DIDL-Lite></DIDL-Lite>",
            kind: .item,
            launchMode: .direct,
            duration: 180
        )
    }

    private static func track(id: String, name: String) -> SonosControlAPITrack {
        SonosControlAPITrack(
            type: "track",
            name: name,
            mediaUrl: nil,
            imageUrl: nil,
            contentType: "audio/mp4",
            album: nil,
            artist: SonosControlAPIArtist(name: "Sonoic", id: nil),
            id: SonosControlAPIUniversalMusicObjectID(
                serviceId: "204",
                objectId: "song:\(id)",
                accountId: nil
            ),
            service: SonosControlAPIService(id: "204", name: "Apple Music", imageUrl: nil),
            durationMillis: 180_000,
            trackNumber: nil,
            quality: nil
        )
    }

    private static func nowPlayingSnapshot(
        title: String,
        playbackState: SonosNowPlayingSnapshot.PlaybackState
    ) -> SonosNowPlayingSnapshot {
        SonosNowPlayingSnapshot(
            title: title,
            artistName: "Sonoic",
            albumTitle: "Cloud",
            sourceName: "Apple Music",
            playbackState: playbackState,
            elapsedTime: 10,
            duration: 180
        )
    }
}

private final class SonoicModelSonosControlAPIURLProtocol: URLProtocol {
    static let testStubHeader = "X-Sonoic-Control-API-Test-ID"

    private static let responderLock = NSLock()
    nonisolated(unsafe) private static var responders: [
        String: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ] = [:]

    static func setResponder(
        id: String,
        _ responder: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        responderLock.withLock {
            responders[id] = responder
        }
    }

    static func removeResponder(id: String) {
        responderLock.withLock {
            responders[id] = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let responder = Self.responder(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try responder(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func responder(
        for request: URLRequest
    ) -> (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        guard let id = request.value(forHTTPHeaderField: Self.testStubHeader) else {
            return nil
        }

        return responderLock.withLock {
            responders[id]
        }
    }
}

private final class SonoicModelSonosControlAPIRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [SonoicModelSonosControlAPICapturedRequest] = []

    var requests: [SonoicModelSonosControlAPICapturedRequest] {
        lock.withLock {
            recordedRequests
        }
    }

    var paths: [String] {
        lock.withLock {
            recordedRequests.compactMap { $0.url?.path }
        }
    }

    func record(_ request: URLRequest) {
        let capturedRequest = SonoicModelSonosControlAPICapturedRequest(request)
        lock.withLock {
            recordedRequests.append(capturedRequest)
        }
    }
}

private struct SonoicModelSonosControlAPICapturedRequest: Sendable {
    var url: URL?
    var httpMethod: String?
    var body: Data?

    private var headers: [String: String]

    init(_ request: URLRequest) {
        url = request.url
        httpMethod = request.httpMethod
        body = request.httpBody ?? request.httpBodyStream.map(Self.bodyData)
        headers = Dictionary(
            uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { key, value in
                (key.lowercased(), value)
            }
        )
    }

    func value(forHTTPHeaderField field: String) -> String? {
        headers[field.lowercased()]
    }

    private static func bodyData(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            guard bytesRead > 0 else {
                break
            }

            data.append(buffer, count: bytesRead)
        }

        return data.isEmpty ? Data() : data
    }
}
