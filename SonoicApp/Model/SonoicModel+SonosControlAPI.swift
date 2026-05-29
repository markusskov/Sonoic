import Foundation

extension SonoicModel {
    struct SonosControlAPILoadRollbackState {
        private let queueState: SonosQueueState
        private let nowPlaying: SonosNowPlayingSnapshot
        private let nowPlayingObservedAt: Date
        private let manualPlaybackContextPayload: SonosPlayablePayload?
        private let manualQueueContextPayloads: [SonosPlayablePayload]?
        private let manualRecentPlaybackContextPayload: SonosPlayablePayload?
        private let cloudQueueRuntimeState: SonosControlAPICloudQueueRuntimeState

        @MainActor
        init(_ model: SonoicModel) {
            queueState = model.queueState
            nowPlaying = model.nowPlaying
            nowPlayingObservedAt = model.nowPlayingObservedAt
            manualPlaybackContextPayload = model.manualPlaybackContextPayload
            manualQueueContextPayloads = model.manualQueueContextPayloads
            manualRecentPlaybackContextPayload = model.manualRecentPlaybackContextPayload
            cloudQueueRuntimeState = model.sonosControlAPICloudQueueRuntimeState
        }

        @MainActor
        func restoreFailedLoad(
            on model: SonoicModel,
            didLoseAuthorization: Bool,
            clearManualContextOnAuthorizationLoss: Bool
        ) {
            if !didLoseAuthorization || !queueState.isSonosControlAPICloudQueueBacked {
                model.queueState = queueState
            }
            model.nowPlaying = nowPlaying
            model.nowPlayingObservedAt = nowPlayingObservedAt

            if didLoseAuthorization {
                if clearManualContextOnAuthorizationLoss {
                    model.manualPlaybackContextPayload = nil
                    model.manualQueueContextPayloads = nil
                    model.manualRecentPlaybackContextPayload = nil
                }
                model.clearSonosControlAPICloudQueueContext()
                return
            }

            model.manualPlaybackContextPayload = manualPlaybackContextPayload
            model.manualQueueContextPayloads = manualQueueContextPayloads
            model.manualRecentPlaybackContextPayload = manualRecentPlaybackContextPayload
            model.sonosControlAPICloudQueueRuntimeState = cloudQueueRuntimeState
            model.persistSonosControlAPICloudQueueContext()
        }
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
        clearSonosControlAPIPlaybackContextAfterAuthorizationLoss()
    }

    func clearSonosControlAPIPlaybackContextAfterAuthorizationLoss() {
        let queueSnapshotIsCloudOwned = queueState.isSonosControlAPICloudQueueBacked
        clearManualSeekConfirmation()
        manualPlaybackContextPayload = nil
        manualQueueContextPayloads = nil
        manualRecentPlaybackContextPayload = nil
        clearSonosControlAPICloudQueueContext()
        if queueSnapshotIsCloudOwned {
            queueState = .idle
            queueOperationErrorDetail = nil
            queueDiagnostics = .empty
            isQueueRefreshing = false
            isQueueClearing = false
            isQueueMutating = false
        }
        persistSharedExternalControlState(forceImmediate: true)
    }

    func syncSonosControlAPIPlaybackStateIfAvailable(
        showProgress: Bool,
        forceRoomRefresh: Bool = false
    ) async -> Bool {
        if showProgress {
            manualHostRefreshStatus = .refreshing
        }

        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudRefresh") else {
            manualHostRefreshStatus = .failed("Sonos Cloud is unavailable.")
            return false
        }

        do {
            async let refreshedPlaybackStatus = sonosControlAPIClient.playbackStatus(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
            async let refreshedMetadataStatus = sonosControlAPIClient.playbackMetadata(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
            async let refreshedExternalVolume = fetchSonosControlAPIActiveTargetVolume()

            let playbackStatus = try await refreshedPlaybackStatus
            let metadataStatus = try await refreshedMetadataStatus
            restoreSonosControlAPICloudQueueContextIfNeeded(
                groupID: context.groupID,
                queueVersion: playbackStatus.queueVersion
            )
            updateSonosControlAPICloudQueueCurrentItem(
                itemIDCandidates: [
                    playbackStatus.itemId,
                    metadataStatus.currentItem?.id
                ]
            )
            var nextNowPlaying = sonosControlAPINowPlayingSnapshot(
                playbackStatus: playbackStatus,
                metadataStatus: metadataStatus,
                fallback: effectiveNowPlayingSnapshotForActiveTarget
            )
            nextNowPlaying = smoothedNowPlayingSnapshot(nextNowPlaying, diagnostics: .empty)
            nextNowPlaying.artworkIdentifier = try? await syncArtworkIdentifier(for: nextNowPlaying)

            if nowPlaying != nextNowPlaying {
                nowPlaying = nextNowPlaying
            }

            if nowPlayingDiagnostics != .empty {
                nowPlayingDiagnostics = .empty
            }

            if let nextVolume = try? await refreshedExternalVolume,
               externalVolume != nextVolume {
                externalVolume = nextVolume
            }

            if forceRoomRefresh {
                await refreshSonosControlAPICloudSnapshot()
            }

            scheduleManualPlayConfirmationRetryIfNeeded(for: nextNowPlaying.playbackState)

            let refreshedAt = Date()
            manualHostLastSuccessfulRefreshAt = refreshedAt
            manualHostRefreshStatus = .updated(refreshedAt)
            return true
        } catch {
            manualPlayTransitionGraceDeadline = nil
            setManualPlayTransitionAwaitingConfirmation(false)
            recordSonosControlAPIError(error)
            if isSonosControlAPIAuthorizationFailure(error) {
                sonosControlAPIState.authorizationStatus = .expired
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
                clearSonosControlAPIPlaybackContextAfterAuthorizationLoss()
            }
            manualHostRefreshStatus = .failed(error.localizedDescription)
            return false
        }
    }

    private func sonosControlAPINowPlayingSnapshot(
        playbackStatus: SonosControlAPIPlaybackStatus,
        metadataStatus: SonosControlAPIMetadataStatus,
        fallback: SonosNowPlayingSnapshot
    ) -> SonosNowPlayingSnapshot {
        if let lineInSnapshot = sonosControlAPILineInNowPlayingSnapshot(
            playbackStatus: playbackStatus,
            metadataStatus: metadataStatus
        ) {
            return lineInSnapshot
        }

        let track = metadataStatus.currentItem?.track
        let container = metadataStatus.container
        let cloudQueueIndex = sonosControlAPICloudQueueCurrentIndex(
            from: [
                playbackStatus.itemId,
                metadataStatus.currentItem?.id
            ]
        )
        let cloudQueuePayload = cloudQueueIndex.flatMap { index in
            manualQueueContextPayloads.flatMap { $0.indices.contains(index) ? $0[index] : nil }
        }
        let cloudQueueTrack = cloudQueueIndex.flatMap { index in
            sonosControlAPICloudQueueRuntimeState.track(at: index)
        }
        let cloudQueueSubtitleParts = sonosControlAPISubtitleParts(from: cloudQueuePayload?.subtitle)
        let title = track?.name?.sonoicNonEmptyTrimmed
            ?? cloudQueueTrack?.name?.sonoicNonEmptyTrimmed
            ?? cloudQueuePayload?.title.sonoicNonEmptyTrimmed
            ?? metadataStatus.streamInfo?.sonoicNonEmptyTrimmed
            ?? fallback.title
        let artistName = track?.artist?.name.sonoicNonEmptyTrimmed
            ?? cloudQueueTrack?.artist?.name.sonoicNonEmptyTrimmed
            ?? cloudQueueSubtitleParts.first
        let albumTitle = track?.album?.name.sonoicNonEmptyTrimmed
            ?? cloudQueueTrack?.album?.name.sonoicNonEmptyTrimmed
            ?? cloudQueueSubtitleParts.dropFirst().first
        let sourceName = track?.service?.name?.sonoicNonEmptyTrimmed
            ?? cloudQueueTrack?.service?.name?.sonoicNonEmptyTrimmed
            ?? container?.service?.name?.sonoicNonEmptyTrimmed
            ?? cloudQueuePayload?.service?.name.sonoicNonEmptyTrimmed
            ?? fallback.sourceName
        let artworkURL = track?.imageUrl?.sonoicNonEmptyTrimmed
            ?? cloudQueueTrack?.imageUrl?.sonoicNonEmptyTrimmed
            ?? cloudQueuePayload?.artworkURL?.sonoicNonEmptyTrimmed
            ?? container?.imageUrl?.sonoicNonEmptyTrimmed
            ?? fallback.artworkURL
        let artworkIdentifier = artworkURL == fallback.artworkURL ? fallback.artworkIdentifier : nil

        return SonosNowPlayingSnapshot(
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            sourceName: sourceName,
            playbackState: sonosControlAPIPlaybackState(playbackStatus.playbackState),
            artworkURL: artworkURL,
            artworkIdentifier: artworkIdentifier,
            elapsedTime: playbackStatus.positionMillis.map { TimeInterval($0) / 1_000 },
            duration: track?.durationMillis.map { TimeInterval($0) / 1_000 }
                ?? cloudQueueTrack?.durationMillis.map { TimeInterval($0) / 1_000 }
                ?? cloudQueuePayload?.duration
                ?? fallback.duration,
            transportActions: sonosControlAPITransportActions(
                playbackStatus: playbackStatus,
                metadataStatus: metadataStatus
            ),
            quality: sonosControlAPINowPlayingQuality(from: track?.quality ?? cloudQueueTrack?.quality)
        )
    }

    private func sonosControlAPINowPlayingQuality(
        from quality: SonosControlAPITrackQuality?
    ) -> SonosNowPlayingQuality? {
        guard let quality else {
            return nil
        }

        let nowPlayingQuality = SonosNowPlayingQuality(
            bitDepth: quality.bitDepth,
            sampleRate: quality.sampleRate,
            codec: quality.codec,
            lossless: quality.lossless,
            immersive: quality.immersive
        )
        return nowPlayingQuality.hasDisplayBadges ? nowPlayingQuality : nil
    }

    private func sonosControlAPILineInNowPlayingSnapshot(
        playbackStatus: SonosControlAPIPlaybackStatus,
        metadataStatus: SonosControlAPIMetadataStatus
    ) -> SonosNowPlayingSnapshot? {
        guard metadataStatus.currentItem?.track == nil,
              let container = metadataStatus.container,
              let containerType = container.type?.sonoicNonEmptyTrimmed
        else {
            return nil
        }

        let normalizedType = containerType.lowercased()
        guard normalizedType.hasPrefix("linein") else {
            return nil
        }

        let containerName = container.name?.sonoicNonEmptyTrimmed
        let normalizedName = containerName?.lowercased() ?? ""
        let isTVAudio = normalizedType.contains("hometheater")
            || normalizedType.contains("home_theater")
            || normalizedName.contains("tv")

        let title: String
        let sourceName: String
        if isTVAudio {
            title = containerName ?? "TV Audio"
            sourceName = "HDMI"
        } else {
            title = containerName ?? "Line-In"
            sourceName = "Line-In"
        }

        return SonosNowPlayingSnapshot(
            title: title,
            artistName: nil,
            albumTitle: nil,
            sourceName: sourceName,
            playbackState: sonosControlAPIPlaybackState(playbackStatus.playbackState),
            artworkURL: container.imageUrl?.sonoicNonEmptyTrimmed,
            artworkIdentifier: nil,
            elapsedTime: nil,
            duration: nil,
            transportActions: sonosControlAPITransportActions(
                playbackStatus: playbackStatus,
                metadataStatus: metadataStatus
            )
        )
    }

    private func sonosControlAPIPlaybackState(
        _ playbackState: SonosControlAPIPlaybackState
    ) -> SonosNowPlayingSnapshot.PlaybackState {
        switch playbackState {
        case .playing:
            manualPlayTransitionGraceDeadline = nil
            setManualPlayTransitionAwaitingConfirmation(false)
            return .playing
        case .paused, .idle:
            manualPlayTransitionGraceDeadline = nil
            setManualPlayTransitionAwaitingConfirmation(false)
            return .paused
        case .buffering:
            return resolvedPlaybackState(.buffering)
        }
    }

    private func sonosControlAPITransportActions(
        playbackStatus: SonosControlAPIPlaybackStatus,
        metadataStatus: SonosControlAPIMetadataStatus
    ) -> SonosTransportActions {
        let availableActions = playbackStatus.availablePlaybackActions
        var rawActions: Set<String> = []

        if playbackStatus.playbackState == .paused || playbackStatus.playbackState == .idle {
            rawActions.insert("Play")
        }
        if (playbackStatus.playbackState == .playing || playbackStatus.playbackState == .buffering),
           availableActions?.canPause != false
        {
            rawActions.insert("Pause")
        }
        if availableActions?.canStop == true {
            rawActions.insert("Stop")
        }
        if availableActions?.canSeek == true,
           sonosControlAPISeekableDurationMillis(
            playbackStatus: playbackStatus,
            metadataStatus: metadataStatus
           ) != nil
        {
            rawActions.insert("Seek")
        }
        if availableActions?.canSkip == true {
            rawActions.insert("Next")
        }
        if availableActions?.canSkipBack == true {
            rawActions.insert("Previous")
        }

        return SonosTransportActions(rawActions: rawActions)
    }

    private func sonosControlAPISeekableDurationMillis(
        playbackStatus: SonosControlAPIPlaybackStatus,
        metadataStatus: SonosControlAPIMetadataStatus
    ) -> Int? {
        if let durationMillis = metadataStatus.currentItem?.track?.durationMillis,
           durationMillis > 0
        {
            return durationMillis
        }

        let cloudQueueIndex = sonosControlAPICloudQueueCurrentIndex(
            from: [
                playbackStatus.itemId,
                metadataStatus.currentItem?.id,
                queueState.snapshot?.currentItemIndex.map { String($0 + 1) }
            ]
        )

        if let cloudQueueIndex,
           let durationMillis = sonosControlAPICloudQueueRuntimeState.track(at: cloudQueueIndex)?.durationMillis,
           durationMillis > 0
        {
            return durationMillis
        }

        if let cloudQueueIndex,
           let duration = manualQueueContextPayloads.flatMap({ payloads in
            payloads.indices.contains(cloudQueueIndex) ? payloads[cloudQueueIndex].duration : nil
           })
        {
            let durationMillis = Int((duration * 1_000).rounded())
            return durationMillis > 0 ? durationMillis : nil
        }

        return nil
    }

    func sonosControlAPISubtitleParts(from subtitle: String?) -> [String] {
        subtitle?
            .components(separatedBy: "•")
            .map(\.sonoicTrimmed)
            .filter { !$0.isEmpty } ?? []
    }

}

private extension SonosQueueState {
    var isSonosControlAPICloudQueueBacked: Bool {
        snapshot?.sourceURI?
            .lowercased()
            .hasPrefix("sonoic-cloud-queue") == true
    }
}
