import Foundation

extension SonoicModel {
    private static let manualHostRefreshInterval: Duration = .seconds(2)

    var hasManualSonosHost: Bool {
        !manualSonosHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    func syncManualSonosState(showProgress: Bool, forceRoomRefresh: Bool = false) async -> Bool {
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
                rawPlaybackState: rawPlaybackState
            )
            nextNowPlaying = smoothedNowPlayingSnapshot(nextNowPlaying)
            nextNowPlaying.artworkIdentifier = try? await syncArtworkIdentifier(for: nextNowPlaying)

            if externalVolume != volume {
                externalVolume = volume
            }

            if nowPlaying != nextNowPlaying {
                nowPlaying = nextNowPlaying
            }

            await refreshManualHostIdentityIfNeeded(force: forceRoomRefresh)
            await refreshManualHostTopologyIfNeeded(force: forceRoomRefresh)

            if wasAwaitingConfirmation != isManualPlayTransitionAwaitingConfirmation,
               nowPlaying == nextNowPlaying
            {
                persistSharedExternalControlState()
            }

            scheduleManualPlayConfirmationRetryIfNeeded(for: rawPlaybackState)

            manualHostLastSuccessfulRefreshAt = .now
            manualHostRefreshStatus = .updated(.now)
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

    private func syncArtworkIdentifier(for snapshot: SonosNowPlayingSnapshot) async throws -> String? {
        let normalizedIncomingArtworkURL = snapshot.artworkURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrentArtworkURL = nowPlaying.artworkURL?.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedIncomingArtworkURL == normalizedCurrentArtworkURL {
            if normalizedIncomingArtworkURL == nil {
                return nil
            }

            if let artworkIdentifier = snapshot.artworkIdentifier {
                return artworkIdentifier
            }
        }

        let artworkStore = try SonoicSharedArtworkStore()
        return try await artworkStore.syncArtwork(
            from: snapshot.artworkURL,
            host: manualSonosHost,
            preferredIdentifier: "\(activeTarget.id)-now-playing-artwork"
        )
    }
}
