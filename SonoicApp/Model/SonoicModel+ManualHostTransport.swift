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

        return await performManualTransportCommand(
            syncDelay: Self.manualTransportSyncDelay,
            refreshQueueAfterSuccess: true
        ) {
            try await avTransportClient.next(host: manualSonosHost)
        }
    }

    func skipToPreviousManualSonosTrack() async -> Bool {
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }

        return await performManualTransportCommand(
            syncDelay: Self.manualTransportSyncDelay,
            refreshQueueAfterSuccess: true
        ) {
            try await avTransportClient.previous(host: manualSonosHost)
        }
    }

    func seekManualSonosPlayback(to timeInterval: TimeInterval) async -> Bool {
        await performManualTransportCommand {
            try await avTransportClient.seek(host: manualSonosHost, timeInterval: timeInterval)
        }
    }

    func playManualSonosQueueItem(at position: Int) async -> Bool {
        guard position > 0 else {
            return false
        }

        beginManualPlayTransitionGrace()
        markLocalPlaybackState(.playing)
        return await performManualTransportCommand(
            syncDelay: Self.manualTransportSyncDelay,
            refreshQueueAfterSuccess: true
        ) {
            try await avTransportClient.seekToTrack(host: manualSonosHost, trackNumber: position)
            try await avTransportClient.play(host: manualSonosHost)
        }
    }

    func playManualSonosFavorite(_ favorite: SonosFavoriteItem) async -> Bool {
        guard let payload = favorite.playablePayload else {
            return false
        }

        return await playManualSonosPayload(payload)
    }

    func playManualSonosPayload(_ payload: SonosPlayablePayload) async -> Bool {
        guard let preparedPayload = try? SonosPlayablePayloadPreparer().prepare(payload) else {
            return false
        }

        if let snapshot = queueState.snapshot {
            queueState = .loaded(SonosQueueSnapshot(
                items: snapshot.items,
                currentItemIndex: nil,
                sourceURI: snapshot.sourceURI
            ))
        }

        beginManualPlayTransitionGrace()
        markLocalPlaybackState(.playing)
        let didStartPlayback = await performManualTransportCommand(syncDelay: Self.manualTransportSyncDelay) {
            let playbackHost = await manualSonosCoordinatorHost() ?? manualSonosHost
            try await avTransportClient.setTransportURI(
                host: playbackHost,
                uri: preparedPayload.uri,
                metadataXML: preparedPayload.metadataXML
            )
            try await avTransportClient.play(host: playbackHost)
        }

        if didStartPlayback {
            recordRecentPlayablePayload(preparedPayload)
        }

        return didStartPlayback
    }

    func toggleManualSonosMute() async {
        guard hasManualSonosHost else {
            return
        }

        let desiredMute = !externalVolume.isMuted
        manualHostRefreshStatus = .refreshing

        do {
            try await setExternalMuteForActiveTarget(desiredMute)
            externalVolume.isMuted = desiredMute
            manualHostRefreshStatus = .updated(.now)
            startManualHostRefreshLoopIfPossible()
        } catch {
            manualHostRefreshStatus = .failed(error.localizedDescription)
        }
    }

    func setManualSonosVolume(to level: Int) async -> Bool {
        guard hasManualSonosHost else {
            return false
        }

        let boundedLevel = min(max(level, 0), 100)
        externalVolume.level = boundedLevel
        pendingManualVolumeLevel = boundedLevel

        guard !isManualVolumeCommandInFlight else {
            return true
        }

        isManualVolumeCommandInFlight = true
        defer {
            isManualVolumeCommandInFlight = false
        }

        var latestRequestSucceeded = true

        while let nextLevel = pendingManualVolumeLevel {
            pendingManualVolumeLevel = nil
            let previousVolume = externalVolume
            externalVolume.level = nextLevel
            manualHostRefreshStatus = .refreshing

            do {
                try await setExternalVolumeForActiveTarget(to: nextLevel)
                manualHostRefreshStatus = .updated(.now)
                latestRequestSucceeded = true
            } catch {
                latestRequestSucceeded = false
                if pendingManualVolumeLevel == nil {
                    externalVolume = previousVolume
                    manualHostRefreshStatus = .failed(error.localizedDescription)
                }
            }
        }

        startManualHostRefreshLoopIfPossible()
        return latestRequestSucceeded
    }

    private func performManualTransportCommand(
        syncDelay: Duration? = nil,
        refreshQueueAfterSuccess: Bool = false,
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
                manualHostRefreshStatus = .refreshing
                scheduleManualStateSync(
                    after: syncDelay,
                    restartRefreshLoop: true,
                    refreshQueueAfterSync: refreshQueueAfterSuccess
                )
            } else {
                _ = await syncManualSonosState(showProgress: false)
                if refreshQueueAfterSuccess {
                    await refreshQueueAfterPlaybackChangeIfNeeded()
                }
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

    private func manualSonosQueuePlayerID() async -> String? {
        let normalizedHost = normalizedManualSonosHost(manualSonosHost)

        if let topology = try? await zoneGroupTopologyClient.fetchTopology(host: manualSonosHost),
           let coordinatorID = topology.coordinatorID(matchingTargetID: activeTarget.id, host: normalizedHost)
        {
            return coordinatorID
        }

        if let activeTargetID = activeTarget.id.sonoicNonEmptyTrimmed,
           activeTargetID.hasPrefix("RINCON_")
        {
            return activeTargetID
        }

        let deviceInfo = try? await deviceInfoClient.fetchDeviceInfo(host: manualSonosHost)
        return deviceInfo?.preferredTargetID
    }
}
