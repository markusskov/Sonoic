import Foundation

extension SonoicModel {
    private static let manualPlayConfirmationRetryDelay: Duration = .milliseconds(300)

    func markLocalPlaybackState(_ playbackState: SonosNowPlayingSnapshot.PlaybackState) {
        guard nowPlaying.playbackState != playbackState else {
            return
        }

        var nextNowPlaying = nowPlaying
        nextNowPlaying.playbackState = playbackState
        nowPlaying = nextNowPlaying
    }

    func markLocalNowPlaying(from payload: SonosPlayablePayload) {
        let subtitleParts = payload.subtitle?
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        nowPlaying = SonosNowPlayingSnapshot(
            title: payload.title,
            artistName: subtitleParts.first,
            albumTitle: subtitleParts.dropFirst().first,
            sourceName: payload.service?.name ?? nowPlaying.sourceName,
            playbackState: .playing,
            artworkURL: payload.artworkURL,
            artworkIdentifier: nil,
            elapsedTime: 0,
            duration: payload.duration,
            transportActions: nowPlaying.transportActions
        )
    }

    func freezeLocalPlaybackTimeIfNeeded() {
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

    func beginManualPlayTransitionGrace() {
        manualPlayTransitionGraceDeadline = Date().addingTimeInterval(Self.manualPlayTransitionGraceInterval)
        setManualPlayTransitionAwaitingConfirmation(true)
    }

    func setManualPlayTransitionAwaitingConfirmation(_ isAwaitingConfirmation: Bool) {
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

    func resolvedPlaybackState(_ playbackState: SonosNowPlayingSnapshot.PlaybackState) -> SonosNowPlayingSnapshot.PlaybackState {
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

    func scheduleManualPlayConfirmationRetryIfNeeded(for rawPlaybackState: SonosNowPlayingSnapshot.PlaybackState) {
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

    func smoothedNowPlayingSnapshot(_ snapshot: SonosNowPlayingSnapshot) -> SonosNowPlayingSnapshot {
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

    func effectiveLocalElapsedTime(referenceDate: Date = .now) -> TimeInterval? {
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

    func scheduleManualStateSync(
        after delay: Duration,
        restartRefreshLoop: Bool = false,
        refreshQueueAfterSync: Bool = false
    ) {
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

            if refreshQueueAfterSync {
                await self.refreshQueueAfterPlaybackChangeIfNeeded()
            }

            if restartRefreshLoop {
                self.startManualHostRefreshLoopIfPossible()
            }
        }
    }
}
