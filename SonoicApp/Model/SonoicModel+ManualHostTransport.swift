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

    func playManualSonosQueueItem(at position: Int) async -> Bool {
        guard position > 0 else {
            return false
        }

        beginManualPlayTransitionGrace()
        markLocalPlaybackState(.playing)
        return await performManualTransportCommand(syncDelay: Self.manualTransportSyncDelay) {
            try await avTransportClient.seekToTrack(host: manualSonosHost, trackNumber: position)
            try await avTransportClient.play(host: manualSonosHost)
        }
    }

    func playManualSonosFavorite(_ favorite: SonosFavoriteItem) async -> Bool {
        guard let playbackURI = favorite.playbackURI.sonoicNonEmptyTrimmed,
              let queuePlayerID = await manualSonosQueuePlayerID()
        else {
            return false
        }

        queueState = .idle
        beginManualPlayTransitionGrace()
        markLocalPlaybackState(.playing)
        return await performManualTransportCommand(syncDelay: Self.manualTransportSyncDelay) {
            let trackNumber = try await avTransportClient.addURIToQueue(
                host: manualSonosHost,
                uri: playbackURI,
                metadataXML: favorite.playbackMetadataXML
            )
            try await avTransportClient.setTransportURI(
                host: manualSonosHost,
                uri: "x-rincon-queue:\(queuePlayerID)#0",
                metadataXML: nil
            )
            try await avTransportClient.seekToTrack(host: manualSonosHost, trackNumber: trackNumber)
            try await avTransportClient.play(host: manualSonosHost)
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
                try await renderingControlClient.setVolume(host: manualSonosHost, level: nextLevel)
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
