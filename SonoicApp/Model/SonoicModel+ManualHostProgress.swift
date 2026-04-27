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
        let subtitleParts = manualPlaybackSubtitleParts(for: payload)

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

    func markLocalSeek(to timeInterval: TimeInterval) {
        var nextNowPlaying = nowPlaying
        let boundedElapsedTime: TimeInterval

        if let duration = nowPlaying.duration {
            boundedElapsedTime = min(max(timeInterval, 0), duration)
        } else {
            boundedElapsedTime = max(timeInterval, 0)
        }

        nextNowPlaying.elapsedTime = boundedElapsedTime
        nowPlaying = nextNowPlaying
        nowPlayingObservedAt = .now
        persistSharedExternalControlState()
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

    func snapshotPreservingManualPlaybackContext(
        _ snapshot: SonosNowPlayingSnapshot,
        diagnostics: SonosNowPlayingDiagnostics
    ) -> SonosNowPlayingSnapshot {
        guard let payload = manualPlaybackContextPayload(for: snapshot, diagnostics: diagnostics) else {
            return snapshot
        }

        let subtitleParts = manualPlaybackSubtitleParts(for: payload)
        var preservedSnapshot = snapshot

        if shouldPreserveManualPlaybackTitle(in: preservedSnapshot, diagnostics: diagnostics, payload: payload) {
            preservedSnapshot.title = payload.title
        }

        if preservedSnapshot.artistName.sonoicNonEmptyTrimmed == nil {
            preservedSnapshot.artistName = subtitleParts.first
        }

        if preservedSnapshot.albumTitle.sonoicNonEmptyTrimmed == nil {
            preservedSnapshot.albumTitle = subtitleParts.dropFirst().first
        }

        if preservedSnapshot.sourceName.sonoicNonEmptyTrimmed == nil,
           let sourceName = payload.service?.name.sonoicNonEmptyTrimmed
        {
            preservedSnapshot.sourceName = sourceName
        }

        if preservedSnapshot.artworkURL.sonoicNonEmptyTrimmed == nil {
            preservedSnapshot.artworkURL = payload.artworkURL
        }

        if preservedSnapshot.duration == nil || (preservedSnapshot.duration ?? 0) <= 0 {
            preservedSnapshot.duration = payload.duration
        }

        if preservedSnapshot.elapsedTime == nil {
            preservedSnapshot.elapsedTime = effectiveLocalElapsedTime() ?? 0
        }

        return preservedSnapshot
    }

    private func manualPlaybackContextPayload(
        for snapshot: SonosNowPlayingSnapshot,
        diagnostics: SonosNowPlayingDiagnostics
    ) -> SonosPlayablePayload? {
        if let payload = manualPlaybackContextPayload,
           manualPlaybackContextMatches(snapshot, diagnostics: diagnostics, payload: payload)
        {
            return payload
        }

        if let payload = manualQueueContextPayload(matching: diagnostics) {
            manualPlaybackContextPayload = payload
            return payload
        }

        if let payload = manualPlaybackContextPayload {
            clearManualPlaybackContextIfContentChanged(snapshot, diagnostics: diagnostics, payload: payload)
        }

        return nil
    }

    private func manualQueueContextPayload(matching diagnostics: SonosNowPlayingDiagnostics) -> SonosPlayablePayload? {
        guard let payloads = manualQueueContextPayloads,
              !payloads.isEmpty
        else {
            return nil
        }

        let observedURIs = [
            normalizedManualPlaybackURI(diagnostics.currentURI),
            normalizedManualPlaybackURI(diagnostics.trackURI),
        ].compactMap(\.self)

        return payloads.first { payload in
            guard let payloadURI = normalizedManualPlaybackURI(payload.uri) else {
                return false
            }

            if observedURIs.contains(payloadURI) {
                return true
            }

            guard let payloadItemID = manualPlaybackItemID(from: payload.uri) else {
                return false
            }

            return observedURIs.contains { $0.contains(payloadItemID) }
        }
    }

    private func shouldPreserveManualPlaybackTitle(
        in snapshot: SonosNowPlayingSnapshot,
        diagnostics: SonosNowPlayingDiagnostics,
        payload: SonosPlayablePayload
    ) -> Bool {
        guard !diagnostics.hasTrackMetadata else {
            return false
        }

        let snapshotTitle = snapshot.title.sonoicTrimmed
        let serviceName = payload.service?.name.sonoicTrimmed

        return snapshotTitle.isEmpty
            || snapshotTitle.caseInsensitiveCompare(snapshot.sourceName.sonoicTrimmed) == .orderedSame
            || serviceName.map { snapshotTitle.caseInsensitiveCompare($0) == .orderedSame } == true
            || SonosMetadataHeuristics.isGenericQueueTitle(snapshotTitle)
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

    private func manualPlaybackContextMatches(
        _ snapshot: SonosNowPlayingSnapshot,
        diagnostics: SonosNowPlayingDiagnostics,
        payload: SonosPlayablePayload
    ) -> Bool {
        let payloadURI = normalizedManualPlaybackURI(payload.uri)
        let observedURIs = [
            normalizedManualPlaybackURI(diagnostics.currentURI),
            normalizedManualPlaybackURI(diagnostics.trackURI),
        ].compactMap(\.self)

        if let payloadURI,
           observedURIs.contains(payloadURI)
        {
            return true
        }

        if let payloadItemID = manualPlaybackItemID(from: payload.uri),
           observedURIs.contains(where: { $0.contains(payloadItemID) })
        {
            return true
        }

        let titleMatches = snapshot.title.sonoicTrimmed.caseInsensitiveCompare(payload.title.sonoicTrimmed) == .orderedSame
        let sourceMatches = payload.service?.name.sonoicNonEmptyTrimmed == nil
            || snapshot.sourceName.sonoicTrimmed.caseInsensitiveCompare(payload.service?.name.sonoicTrimmed ?? "") == .orderedSame
            || diagnostics.currentURIOwnership == .directServiceStream
            || diagnostics.trackURIOwnership == .directServiceStream

        return titleMatches && sourceMatches
    }

    private func clearManualPlaybackContextIfContentChanged(
        _ snapshot: SonosNowPlayingSnapshot,
        diagnostics: SonosNowPlayingDiagnostics,
        payload: SonosPlayablePayload
    ) {
        guard diagnostics.currentURI.sonoicNonEmptyTrimmed != nil
                || diagnostics.trackURI.sonoicNonEmptyTrimmed != nil
                || diagnostics.hasTrackMetadata
                || diagnostics.hasSourceMetadata
        else {
            return
        }

        guard snapshot.title.sonoicTrimmed.caseInsensitiveCompare(payload.title.sonoicTrimmed) != .orderedSame else {
            return
        }

        manualPlaybackContextPayload = nil
    }

    private func manualPlaybackSubtitleParts(for payload: SonosPlayablePayload) -> [String] {
        payload.subtitle?
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private func normalizedManualPlaybackURI(_ uri: String?) -> String? {
        uri?
            .replacingOccurrences(of: "&amp;", with: "&")
            .sonoicNonEmptyTrimmed?
            .lowercased()
    }

    private func manualPlaybackItemID(from uri: String) -> String? {
        guard let normalizedURI = normalizedManualPlaybackURI(uri),
              let idStartRange = normalizedURI.range(of: "%3a")
        else {
            return nil
        }

        let valueAfterPrefix = normalizedURI[idStartRange.upperBound...]
        let id = valueAfterPrefix.split(separator: "?", maxSplits: 1).first.map(String.init)
        return id?.sonoicNonEmptyTrimmed
    }
}
