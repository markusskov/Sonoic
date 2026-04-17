import Foundation

extension SonoicModel {
    private static let manualTransportSyncDelay: Duration = .milliseconds(300)

    func toggleManualSonosPlayback() async {
        guard hasManualSonosHost else {
            return
        }

        switch nowPlaying.playbackState {
        case .playing:
            _ = await pauseManualSonosPlayback()
        case .paused, .buffering:
            _ = await playManualSonosPlayback()
        }
    }

    func playManualSonosPlayback() async -> Bool {
        beginManualPlayTransitionGrace()
        markLocalPlaybackState(.playing)
        return await performManualTransportCommand(syncDelay: Self.manualTransportSyncDelay) {
            try await avTransportClient.play(host: manualSonosHost)
        }
    }

    func pauseManualSonosPlayback() async -> Bool {
        manualPlayTransitionGraceDeadline = nil
        setManualPlayTransitionAwaitingConfirmation(false)
        freezeLocalPlaybackTimeIfNeeded()
        markLocalPlaybackState(.paused)
        return await performManualTransportCommand(syncDelay: Self.manualTransportSyncDelay) {
            try await avTransportClient.pause(host: manualSonosHost)
        }
    }

    func skipToNextManualSonosTrack() async -> Bool {
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }

        return await performManualTransportCommand(syncDelay: Self.manualTransportSyncDelay) {
            try await avTransportClient.next(host: manualSonosHost)
        }
    }

    func skipToPreviousManualSonosTrack() async -> Bool {
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }

        return await performManualTransportCommand(syncDelay: Self.manualTransportSyncDelay) {
            try await avTransportClient.previous(host: manualSonosHost)
        }
    }

    func seekManualSonosPlayback(to timeInterval: TimeInterval) async -> Bool {
        await performManualTransportCommand {
            try await avTransportClient.seek(host: manualSonosHost, timeInterval: timeInterval)
        }
    }

    func toggleManualSonosMute() async {
        guard hasManualSonosHost else {
            return
        }

        let desiredMute = !externalVolume.isMuted
        manualHostRefreshStatus = .refreshing

        do {
            try await renderingControlClient.setMute(host: manualSonosHost, isMuted: desiredMute)
            externalVolume.isMuted = desiredMute
            manualHostRefreshStatus = .updated(.now)
            startManualHostRefreshLoopIfPossible()
        } catch {
            manualHostRefreshStatus = .failed(error.localizedDescription)
        }
    }

    private func performManualTransportCommand(
        syncDelay: Duration? = nil,
        _ action: () async throws -> Void
    ) async -> Bool {
        guard hasManualSonosHost else {
            return false
        }

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
            if let syncDelay {
                scheduleManualStateSync(after: syncDelay, restartRefreshLoop: true)
                manualHostRefreshStatus = .updated(.now)
            } else {
                _ = await syncManualSonosState(showProgress: false)
                startManualHostRefreshLoopIfPossible()
            }
            return true
        } catch {
            manualPlayTransitionGraceDeadline = nil
            setManualPlayTransitionAwaitingConfirmation(false)
            startManualHostRefreshLoopIfPossible()
            manualHostRefreshStatus = .failed(error.localizedDescription)
            return false
        }
    }
}
