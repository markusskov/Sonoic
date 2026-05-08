import Foundation

extension SonoicModel {
    private static let sonosControlAPITransportSyncDelay: Duration = .milliseconds(350)
    private static let sonosControlAPISeekSyncDelay: Duration = .milliseconds(750)

    private struct SonosControlAPICommandContext {
        var groupID: String
        var accessToken: String
    }

    func updateSonosControlAPISettings(_ settings: SonosControlAPISettings) {
        settingsStore.saveSonosControlAPISettings(settings)
        sonosControlAPIState.settings = settings
        sonosControlAPIState.lastUpdatedAt = .now
    }

    func markSonosControlAPIAuthorizationReady() {
        sonosControlAPIState.authorizationStatus = .ready
        sonosControlAPIState.lastErrorDetail = nil
        sonosControlAPIState.lastUpdatedAt = .now
    }

    func markSonosControlAPIAuthorizationUnavailable(_ detail: String? = nil) {
        sonosControlAPIState.authorizationStatus = .notConfigured
        sonosControlAPIState.lastErrorDetail = detail
        sonosControlAPIState.lastUpdatedAt = .now
    }

    func activeSonosControlAPIGroupID() -> String? {
        guard sonosControlAPIState.canSendCommands else {
            return nil
        }

        return activeSonosControlAPICommandTarget()?.groupID
            ?? sonosControlAPIState.settings.selectedGroupID?.sonoicNonEmptyTrimmed
    }

    func applyVerifiedSonosControlAPICloudSnapshot(_ snapshot: SonosControlAPICloudSnapshot) {
        markSonosControlAPIAuthorizationReady()

        var settings = sonosControlAPIState.settings
        var didChangeSettings = false

        if settings.mode == .off {
            settings.mode = .fallback
            didChangeSettings = true
        }

        if didChangeSettings {
            updateSonosControlAPISettings(settings)
        }
    }

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
        guard let context = sonosControlAPICommandContext() else {
            return false
        }

        let previousNowPlaying = nowPlaying
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
        }

        return didPlay
    }

    func pauseSonosControlAPIPlaybackIfAvailable() async -> Bool {
        guard let context = sonosControlAPICommandContext() else {
            return false
        }

        let previousNowPlaying = nowPlaying
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
        }

        return didPause
    }

    func skipToNextSonosControlAPITrackIfAvailable() async -> Bool {
        guard let context = sonosControlAPICommandContext() else {
            return false
        }

        manualPlaybackContextPayload = nil
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }

        return await performSonosControlAPITransportCommand(
            description: "Cloud next",
            refreshQueueAfterSuccess: true
        ) {
            try await sonosControlAPIClient.skipToNextTrack(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }
    }

    func skipToPreviousSonosControlAPITrackIfAvailable() async -> Bool {
        guard let context = sonosControlAPICommandContext() else {
            return false
        }

        manualPlaybackContextPayload = nil
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }

        return await performSonosControlAPITransportCommand(
            description: "Cloud previous",
            refreshQueueAfterSuccess: true
        ) {
            try await sonosControlAPIClient.skipToPreviousTrack(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }
    }

    func seekSonosControlAPIPlaybackIfAvailable(to timeInterval: TimeInterval) async -> Bool {
        guard let context = sonosControlAPICommandContext() else {
            return false
        }

        let previousNowPlaying = nowPlaying
        let previousObservedAt = nowPlayingObservedAt
        let boundedElapsedTime = markLocalSeek(to: timeInterval)
        beginManualSeekConfirmation(to: boundedElapsedTime)
        recordSeekDiagnostics(
            status: .pending,
            host: "Sonos Control API",
            target: boundedElapsedTime,
            observed: nil,
            errorDetail: nil
        )

        do {
            let status = try await sonosControlAPIClient.playbackStatus(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
            try await sonosControlAPIClient.seek(
                groupID: context.groupID,
                positionMillis: Int((boundedElapsedTime * 1_000).rounded()),
                itemID: status.itemId,
                accessToken: context.accessToken
            )
            recordSonosControlAPICommand("Cloud seek")
            try await Task.sleep(for: Self.sonosControlAPISeekSyncDelay)
            let observed = try? await sonosControlAPIClient.playbackStatus(
                groupID: context.groupID,
                accessToken: context.accessToken
            ).positionMillis.map { TimeInterval($0) / 1_000 }
            recordSeekDiagnostics(
                status: .succeeded,
                host: "Sonos Control API",
                target: boundedElapsedTime,
                observed: observed,
                errorDetail: nil
            )
            scheduleManualStateSync(
                after: .milliseconds(100),
                restartRefreshLoop: true,
                refreshQueueAfterSync: false
            )
            return true
        } catch {
            recordSonosControlAPIError(error)
            recordSeekDiagnostics(
                status: .failed,
                host: "Sonos Control API",
                target: boundedElapsedTime,
                observed: nil,
                errorDetail: error.localizedDescription
            )
            clearManualSeekConfirmation()
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousObservedAt
            if isSonosControlAPIAuthorizationFailure(error) {
                sonosControlAPIState.authorizationStatus = .expired
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
            }
            return false
        }
    }

    private func sonosControlAPICommandContext() -> SonosControlAPICommandContext? {
        guard let groupID = activeSonosControlAPIGroupID() else {
            return nil
        }

        do {
            guard let tokenSet = try keychainStore.loadSonosTokenSet() else {
                sonosControlAPIAuthorizationState = .disconnected
                markSonosControlAPIAuthorizationUnavailable()
                return nil
            }

            guard !tokenSet.isExpired() else {
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
                sonosControlAPIState.authorizationStatus = .expired
                return nil
            }

            markSonosControlAPIAuthorizationReady()
            return SonosControlAPICommandContext(
                groupID: groupID,
                accessToken: tokenSet.accessToken
            )
        } catch {
            recordSonosControlAPIError(error)
            return nil
        }
    }

    private func activeSonosControlAPICommandTarget() -> SonosControlAPITargetIdentity? {
        guard case let .verified(snapshot) = sonosControlAPICloudState.status else {
            return nil
        }

        return snapshot.preferredCommandTarget(
            settings: sonosControlAPIState.settings,
            activeTargetID: activeTarget.id
        )
    }

    private func performSonosControlAPITransportCommand(
        description: String,
        refreshQueueAfterSuccess: Bool,
        _ action: () async throws -> Void
    ) async -> Bool {
        guard !isManualTransportCommandInFlight else {
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
                after: Self.sonosControlAPITransportSyncDelay,
                restartRefreshLoop: true,
                refreshQueueAfterSync: refreshQueueAfterSuccess
            )
            return true
        } catch {
            manualPlayTransitionGraceDeadline = nil
            setManualPlayTransitionAwaitingConfirmation(false)
            clearManualSeekConfirmation()
            recordSonosControlAPIError(error)
            if isSonosControlAPIAuthorizationFailure(error) {
                sonosControlAPIState.authorizationStatus = .expired
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
            }
            manualHostRefreshStatus = .failed(error.localizedDescription)
            startManualHostRefreshLoopIfPossible()
            return false
        }
    }

    private func isSonosControlAPIAuthorizationFailure(_ error: Error) -> Bool {
        guard let transportError = error as? SonosControlAPITransport.TransportError else {
            return false
        }

        return transportError.isAuthorizationFailure
    }
}
