import Foundation

extension SonoicModel {
    private static let manualTransportSyncDelay: Duration = .milliseconds(300)

    var canControlManualPlayback: Bool {
        if sonosControlAPIState.settings.mode.canSendCommands {
            return sonosControlAPIState.canSendCommands
        }

        return hasManualSonosHost
    }

    func toggleManualSonosPlayback() async {
        switch nowPlaying.playbackState {
        case .playing:
            _ = await pauseManualSonosPlayback()
        case .paused, .buffering:
            _ = await playManualSonosPlayback()
        }
    }

    func playManualSonosPlayback() async -> Bool {
        if sonosControlAPIState.settings.mode.canSendCommands {
            if await playSonosControlAPIPlaybackIfAvailable() {
                return true
            }

            sonoicPlaybackDebugLog("manualPlay cloudUnavailable noLocalTransportFallback=true")
            return false
        }

        return await playLocalManualSonosPlayback()
    }

    func pauseManualSonosPlayback() async -> Bool {
        if sonosControlAPIState.settings.mode.canSendCommands {
            if await pauseSonosControlAPIPlaybackIfAvailable() {
                return true
            }

            sonoicPlaybackDebugLog("manualPause cloudUnavailable noLocalTransportFallback=true")
            return false
        }

        return await pauseLocalManualSonosPlayback()
    }

    func skipToNextManualSonosTrack() async -> Bool {
        if sonosControlAPIState.settings.mode.canSendCommands {
            if await skipToNextSonosControlAPITrackIfAvailable() {
                return true
            }

            sonoicPlaybackDebugLog("manualNext cloudUnavailable noLocalTransportFallback=true")
            return false
        }

        return await skipToNextLocalManualSonosTrack()
    }

    func skipToPreviousManualSonosTrack() async -> Bool {
        if sonosControlAPIState.settings.mode.canSendCommands {
            if await skipToPreviousSonosControlAPITrackIfAvailable() {
                return true
            }

            sonoicPlaybackDebugLog("manualPrevious cloudUnavailable noLocalTransportFallback=true")
            return false
        }

        return await skipToPreviousLocalManualSonosTrack()
    }

    func seekManualSonosPlayback(to timeInterval: TimeInterval) async -> Bool {
        sonoicPlaybackDebugLog(
            "manualSeek start target=\(timeInterval) canSeek=\(nowPlaying.canSeek) hasHost=\(hasManualSonosHost) cloudCanSend=\(sonosControlAPIState.canSendCommands) cloudAuth=\(String(describing: sonosControlAPIState.authorizationStatus)) cloudMode=\(sonosControlAPIState.settings.mode.rawValue)"
        )
        if !sonosControlAPIState.settings.mode.canSendCommands {
            return await seekLocalManualSonosPlayback(to: timeInterval)
        }

        let previousNowPlaying = nowPlaying
        let previousObservedAt = nowPlayingObservedAt

        if await seekSonosControlAPIPlaybackIfAvailable(to: timeInterval) {
            sonoicPlaybackDebugLog("manualSeek cloudConfirmed target=\(timeInterval)")
            return true
        }

        clearManualSeekConfirmation()
        nowPlaying = previousNowPlaying
        nowPlayingObservedAt = previousObservedAt
        sonoicPlaybackDebugLog("manualSeek cloudFailed noLocalTransportFallback=true target=\(timeInterval)")
        return false
    }

    func recordSeekDiagnostics(
        status: SonosSeekDiagnostics.Status,
        host: String?,
        target: TimeInterval?,
        observed: TimeInterval?,
        errorDetail: String?
    ) {
        seekDiagnostics = SonosSeekDiagnostics(
            status: status,
            requestedAt: .now,
            host: host,
            target: target,
            observed: observed,
            errorDetail: errorDetail
        )
    }

    private func playLocalManualSonosPlayback() async -> Bool {
        beginManualPlayTransitionGrace()
        markLocalPlaybackState(.playing)
        let didPlay = await performManualTransportCommand(
            syncDelay: Self.manualTransportSyncDelay
        ) {
            let playbackHost = await manualSonosCoordinatorHost() ?? manualSonosHost
            try await avTransportClient.play(host: playbackHost)
        }
        sonoicPlaybackDebugLog("manualPlay localMode result=\(didPlay)")
        return didPlay
    }

    private func pauseLocalManualSonosPlayback() async -> Bool {
        manualPlayTransitionGraceDeadline = nil
        setManualPlayTransitionAwaitingConfirmation(false)
        freezeLocalPlaybackTimeIfNeeded()
        markLocalPlaybackState(.paused)
        let didPause = await performManualTransportCommand(
            syncDelay: Self.manualTransportSyncDelay
        ) {
            let playbackHost = await manualSonosCoordinatorHost() ?? manualSonosHost
            try await avTransportClient.pause(host: playbackHost)
        }
        sonoicPlaybackDebugLog("manualPause localMode result=\(didPause)")
        return didPause
    }

    private func skipToNextLocalManualSonosTrack() async -> Bool {
        manualPlaybackContextPayload = nil
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }
        let didSkip = await performManualTransportCommand(
            syncDelay: Self.manualTransportSyncDelay,
            refreshQueueAfterSuccess: true
        ) {
            let playbackHost = await manualSonosCoordinatorHost() ?? manualSonosHost
            try await avTransportClient.next(host: playbackHost)
        }
        sonoicPlaybackDebugLog("manualNext localMode result=\(didSkip)")
        return didSkip
    }

    private func skipToPreviousLocalManualSonosTrack() async -> Bool {
        manualPlaybackContextPayload = nil
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }
        let didSkip = await performManualTransportCommand(
            syncDelay: Self.manualTransportSyncDelay,
            refreshQueueAfterSuccess: true
        ) {
            let playbackHost = await manualSonosCoordinatorHost() ?? manualSonosHost
            try await avTransportClient.previous(host: playbackHost)
        }
        sonoicPlaybackDebugLog("manualPrevious localMode result=\(didSkip)")
        return didSkip
    }

    private func seekLocalManualSonosPlayback(to timeInterval: TimeInterval) async -> Bool {
        let previousNowPlaying = nowPlaying
        let previousObservedAt = nowPlayingObservedAt
        let boundedElapsedTime = markLocalSeek(to: timeInterval)
        beginManualSeekConfirmation(to: boundedElapsedTime)
        let didSeek = await performManualTransportCommand(
            syncDelay: Self.manualTransportSyncDelay
        ) {
            let playbackHost = await manualSonosCoordinatorHost() ?? manualSonosHost
            try await avTransportClient.seek(host: playbackHost, timeInterval: boundedElapsedTime)
        }

        if !didSeek {
            clearManualSeekConfirmation()
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousObservedAt
        }

        sonoicPlaybackDebugLog("manualSeek localMode result=\(didSeek) target=\(boundedElapsedTime)")
        return didSeek
    }

    func playManualSonosQueueItem(at position: Int) async -> Bool {
        guard position > 0 else {
            sonoicPlaybackDebugLog("queueSeek invalidPosition=\(position)")
            return false
        }

        if sonosControlAPIState.settings.mode.canSendCommands {
            return await skipSonosControlAPICloudQueueItemIfAvailable(at: position)
        }

        sonoicPlaybackDebugLog("queueSeek start position=\(position) host=\(manualSonosHost)")
        manualPlaybackContextPayload = nil
        manualQueueContextPayloads = nil
        clearSonosControlAPICloudQueueContext()
        manualRecentPlaybackContextPayload = nil
        beginManualPlayTransitionGrace()
        markLocalPlaybackState(.playing)
        let didSeek = await performManualTransportCommand(
            syncDelay: Self.manualTransportSyncDelay,
            refreshQueueAfterSuccess: true
        ) {
            try await avTransportClient.seekToTrack(host: manualSonosHost, trackNumber: position)
            try await avTransportClient.play(host: manualSonosHost)
        }
        sonoicPlaybackDebugLog("queueSeek result=\(didSeek) position=\(position)")
        return didSeek
    }

    func playManualSonosFavorite(_ favorite: SonosFavoriteItem) async -> Bool {
        sonoicPlaybackDebugLog(
            "manualFavorite start title='\(favorite.title)' kind=\(favorite.kind.rawValue) isPlaylistLike=\(favorite.isPlaylistLike)"
        )
        if await playSonosControlAPIFavoriteIfAvailable(favorite) {
            sonoicPlaybackDebugLog("manualFavorite cloudSuccess title='\(favorite.title)'")
            return true
        }

        if sonosControlAPIState.settings.mode.canSendCommands {
            if !favorite.isCollectionLike,
               let payload = favorite.playablePayload
            {
                let sourceItem = SonoicSourceItem(favorite: favorite)
                let plan = SonoicSourcePlaylistPlaybackPlan(
                    payloads: [payload],
                    items: [sourceItem],
                    startingTrackNumber: 1,
                    localNowPlayingPayload: payload,
                    recentPlaybackPayload: payload
                )
                if await playSonosControlAPICloudQueueIfAvailable(parentItem: sourceItem, plan: plan) {
                    recordRecentFavoritePlayback(favorite)
                    sonoicPlaybackDebugLog("manualFavorite cloudQueueSuccess title='\(favorite.title)'")
                    return true
                }
            }

            sonoicPlaybackDebugLog("manualFavorite cloudFailed noLocalPlaybackFallback=true title='\(favorite.title)'")
            return false
        }

        guard let payload = favorite.playablePayload else {
            sonoicPlaybackDebugLog("manualFavorite noLANPayload title='\(favorite.title)'")
            return false
        }

        let didStart = await playManualSonosPayload(payload)
        sonoicPlaybackDebugLog("manualFavorite lanFallbackResult=\(didStart) title='\(favorite.title)'")
        return didStart
    }

    func playManualSonosPayload(
        _ payload: SonosPlayablePayload,
        startingTrackNumber: Int? = nil,
        localNowPlayingPayload: SonosPlayablePayload? = nil,
        recentPlaybackPayload: SonosPlayablePayload? = nil
    ) async -> Bool {
        guard let preparedPayload = try? SonosPlayablePayloadPreparer().prepare(payload) else {
            return false
        }
        let preparedLocalPayload = localNowPlayingPayload.flatMap {
            try? SonosPlayablePayloadPreparer().prepare($0)
        }
        let preparedRecentPayload = recentPlaybackPayload.flatMap {
            try? SonosPlayablePayloadPreparer().prepare($0)
        }
        let displayPayload = preparedLocalPayload ?? preparedPayload

        if let snapshot = queueState.snapshot {
            queueState = .loaded(SonosQueueSnapshot(
                items: snapshot.items,
                currentItemIndex: nil,
                sourceURI: snapshot.sourceURI
            ))
        }

        beginManualPlayTransitionGrace()
        manualQueueContextPayloads = nil
        clearSonosControlAPICloudQueueContext()
        manualRecentPlaybackContextPayload = nil
        manualPlaybackContextPayload = displayPayload
        markLocalNowPlaying(from: displayPayload)
        let didStartPlayback = await performManualTransportCommand(syncDelay: Self.manualTransportSyncDelay) {
            let playbackHost = await manualSonosCoordinatorHost() ?? manualSonosHost
            try await avTransportClient.setTransportURI(
                host: playbackHost,
                uri: preparedPayload.uri,
                metadataXML: preparedPayload.metadataXML
            )
            if SonosPlaybackSourceOwnership(uri: preparedPayload.uri) == .directServiceStream {
                try? await avTransportClient.setPlayMode(host: playbackHost, mode: "NORMAL")
            }
            if let startingTrackNumber,
               startingTrackNumber > 1
            {
                try? await avTransportClient.seekToTrack(host: playbackHost, trackNumber: startingTrackNumber)
            }
            try await avTransportClient.play(host: playbackHost)
        }

        if didStartPlayback {
            recordRecentPlayablePayload(preparedRecentPayload ?? displayPayload)
        } else {
            manualPlaybackContextPayload = nil
        }

        return didStartPlayback
    }

    func playManualSonosQueuePayloads(
        _ payloads: [SonosPlayablePayload],
        startingTrackNumber: Int,
        localNowPlayingPayload: SonosPlayablePayload? = nil,
        recentPlaybackPayload: SonosPlayablePayload? = nil
    ) async -> Bool {
        guard !payloads.isEmpty,
              startingTrackNumber > 0,
              startingTrackNumber <= payloads.count
        else {
            return false
        }

        let preparedPayloads = payloads.compactMap {
            try? SonosPlayablePayloadPreparer().prepare($0)
        }

        guard preparedPayloads.count == payloads.count else {
            return false
        }

        let preparedLocalPayload = localNowPlayingPayload.flatMap {
            try? SonosPlayablePayloadPreparer().prepare($0)
        }
        let preparedRecentPayload = recentPlaybackPayload.flatMap {
            try? SonosPlayablePayloadPreparer().prepare($0)
        }
        let confirmationPayload = preparedPayloads[startingTrackNumber - 1]
        let displayPayload = preparedLocalPayload ?? preparedPayloads[startingTrackNumber - 1]

        if let snapshot = queueState.snapshot {
            queueState = .loaded(SonosQueueSnapshot(
                items: snapshot.items,
                currentItemIndex: nil,
                sourceURI: snapshot.sourceURI
            ))
        }

        beginManualPlayTransitionGrace()
        manualQueueContextPayloads = preparedPayloads
        clearSonosControlAPICloudQueueContext()
        manualRecentPlaybackContextPayload = preparedRecentPayload
        manualPlaybackContextPayload = confirmationPayload
        markLocalNowPlaying(from: displayPayload)
        let didStartPlayback = await performManualTransportCommand(
            syncDelay: Self.manualTransportSyncDelay,
            refreshQueueAfterSuccess: true
        ) {
            let playbackHost = await manualSonosCoordinatorHost() ?? manualSonosHost
            let queuePlayerID = await manualSonosQueuePlayerID() ?? ""
            guard !queuePlayerID.isEmpty else {
                throw SonosControlTransport.TransportError.invalidResponse
            }

            try await avTransportClient.removeAllTracksFromQueue(host: playbackHost)

            for payload in preparedPayloads {
                _ = try await avTransportClient.addURIToQueue(
                    host: playbackHost,
                    uri: payload.uri,
                    metadataXML: payload.metadataXML,
                    enqueueAsNext: false
                )
            }

            try await avTransportClient.setTransportURI(
                host: playbackHost,
                uri: "x-rincon-queue:\(queuePlayerID)#0",
                metadataXML: nil
            )

            try await avTransportClient.seekToTrack(host: playbackHost, trackNumber: startingTrackNumber)

            try await avTransportClient.play(host: playbackHost)
        }

        if !didStartPlayback {
            manualPlaybackContextPayload = nil
            manualQueueContextPayloads = nil
            manualRecentPlaybackContextPayload = nil
        }

        return didStartPlayback
    }

    func toggleManualSonosMute() async {
        guard hasActiveSonosControlTarget else {
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
        guard hasActiveSonosControlTarget else {
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
            clearManualSeekConfirmation()
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
