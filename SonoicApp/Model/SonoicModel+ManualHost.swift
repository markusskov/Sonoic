import Foundation

extension SonoicModel {
    private static let manualHostRefreshInterval: Duration = .seconds(2)
    private static let manualTransportSyncDelay: Duration = .milliseconds(300)
    private static let manualPlayConfirmationRetryDelay: Duration = .milliseconds(300)

    var hasManualSonosHost: Bool {
        !manualSonosHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleManualSonosPlayback() async {
        guard hasManualSonosHost else {
            toggleDebugPlayback()
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

    func refreshManualSonosPlayerState() async {
        guard hasManualSonosHost else {
            manualHostRefreshStatus = .idle
            stopManualHostRefreshLoop()
            return
        }

        let didRefresh = await syncManualSonosState(showProgress: true)

        if didRefresh {
            startManualHostRefreshLoopIfPossible()
        }
    }

    func toggleManualSonosMute() async {
        guard hasManualSonosHost else {
            toggleDebugMute()
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

    func startManualHostRefreshLoopIfPossible() {
        guard isSceneActive, hasManualSonosHost else {
            stopManualHostRefreshLoop()
            return
        }

        stopManualHostRefreshLoop()

        manualHostRefreshTask = Task {
            await pollManualSonosPlayerState()
        }
    }

    func stopManualHostRefreshLoop() {
        manualHostRefreshTask?.cancel()
        manualHostRefreshTask = nil
        manualHostDeferredSyncTask?.cancel()
        manualHostDeferredSyncTask = nil
        manualPlayConfirmationRetryTask?.cancel()
        manualPlayConfirmationRetryTask = nil
    }

    private func pollManualSonosPlayerState() async {
        _ = await syncManualSonosState(showProgress: false)

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.manualHostRefreshInterval)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            _ = await syncManualSonosState(showProgress: false)
        }
    }

    func syncManualSonosState(showProgress: Bool) async -> Bool {
        if showProgress {
            manualHostRefreshStatus = .refreshing
        }

        do {
            let wasAwaitingConfirmation = isManualPlayTransitionAwaitingConfirmation
            async let refreshedVolume = renderingControlClient.fetchVolume(host: manualSonosHost)
            async let refreshedPlaybackState = avTransportClient.fetchPlaybackState(host: manualSonosHost)
            let rawPlaybackState = try await refreshedPlaybackState
            let playbackState = resolvedPlaybackState(rawPlaybackState)
            async let refreshedNowPlaying = nowPlayingClient.fetchSnapshot(
                host: manualSonosHost,
                playbackState: playbackState,
                fallback: nowPlaying
            )
            let volume = try await refreshedVolume
            var nextNowPlaying = await refreshedNowPlaying
            confirmManualPlayTransitionIfNeeded(
                rawPlaybackState: rawPlaybackState,
                incomingElapsedTime: nextNowPlaying.elapsedTime
            )
            nextNowPlaying = smoothedNowPlayingSnapshot(nextNowPlaying)
            nextNowPlaying.artworkIdentifier = try? await syncArtworkIdentifier(for: nextNowPlaying)

            if externalVolume != volume {
                externalVolume = volume
            }

            if nowPlaying != nextNowPlaying {
                nowPlaying = nextNowPlaying
            }

            await refreshManualHostIdentityIfNeeded()
            await refreshManualHostTopologyIfNeeded()

            if wasAwaitingConfirmation != isManualPlayTransitionAwaitingConfirmation,
               nowPlaying == nextNowPlaying
            {
                persistSharedExternalControlState()
            }

            scheduleManualPlayConfirmationRetryIfNeeded(for: rawPlaybackState)

            manualHostRefreshStatus = .updated(.now)
            return true
        } catch {
            manualPlayTransitionGraceDeadline = nil
            setManualPlayTransitionAwaitingConfirmation(false)
            manualHostRefreshStatus = .failed(error.localizedDescription)
            return false
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

    private func syncArtworkIdentifier(for snapshot: SonosNowPlayingSnapshot) async throws -> String? {
        let artworkStore = try SonoicSharedArtworkStore()
        return try await artworkStore.syncArtwork(
            from: snapshot.artworkURL,
            host: manualSonosHost,
            preferredIdentifier: "\(activeTarget.id)-now-playing-artwork"
        )
    }

    private func markLocalPlaybackState(_ playbackState: SonosNowPlayingSnapshot.PlaybackState) {
        guard nowPlaying.playbackState != playbackState else {
            return
        }

        var nextNowPlaying = nowPlaying
        nextNowPlaying.playbackState = playbackState
        nowPlaying = nextNowPlaying
    }

    private func freezeLocalPlaybackTimeIfNeeded() {
        guard nowPlaying.playbackState == .playing,
              let elapsedTime = nowPlaying.elapsedTime
        else {
            return
        }

        let advancedElapsedTime = elapsedTime + max(nowPlayingObservedAt.timeIntervalSinceNow * -1, 0)
        var nextNowPlaying = nowPlaying

        if let duration = nowPlaying.duration {
            nextNowPlaying.elapsedTime = min(advancedElapsedTime, duration)
        } else {
            nextNowPlaying.elapsedTime = advancedElapsedTime
        }

        nowPlaying = nextNowPlaying
    }

    private func beginManualPlayTransitionGrace() {
        manualPlayTransitionGraceDeadline = Date().addingTimeInterval(Self.manualPlayTransitionGraceInterval)
        setManualPlayTransitionAwaitingConfirmation(true)
    }

    private func setManualPlayTransitionAwaitingConfirmation(_ isAwaitingConfirmation: Bool) {
        guard isManualPlayTransitionAwaitingConfirmation != isAwaitingConfirmation else {
            return
        }

        isManualPlayTransitionAwaitingConfirmation = isAwaitingConfirmation
        if !isAwaitingConfirmation {
            manualPlayConfirmationRetryTask?.cancel()
            manualPlayConfirmationRetryTask = nil
        }

        // The native now-playing session depends on this flag even when the snapshot itself
        // has not changed, so push an explicit refresh for those transitions.
        persistSharedExternalControlState()
    }

    private func resolvedPlaybackState(_ playbackState: SonosNowPlayingSnapshot.PlaybackState) -> SonosNowPlayingSnapshot.PlaybackState {
        switch playbackState {
        case .playing:
            manualPlayTransitionGraceDeadline = nil
            setManualPlayTransitionAwaitingConfirmation(false)
            return .playing
        case .paused:
            manualPlayTransitionGraceDeadline = nil
            setManualPlayTransitionAwaitingConfirmation(false)
            return .paused
        case .buffering:
            guard let manualPlayTransitionGraceDeadline,
                  manualPlayTransitionGraceDeadline > .now
            else {
                setManualPlayTransitionAwaitingConfirmation(false)
                return .buffering
            }

            return .playing
        }
    }

    private func scheduleManualPlayConfirmationRetryIfNeeded(for rawPlaybackState: SonosNowPlayingSnapshot.PlaybackState) {
        guard rawPlaybackState == .buffering,
              isManualPlayTransitionAwaitingConfirmation,
              let manualPlayTransitionGraceDeadline,
              manualPlayTransitionGraceDeadline > .now
        else {
            return
        }

        manualPlayConfirmationRetryTask?.cancel()
        manualPlayConfirmationRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.manualPlayConfirmationRetryDelay)
            } catch {
                return
            }

            guard let self else {
                return
            }

            _ = await self.syncManualSonosState(showProgress: false)
        }
    }

    private func confirmManualPlayTransitionIfNeeded(
        rawPlaybackState: SonosNowPlayingSnapshot.PlaybackState,
        incomingElapsedTime: TimeInterval?
    ) {
        guard isManualPlayTransitionAwaitingConfirmation else {
            return
        }

        guard rawPlaybackState == .buffering,
              let manualPlayTransitionGraceDeadline,
              manualPlayTransitionGraceDeadline > .now
        else {
            return
        }

        self.manualPlayTransitionGraceDeadline = nil
        setManualPlayTransitionAwaitingConfirmation(false)
    }

    private func smoothedNowPlayingSnapshot(_ snapshot: SonosNowPlayingSnapshot) -> SonosNowPlayingSnapshot {
        guard snapshot.playbackState == .playing || snapshot.playbackState == .paused,
              snapshot.title == nowPlaying.title,
              snapshot.artistName == nowPlaying.artistName,
              snapshot.albumTitle == nowPlaying.albumTitle,
              let incomingElapsedTime = snapshot.elapsedTime,
              let localElapsedTime = effectiveLocalElapsedTime()
        else {
            return snapshot
        }

        let delta = localElapsedTime - incomingElapsedTime
        let shouldSmooth: Bool

        switch snapshot.playbackState {
        case .playing:
            shouldSmooth = delta > 0 && delta <= 1.25
        case .paused:
            shouldSmooth = abs(delta) <= 1.25
        case .buffering:
            shouldSmooth = false
        }

        guard shouldSmooth else {
            return snapshot
        }

        var smoothedSnapshot = snapshot
        if let duration = snapshot.duration {
            smoothedSnapshot.elapsedTime = min(localElapsedTime, duration)
        } else {
            smoothedSnapshot.elapsedTime = localElapsedTime
        }

        return smoothedSnapshot
    }

    private func effectiveLocalElapsedTime(referenceDate: Date = .now) -> TimeInterval? {
        guard let elapsedTime = nowPlaying.elapsedTime else {
            return nil
        }

        guard nowPlaying.playbackState == .playing else {
            return elapsedTime
        }

        if let duration = nowPlaying.duration {
            return min(elapsedTime + max(referenceDate.timeIntervalSince(nowPlayingObservedAt), 0), duration)
        }

        return elapsedTime + max(referenceDate.timeIntervalSince(nowPlayingObservedAt), 0)
    }

    private func scheduleManualStateSync(after delay: Duration, restartRefreshLoop: Bool = false) {
        manualHostDeferredSyncTask?.cancel()
        manualHostDeferredSyncTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard let self else {
                return
            }

            _ = await self.syncManualSonosState(showProgress: false)

            if restartRefreshLoop {
                self.startManualHostRefreshLoopIfPossible()
            }
        }
    }
}
