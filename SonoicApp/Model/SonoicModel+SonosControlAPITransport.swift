import Foundation

extension SonoicModel {
    private static let sonosControlAPITransportSyncDelay: Duration = .milliseconds(350)

    func recordSonosControlAPICommand(_ description: String) {
        sonosControlAPIState.lastCommandDescription = description
        sonosControlAPIState.lastErrorDetail = nil
        sonosControlAPIState.lastUpdatedAt = .now
    }

    func recordSonosControlAPIError(_ error: Error) {
        sonosControlAPIState.lastErrorDetail = error.localizedDescription
        sonosControlAPIState.lastUpdatedAt = .now
    }

    func playSonosControlAPIPlaybackIfAvailable() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudPlay") else {
            return false
        }

        let previousNowPlaying = nowPlaying
        let previousNowPlayingObservedAt = nowPlayingObservedAt
        beginManualPlayTransitionGrace()
        markLocalPlaybackState(.playing)

        let didPlay = await performSonosControlAPITransportCommand(
            description: "Cloud play",
            refreshQueueAfterSuccess: false
        ) {
            try await sonosControlAPIClient.play(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }

        if !didPlay {
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousNowPlayingObservedAt
            persistSharedExternalControlState()
        }

        return didPlay
    }

    func pauseSonosControlAPIPlaybackIfAvailable() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudPause") else {
            return false
        }

        let previousNowPlaying = nowPlaying
        let previousNowPlayingObservedAt = nowPlayingObservedAt
        manualPlayTransitionGraceDeadline = nil
        setManualPlayTransitionAwaitingConfirmation(false)
        freezeLocalPlaybackTimeIfNeeded()
        markLocalPlaybackState(.paused)

        let didPause = await performSonosControlAPITransportCommand(
            description: "Cloud pause",
            refreshQueueAfterSuccess: false
        ) {
            try await sonosControlAPIClient.pause(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }

        if !didPause {
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousNowPlayingObservedAt
            persistSharedExternalControlState()
        }

        return didPause
    }

    func skipToNextSonosControlAPITrackIfAvailable() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudNext") else {
            return false
        }

        let previousNowPlaying = nowPlaying
        let previousNowPlayingObservedAt = nowPlayingObservedAt
        let previousPlaybackContextPayload = manualPlaybackContextPayload
        manualPlaybackContextPayload = nil
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }

        let didSkip = await performSonosControlAPITransportCommand(
            description: "Cloud next",
            refreshQueueAfterSuccess: true
        ) {
            try await sonosControlAPIClient.skipToNextTrack(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }

        if !didSkip {
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousNowPlayingObservedAt
            if sonosControlAPIState.authorizationStatus != .expired {
                manualPlaybackContextPayload = previousPlaybackContextPayload
            }
            persistSharedExternalControlState()
        }

        return didSkip
    }

    func skipToPreviousSonosControlAPITrackIfAvailable() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudPrevious") else {
            return false
        }

        let previousNowPlaying = nowPlaying
        let previousNowPlayingObservedAt = nowPlayingObservedAt
        let previousPlaybackContextPayload = manualPlaybackContextPayload
        manualPlaybackContextPayload = nil
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }

        let didSkip = await performSonosControlAPITransportCommand(
            description: "Cloud previous",
            refreshQueueAfterSuccess: true
        ) {
            try await sonosControlAPIClient.skipToPreviousTrack(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }

        if !didSkip {
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousNowPlayingObservedAt
            if sonosControlAPIState.authorizationStatus != .expired {
                manualPlaybackContextPayload = previousPlaybackContextPayload
            }
            persistSharedExternalControlState()
        }

        return didSkip
    }

    func performSonosControlAPITransportCommand(
        description: String,
        refreshQueueAfterSuccess: Bool,
        syncDelay: Duration? = nil,
        _ action: () async throws -> Void
    ) async -> Bool {
        guard !isManualTransportCommandInFlight else {
            sonoicPlaybackDebugLog("cloudCommand skipped description='\(description)' reason=inFlight")
            return false
        }

        manualHostRefreshTask?.cancel()
        manualHostRefreshTask = nil
        manualHostDeferredSyncTask?.cancel()
        manualHostDeferredSyncTask = nil
        manualPlayConfirmationRetryTask?.cancel()
        manualPlayConfirmationRetryTask = nil
        isManualTransportCommandInFlight = true
        manualHostRefreshStatus = .refreshing
        defer {
            isManualTransportCommandInFlight = false
        }

        do {
            try await action()
            recordSonosControlAPICommand(description)
            scheduleManualStateSync(
                after: syncDelay ?? Self.sonosControlAPITransportSyncDelay,
                restartRefreshLoop: true,
                refreshQueueAfterSync: refreshQueueAfterSuccess
            )
            return true
        } catch {
            manualPlayTransitionGraceDeadline = nil
            setManualPlayTransitionAwaitingConfirmation(false)
            clearManualSeekConfirmation()
            recordSonosControlAPIError(error)
            sonoicPlaybackDebugLog(
                "cloudCommand failed description='\(description)' error='\(error.localizedDescription)'"
            )
            if isSonosControlAPIAuthorizationFailure(error) {
                sonosControlAPIState.authorizationStatus = .expired
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
                clearSonosControlAPIPlaybackContextAfterAuthorizationLoss()
            }
            manualHostRefreshStatus = .failed(error.localizedDescription)
            startManualHostRefreshLoopIfPossible()
            return false
        }
    }

    func isSonosControlAPIAuthorizationFailure(_ error: Error) -> Bool {
        if let transportError = error as? SonosControlAPITransport.TransportError {
            return transportError.isAuthorizationFailure
        }

        if let cloudQueueError = error as? SonoicCloudQueueClient.ClientError {
            return cloudQueueError.isAuthorizationFailure
        }

        return false
    }
}
