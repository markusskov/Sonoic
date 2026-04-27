import Foundation

extension SonoicModel {
    private static let manualHostRefreshInterval: Duration = .seconds(2)

    var hasManualSonosHost: Bool {
        manualSonosHost.sonoicNonEmptyTrimmed != nil
    }

    func refreshManualSonosPlayerState(forceRoomRefresh: Bool = true) async {
        guard hasManualSonosHost else {
            manualHostRefreshStatus = .idle
            stopManualHostRefreshLoop()
            return
        }

        let didRefresh = await syncManualSonosState(
            showProgress: true,
            forceRoomRefresh: forceRoomRefresh
        )

        if didRefresh {
            startManualHostRefreshLoopIfPossible()
        }
    }

    func startManualHostRefreshLoopIfPossible() {
        guard shouldRunManualHostRefreshLoop else {
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

    private var shouldRunManualHostRefreshLoop: Bool {
        guard hasManualSonosHost else {
            return false
        }

        return isSceneActive
            || isManualPlayTransitionAwaitingConfirmation
            || nowPlaying.playbackState == .playing
            || nowPlaying.playbackState == .buffering
    }

    func syncManualSonosState(showProgress: Bool, forceRoomRefresh: Bool = false) async -> Bool {
        if showProgress {
            manualHostRefreshStatus = .refreshing
        }

        do {
            let wasAwaitingConfirmation = isManualPlayTransitionAwaitingConfirmation
            async let refreshedVolume = fetchExternalVolumeForActiveTarget()
            async let refreshedPlaybackState = avTransportClient.fetchPlaybackState(host: manualSonosHost)
            async let refreshedTransportActions = fetchManualTransportActions()
            let rawPlaybackState = try await refreshedPlaybackState
            let playbackState = resolvedPlaybackState(rawPlaybackState)
            async let refreshedNowPlaying = nowPlayingClient.fetchSnapshot(
                host: manualSonosHost,
                playbackState: playbackState,
                fallback: nowPlaying
            )
            let volume = try await refreshedVolume
            let nowPlayingResult = await refreshedNowPlaying
            var nextNowPlaying = nowPlayingResult.snapshot
            nextNowPlaying = snapshotPreservingManualPlaybackContext(
                nextNowPlaying,
                diagnostics: nowPlayingResult.diagnostics
            )
            nextNowPlaying = smoothedNowPlayingSnapshot(nextNowPlaying)
            nextNowPlaying.artworkIdentifier = try? await syncArtworkIdentifier(for: nextNowPlaying)
            nextNowPlaying.transportActions = await refreshedTransportActions ?? nowPlaying.transportActions

            if externalVolume != volume {
                externalVolume = volume
            }

            if nowPlaying != nextNowPlaying {
                nowPlaying = nextNowPlaying
            }

            if nowPlayingDiagnostics != nowPlayingResult.diagnostics {
                nowPlayingDiagnostics = nowPlayingResult.diagnostics
            }

            await refreshManualHostIdentityIfNeeded(force: forceRoomRefresh)
            await refreshManualHostTopologyIfNeeded(force: forceRoomRefresh)

            if wasAwaitingConfirmation != isManualPlayTransitionAwaitingConfirmation,
               nowPlaying == nextNowPlaying
            {
                persistSharedExternalControlState()
            }

            scheduleManualPlayConfirmationRetryIfNeeded(for: rawPlaybackState)

            let refreshedAt = Date()
            manualHostLastSuccessfulRefreshAt = refreshedAt
            manualHostRefreshStatus = .updated(refreshedAt)
            return true
        } catch {
            manualPlayTransitionGraceDeadline = nil
            setManualPlayTransitionAwaitingConfirmation(false)
            if !manualHostIdentityStatus.isResolved {
                manualHostIdentityStatus = .failed(error.localizedDescription)
            }
            if !manualHostTopologyStatus.isResolved {
                manualHostTopologyStatus = .failed(error.localizedDescription)
            }
            manualHostRefreshStatus = .failed(error.localizedDescription)
            return false
        }
    }

    private func fetchManualTransportActions() async -> SonosTransportActions? {
        try? await avTransportClient.fetchCurrentTransportActions(host: manualSonosHost)
    }

    private func syncArtworkIdentifier(for snapshot: SonosNowPlayingSnapshot) async throws -> String? {
        let normalizedIncomingArtworkURL = snapshot.artworkURL.sonoicNonEmptyTrimmed
        let normalizedCurrentArtworkURL = nowPlaying.artworkURL.sonoicNonEmptyTrimmed

        if normalizedIncomingArtworkURL == normalizedCurrentArtworkURL {
            if normalizedIncomingArtworkURL == nil {
                return nil
            }

            if let artworkIdentifier = snapshot.artworkIdentifier {
                return artworkIdentifier
            }
        }

        let artworkURL = snapshot.artworkURL
        let host = manualSonosHost
        let preferredIdentifier = "\(activeTarget.id)-now-playing-artwork"

        return try await Task.detached(priority: .utility) {
            let artworkStore = try SonoicSharedArtworkStore()
            return try await artworkStore.syncArtwork(
                from: artworkURL,
                host: host,
                preferredIdentifier: preferredIdentifier
            )
        }.value
    }

}
