import Foundation

extension SonoicModel {
    private static let sonosControlAPITransportSyncDelay: Duration = .milliseconds(350)
    private static let sonosControlAPISeekPollDelay: Duration = .milliseconds(350)
    private static let sonosControlAPISeekPollAttempts = 5
    private static let sonosControlAPISeekSlotWaitDelay: Duration = .milliseconds(80)
    private static let sonosControlAPISeekSlotWaitAttempts = 8

    private struct SonosControlAPICommandContext {
        var householdID: String?
        var groupID: String
        var accessToken: String
    }

    private struct SonosControlAPISeekItemIDCandidate {
        var label: String
        var itemID: String?
    }

    private struct SonosControlAPICommandUnavailableError: LocalizedError {
        var errorDescription: String? {
            "Sonos Cloud control is unavailable."
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
        clearSonosControlAPICloudQueueContext()
    }

    func activeSonosControlAPIGroupID() -> String? {
        guard sonosControlAPIState.settings.mode.canSendCommands else {
            return nil
        }

        return activeSonosControlAPICommandTarget()?.groupID
            ?? sonosControlAPIState.settings.selectedGroupID?.sonoicNonEmptyTrimmed
    }

    func applyVerifiedSonosControlAPICloudSnapshot(_ snapshot: SonosControlAPICloudSnapshot) {
        markSonosControlAPIAuthorizationReady()

        var settings = sonosControlAPIState.settings
        var didChangeSettings = false

        if let target = snapshot.preferredCommandTarget(
            settings: settings,
            activeTargetID: activeTarget.id
        ) {
            if settings.selectedHouseholdID != target.householdID {
                settings.selectedHouseholdID = target.householdID
                didChangeSettings = true
            }

            if settings.selectedGroupID != target.groupID {
                settings.selectedGroupID = target.groupID
                didChangeSettings = true
            }
        }

        if didChangeSettings {
            updateSonosControlAPISettings(settings)
        }
    }

    func recordSonosControlAPICommand(_ description: String) {
        sonosControlAPIState.lastCommandDescription = description
        sonosControlAPIState.lastErrorDetail = nil
        sonosControlAPIState.lastUpdatedAt = .now
    }

    func recordSonosControlAPIError(_ error: Error) {
        sonosControlAPIState.lastErrorDetail = error.localizedDescription
        sonosControlAPIState.lastUpdatedAt = .now
    }

    func playSonosControlAPIPlaybackIfAvailable() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudPlay") else {
            return false
        }

        let previousNowPlaying = nowPlaying
        beginManualPlayTransitionGrace()
        markLocalPlaybackState(.playing)

        let didPlay = await performSonosControlAPITransportCommand(
            description: "Cloud play",
            refreshQueueAfterSuccess: false
        ) {
            try await sonosControlAPIClient.play(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }

        if !didPlay {
            nowPlaying = previousNowPlaying
        }

        return didPlay
    }

    func pauseSonosControlAPIPlaybackIfAvailable() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudPause") else {
            return false
        }

        let previousNowPlaying = nowPlaying
        manualPlayTransitionGraceDeadline = nil
        setManualPlayTransitionAwaitingConfirmation(false)
        freezeLocalPlaybackTimeIfNeeded()
        markLocalPlaybackState(.paused)

        let didPause = await performSonosControlAPITransportCommand(
            description: "Cloud pause",
            refreshQueueAfterSuccess: false
        ) {
            try await sonosControlAPIClient.pause(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }

        if !didPause {
            nowPlaying = previousNowPlaying
        }

        return didPause
    }

    func skipToNextSonosControlAPITrackIfAvailable() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudNext") else {
            return false
        }

        manualPlaybackContextPayload = nil
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }

        return await performSonosControlAPITransportCommand(
            description: "Cloud next",
            refreshQueueAfterSuccess: true
        ) {
            try await sonosControlAPIClient.skipToNextTrack(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }
    }

    func skipToPreviousSonosControlAPITrackIfAvailable() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudPrevious") else {
            return false
        }

        manualPlaybackContextPayload = nil
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }

        return await performSonosControlAPITransportCommand(
            description: "Cloud previous",
            refreshQueueAfterSuccess: true
        ) {
            try await sonosControlAPIClient.skipToPreviousTrack(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }
    }

    func seekSonosControlAPIPlaybackIfAvailable(to timeInterval: TimeInterval) async -> Bool {
        sonoicPlaybackDebugLog("cloudseek entry target=\(timeInterval)")
        guard sonosControlAPIState.settings.mode.canSendCommands else {
            sonoicPlaybackDebugLog(
                "cloudseek unavailable canSend=false auth=\(String(describing: sonosControlAPIState.authorizationStatus)) mode=\(sonosControlAPIState.settings.mode.rawValue) target=\(timeInterval)"
            )
            return false
        }

        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudseek") else {
            sonoicPlaybackDebugLog(
                "cloudseek unavailable contextMissing auth=\(String(describing: sonosControlAPIState.authorizationStatus)) mode=\(sonosControlAPIState.settings.mode.rawValue) selectedGroup=\(sonoicPlaybackDebugID(sonosControlAPIState.settings.selectedGroupID)) cloudState=\(sonoicPlaybackDebugCloudStatus(sonosControlAPICloudState.status)) target=\(timeInterval)"
            )
            return false
        }

        guard await waitForSonosControlAPISeekTransportSlot(target: timeInterval) else {
            return false
        }

        let previousNowPlaying = nowPlaying
        let previousObservedAt = nowPlayingObservedAt
        let boundedElapsedTime = markLocalSeek(to: timeInterval)
        beginManualSeekConfirmation(to: boundedElapsedTime)
        sonoicPlaybackDebugLog(
            "cloudseek start target=\(boundedElapsedTime) group=\(sonoicPlaybackDebugID(context.groupID))"
        )
        recordSeekDiagnostics(
            status: .pending,
            host: "Sonos Control API",
            target: boundedElapsedTime,
            observed: nil,
            errorDetail: nil
        )

        var observedElapsedTime: TimeInterval?
        var observedPlaybackState: SonosControlAPIPlaybackState?
        var didConfirmSeek = false
        var pollingErrorDetail: String?
        var requestedAt = Date()
        let didSeek = await performSonosControlAPITransportCommand(
            description: "Cloud seek",
            refreshQueueAfterSuccess: false,
            syncDelay: .milliseconds(100)
        ) {
            let status = try await sonosControlAPIClient.playbackStatus(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
            if status.availablePlaybackActions?.canSeek == false {
                throw SonosControlAPISeekFailure.unsupported
            }
            sonoicPlaybackDebugLog(
                "cloudseek status canSeek=\(String(describing: status.availablePlaybackActions?.canSeek)) itemID=\(sonoicPlaybackDebugID(status.itemId)) positionMillis=\(String(describing: status.positionMillis))"
            )
            let itemIDCandidates = sonosControlAPISeekItemIDCandidates(from: status)
            sonoicPlaybackDebugLog(
                "cloudseek seekPayload candidates=\(itemIDCandidates.map { "\($0.label):\($0.itemID.map(sonoicPlaybackDebugID) ?? "omitted")" }.joined(separator: ",")) rawItemID=\(sonoicPlaybackDebugID(status.itemId))"
            )
            requestedAt = Date()
            let targetMillis = Int((boundedElapsedTime * 1_000).rounded())
            if let sessionSeekTarget = sonosControlAPICloudQueueSeekTarget(from: status) {
                sonoicPlaybackDebugLog(
                    "cloudseek sessionSeek itemID=\(sonoicPlaybackDebugID(sessionSeekTarget.itemID)) session=\(sonoicPlaybackDebugID(sessionSeekTarget.sessionID)) targetMillis=\(targetMillis)"
                )
                do {
                    try await sonosControlAPIClient.seekPlaybackSession(
                        sessionID: sessionSeekTarget.sessionID,
                        itemID: sessionSeekTarget.itemID,
                        positionMillis: targetMillis,
                        accessToken: context.accessToken
                    )
                } catch {
                    sonoicPlaybackDebugLog(
                        "cloudseek sessionSeekFailed retrySkipToItem itemID=\(sonoicPlaybackDebugID(sessionSeekTarget.itemID)) error='\(error.localizedDescription)'"
                    )
                    try await sonosControlAPIClient.skipToItem(
                        sessionID: sessionSeekTarget.sessionID,
                        itemID: sessionSeekTarget.itemID,
                        queueVersion: sonosControlAPICloudQueueVersion,
                        positionMillis: targetMillis,
                        playOnCompletion: true,
                        trackMetadata: sessionSeekTarget.track,
                        accessToken: context.accessToken
                    )
                }
                return
            }

            var lastSeekError: Error?
            for candidate in itemIDCandidates {
                sonoicPlaybackDebugLog(
                    "cloudseek attemptAbsolute candidate=\(candidate.label) itemID=\(candidate.itemID.map(sonoicPlaybackDebugID) ?? "omitted")"
                )
                do {
                    try await sonosControlAPIClient.seek(
                        groupID: context.groupID,
                        positionMillis: targetMillis,
                        itemID: candidate.itemID,
                        accessToken: context.accessToken
                    )
                    lastSeekError = nil
                    break
                } catch {
                    lastSeekError = error
                    if sonosControlAPIError(error, matchesStatus: 499, detailContains: "ERROR_DISALLOWED_BY_POLICY"),
                       let positionMillis = status.positionMillis
                    {
                        let deltaMillis = targetMillis - positionMillis
                        sonoicPlaybackDebugLog(
                            "cloudseek absoluteDisallowed retryRelative deltaMillis=\(deltaMillis) currentMillis=\(positionMillis) targetMillis=\(targetMillis) candidate=\(candidate.label) itemID=\(candidate.itemID.map(sonoicPlaybackDebugID) ?? "omitted")"
                        )
                        do {
                            try await sonosControlAPIClient.seekRelative(
                                groupID: context.groupID,
                                deltaMillis: deltaMillis,
                                itemID: candidate.itemID,
                                accessToken: context.accessToken
                            )
                            lastSeekError = nil
                            break
                        } catch {
                            lastSeekError = error
                            sonoicPlaybackDebugLog(
                                "cloudseek relativeFailed candidate=\(candidate.label) itemID=\(candidate.itemID.map(sonoicPlaybackDebugID) ?? "omitted") error='\(error.localizedDescription)'"
                            )
                            continue
                        }
                    }

                    if sonosControlAPIError(error, matchesStatus: 400, detailContains: "ERROR_INVALID_OBJECT_ID") {
                        sonoicPlaybackDebugLog(
                            "cloudseek invalidObject candidate=\(candidate.label) itemID=\(candidate.itemID.map(sonoicPlaybackDebugID) ?? "omitted")"
                        )
                        continue
                    }

                    throw error
                }
            }
            if let lastSeekError {
                throw lastSeekError
            }
            for attempt in 1 ... Self.sonosControlAPISeekPollAttempts {
                try await Task.sleep(for: Self.sonosControlAPISeekPollDelay)
                let observedStatus: SonosControlAPIPlaybackStatus
                do {
                    observedStatus = try await sonosControlAPIClient.playbackStatus(
                        groupID: context.groupID,
                        accessToken: context.accessToken
                    )
                } catch {
                    pollingErrorDetail = error.localizedDescription
                    sonoicPlaybackDebugLog(
                        "cloudseek pollFailed attempt=\(attempt) target=\(boundedElapsedTime) error='\(error.localizedDescription)'"
                    )
                    return
                }
                observedPlaybackState = observedStatus.playbackState
                observedElapsedTime = observedStatus.positionMillis.map { TimeInterval($0) / 1_000 }
                sonoicPlaybackDebugLog(
                    "cloudseek poll attempt=\(attempt) target=\(boundedElapsedTime) observed=\(String(describing: observedElapsedTime)) state=\(String(describing: observedPlaybackState)) itemID=\(sonoicPlaybackDebugID(observedStatus.itemId))"
                )
                if SonosSeekConfirmation.isConfirmed(
                    targetElapsedTime: boundedElapsedTime,
                    observedElapsedTime: observedElapsedTime,
                    requestedAt: requestedAt,
                    observedAt: .now,
                    playbackState: observedPlaybackState
                ) {
                    didConfirmSeek = true
                    return
                }
            }
        }

        if didSeek {
            if didConfirmSeek {
                clearManualSeekConfirmation()
                sonoicPlaybackDebugLog(
                    "cloudseek result=true confirmed=true target=\(boundedElapsedTime) observed=\(String(describing: observedElapsedTime)) state=\(String(describing: observedPlaybackState))"
                )
                recordSeekDiagnostics(
                    status: .succeeded,
                    host: "Sonos Control API",
                    target: boundedElapsedTime,
                    observed: observedElapsedTime,
                    errorDetail: nil
                )
                return true
            }
            sonoicPlaybackDebugLog(
                "cloudseek result=true accepted=true confirmed=false target=\(boundedElapsedTime) observed=\(String(describing: observedElapsedTime)) state=\(String(describing: observedPlaybackState))"
            )
            recordSeekDiagnostics(
                status: .succeeded,
                host: "Sonos Control API",
                target: boundedElapsedTime,
                observed: observedElapsedTime,
                errorDetail: pollingErrorDetail.map {
                    "Cloud accepted; status polling lagged: \($0)"
                } ?? "Cloud accepted; waiting for Sonos to report the requested position."
            )
            return true
        }

        clearManualSeekConfirmation()
        nowPlaying = previousNowPlaying
        nowPlayingObservedAt = previousObservedAt
        persistSharedExternalControlState()
        sonoicPlaybackDebugLog(
            "cloudseek result=false target=\(boundedElapsedTime) error='\(sonosControlAPIState.lastErrorDetail ?? "")'"
        )
        recordSeekDiagnostics(
            status: .failed,
            host: "Sonos Control API",
            target: boundedElapsedTime,
            observed: observedElapsedTime,
            errorDetail: sonosControlAPIState.lastErrorDetail
        )
        return false
    }

    private func waitForSonosControlAPISeekTransportSlot(target: TimeInterval) async -> Bool {
        guard isManualTransportCommandInFlight else {
            return true
        }

        sonoicPlaybackDebugLog("cloudseek waiting transportInFlight=true target=\(target)")
        for attempt in 1 ... Self.sonosControlAPISeekSlotWaitAttempts {
            try? await Task.sleep(for: Self.sonosControlAPISeekSlotWaitDelay)
            if !isManualTransportCommandInFlight {
                sonoicPlaybackDebugLog("cloudseek waitComplete attempt=\(attempt) target=\(target)")
                return true
            }
        }

        sonoicPlaybackDebugLog("cloudseek blocked transportInFlight=true target=\(target)")
        return false
    }

    private func sonosControlAPISeekItemIDCandidates(
        from status: SonosControlAPIPlaybackStatus
    ) -> [SonosControlAPISeekItemIDCandidate] {
        guard let statusItemID = status.itemId?.sonoicNonEmptyTrimmed else {
            return [SonosControlAPISeekItemIDCandidate(label: "omitted", itemID: nil)]
        }

        return [SonosControlAPISeekItemIDCandidate(label: "status", itemID: statusItemID)]
    }

    private func sonosControlAPICloudQueueSeekTarget(
        from status: SonosControlAPIPlaybackStatus
    ) -> (sessionID: String, itemID: String, track: SonosControlAPITrack?)? {
        guard let sessionID = sonosControlAPICloudQueueSessionID?.sonoicNonEmptyTrimmed,
              let itemIDs = sonosControlAPICloudQueueItemIDs,
              !itemIDs.isEmpty
        else {
            return nil
        }

        if let index = sonosControlAPICloudQueueCurrentIndex(from: status, itemIDs: itemIDs),
           itemIDs.indices.contains(index),
           let itemID = itemIDs[index].sonoicNonEmptyTrimmed
        {
            let track = sonosControlAPICloudQueueTracks.flatMap { tracks in
                tracks.indices.contains(index) ? tracks[index] : nil
            }
            return (sessionID, itemID, track)
        }

        return nil
    }

    private func sonosControlAPICloudQueueCurrentIndex(
        from status: SonosControlAPIPlaybackStatus,
        itemIDs: [String]
    ) -> Int? {
        if let statusItemID = status.itemId?.sonoicNonEmptyTrimmed {
            if let exactIndex = itemIDs.firstIndex(of: statusItemID) {
                return exactIndex
            }

            if let oneBasedIndex = Int(statusItemID),
               itemIDs.indices.contains(oneBasedIndex - 1)
            {
                return oneBasedIndex - 1
            }

            sonoicPlaybackDebugLog(
                "cloudseek sessionItemUnmapped rawItemID=\(sonoicPlaybackDebugID(statusItemID)) cloudQueueItems=\(itemIDs.count)"
            )
            return nil
        }

        if let currentIndex = queueState.snapshot?.currentItemIndex,
           itemIDs.indices.contains(currentIndex)
        {
            return currentIndex
        }

        if let payloadID = manualPlaybackContextPayload?.id,
           let payloads = manualQueueContextPayloads,
           let payloadIndex = payloads.firstIndex(where: { $0.id == payloadID }),
           itemIDs.indices.contains(payloadIndex)
        {
            return payloadIndex
        }

        return nil
    }

    func fetchSonosControlAPIActiveTargetVolume() async throws -> SonoicExternalControlState.Volume {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudVolume") else {
            throw SonosControlAPICommandUnavailableError()
        }

        if activeTarget.kind == .group {
            let volume = try await sonosControlAPIClient.groupVolume(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
            return sonoicExternalVolume(from: volume)
        }

        let playerID = try sonosControlAPIActivePlayerID()
        let volume = try await sonosControlAPIClient.playerVolume(
            playerID: playerID,
            accessToken: context.accessToken
        )
        return sonoicExternalVolume(from: volume)
    }

    func setSonosControlAPIActiveTargetVolume(to level: Int) async throws {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudVolume") else {
            throw SonosControlAPICommandUnavailableError()
        }

        if activeTarget.kind == .group {
            try await sonosControlAPIClient.setGroupVolume(
                groupID: context.groupID,
                level: level,
                accessToken: context.accessToken
            )
        } else {
            let playerID = try sonosControlAPIActivePlayerID()
            try await sonosControlAPIClient.setPlayerVolume(
                playerID: playerID,
                level: level,
                accessToken: context.accessToken
            )
        }
    }

    func setSonosControlAPIActiveTargetMute(_ isMuted: Bool) async throws {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudMute") else {
            throw SonosControlAPICommandUnavailableError()
        }

        if activeTarget.kind == .group {
            try await sonosControlAPIClient.setGroupMute(
                groupID: context.groupID,
                isMuted: isMuted,
                accessToken: context.accessToken
            )
        } else {
            let playerID = try sonosControlAPIActivePlayerID()
            try await sonosControlAPIClient.setPlayerMute(
                playerID: playerID,
                isMuted: isMuted,
                accessToken: context.accessToken
            )
        }
    }

    func fetchSonosControlAPIPlayerVolume(playerID: String) async throws -> SonoicExternalControlState.Volume {
        guard let tokenSet = await validSonosControlAPITokenSetForCommands(logPrefix: "cloudPlayerVolume") else {
            throw SonosControlAPICommandUnavailableError()
        }

        let volume = try await sonosControlAPIClient.playerVolume(
            playerID: playerID,
            accessToken: tokenSet.accessToken
        )
        return sonoicExternalVolume(from: volume)
    }

    func setSonosControlAPIPlayerVolume(playerID: String, to level: Int) async throws {
        guard let tokenSet = await validSonosControlAPITokenSetForCommands(logPrefix: "cloudPlayerVolume") else {
            throw SonosControlAPICommandUnavailableError()
        }

        try await sonosControlAPIClient.setPlayerVolume(
            playerID: playerID,
            level: level,
            accessToken: tokenSet.accessToken
        )
    }

    func setSonosControlAPIPlayerMute(playerID: String, isMuted: Bool) async throws {
        guard let tokenSet = await validSonosControlAPITokenSetForCommands(logPrefix: "cloudPlayerMute") else {
            throw SonosControlAPICommandUnavailableError()
        }

        try await sonosControlAPIClient.setPlayerMute(
            playerID: playerID,
            isMuted: isMuted,
            accessToken: tokenSet.accessToken
        )
    }

    private func sonosControlAPIActivePlayerID() throws -> String {
        if activeTarget.kind == .room,
           let activePlayerID = activeTarget.id.sonoicNonEmptyTrimmed
        {
            return activePlayerID
        }

        guard let target = activeSonosControlAPICommandTarget(requiresActiveTargetMatch: true),
              let playerID = (target.playerID ?? target.coordinatorPlayerID)?.sonoicNonEmptyTrimmed
        else {
            throw SonosControlAPICommandUnavailableError()
        }

        return playerID
    }

    private func sonoicExternalVolume(
        from volume: SonosControlAPIVolumeState
    ) -> SonoicExternalControlState.Volume {
        SonoicExternalControlState.Volume(
            level: min(max(volume.volume, 0), 100),
            isMuted: volume.muted
        )
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
            async let refreshedGroupVolume = sonosControlAPIClient.groupVolume(
                groupID: context.groupID,
                accessToken: context.accessToken
            )

            let playbackStatus = try await refreshedPlaybackStatus
            let metadataStatus = try await refreshedMetadataStatus
            updateSonosControlAPICloudQueueCurrentItem(itemID: playbackStatus.itemId)
            var nextNowPlaying = sonosControlAPINowPlayingSnapshot(
                playbackStatus: playbackStatus,
                metadataStatus: metadataStatus,
                fallback: nowPlaying
            )
            nextNowPlaying = smoothedNowPlayingSnapshot(nextNowPlaying, diagnostics: .empty)
            nextNowPlaying.artworkIdentifier = try? await syncArtworkIdentifier(for: nextNowPlaying)

            if nowPlaying != nextNowPlaying {
                nowPlaying = nextNowPlaying
            }

            if nowPlayingDiagnostics != .empty {
                nowPlayingDiagnostics = .empty
            }

            if let volumeState = try? await refreshedGroupVolume {
                let nextVolume = sonoicExternalVolume(from: volumeState)
                if externalVolume != nextVolume {
                    externalVolume = nextVolume
                }
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
        let track = metadataStatus.currentItem?.track
        let container = metadataStatus.container
        let title = track?.name?.sonoicNonEmptyTrimmed
            ?? metadataStatus.streamInfo?.sonoicNonEmptyTrimmed
            ?? fallback.title
        let artistName = track?.artist?.name.sonoicNonEmptyTrimmed
        let albumTitle = track?.album?.name.sonoicNonEmptyTrimmed
        let sourceName = track?.service?.name?.sonoicNonEmptyTrimmed
            ?? container?.service?.name?.sonoicNonEmptyTrimmed
            ?? fallback.sourceName
        let artworkURL = track?.imageUrl?.sonoicNonEmptyTrimmed
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
            duration: track?.durationMillis.map { TimeInterval($0) / 1_000 } ?? fallback.duration,
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

        if playbackStatus.playbackState != .playing || availableActions?.canPause != false {
            rawActions.insert("Play")
        }
        if availableActions?.canPause != false {
            rawActions.insert("Pause")
        }
        if availableActions?.canStop == true {
            rawActions.insert("Stop")
        }
        if availableActions?.canSeek == true && metadataStatus.currentItem?.track?.durationMillis != nil {
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

    private func sonosControlAPIError(
        _ error: Error,
        matchesStatus statusCode: Int,
        detailContains detailNeedle: String
    ) -> Bool {
        guard case let SonosControlAPITransport.TransportError.httpStatus(status, detail) = error else {
            return false
        }

        guard status == statusCode else {
            return false
        }

        return detail?.localizedCaseInsensitiveContains(detailNeedle) == true
    }

    func playSonosControlAPIFavoriteIfAvailable(_ favorite: SonosFavoriteItem) async -> Bool {
        sonoicPlaybackDebugLog(
            "cloudFavorite start title='\(favorite.title)' canSend=\(sonosControlAPIState.canSendCommands) auth=\(String(describing: sonosControlAPIState.authorizationStatus)) target=\(activeTarget.id)"
        )
        guard sonosControlAPIState.settings.mode.canSendCommands else {
            sonoicPlaybackDebugLog("cloudFavorite unavailable canSend=false title='\(favorite.title)'")
            return false
        }

        guard await hasValidSonosControlAPITokenForPlayback(logPrefix: "cloudFavorite") else {
            sonoicPlaybackDebugLog("cloudFavorite unavailable tokenInvalid title='\(favorite.title)'")
            return false
        }

        let snapshot: SonosControlAPICloudSnapshot
        if case let .verified(verifiedSnapshot) = sonosControlAPICloudState.status {
            snapshot = verifiedSnapshot
        } else {
            sonoicPlaybackDebugLog(
                "cloudFavorite refreshCloudSnapshot state=\(sonoicPlaybackDebugCloudStatus(sonosControlAPICloudState.status)) title='\(favorite.title)'"
            )
            refreshSonosControlAPIAuthorizationState()
            await refreshSonosControlAPICloudSnapshot()

            guard case let .verified(refreshedSnapshot) = sonosControlAPICloudState.status else {
                sonoicPlaybackDebugLog(
                    "cloudFavorite unavailable cloudState=\(sonoicPlaybackDebugCloudStatus(sonosControlAPICloudState.status)) title='\(favorite.title)'"
                )
                return false
            }

            sonoicPlaybackDebugLog(
                "cloudFavorite refreshedCloudSnapshot \(sonoicPlaybackDebugCloudStatus(sonosControlAPICloudState.status)) title='\(favorite.title)'"
            )
            snapshot = refreshedSnapshot
        }

        if let context = await sonosControlAPICommandContext(
            requiresActiveTargetMatch: true,
            logPrefix: "cloudFavorite"
        ),
           let householdID = context.householdID
        {
            sonoicPlaybackDebugLog(
                "cloudFavorite strictContext household=\(sonoicPlaybackDebugID(householdID)) group=\(sonoicPlaybackDebugID(context.groupID)) title='\(favorite.title)'"
            )
            return await loadMatchedSonosControlAPICloudContent(
                favorite,
                snapshot: snapshot,
                householdID: householdID,
                context: context
            ) ?? false
        }

        guard favorite.isPlaylistLike,
              let fallbackHouseholdID = sonosControlAPICloudContentFallbackHouseholdID(snapshot: snapshot),
              hasMatchedSonosControlAPICloudContent(
                  favorite,
                  snapshot: snapshot,
                  householdID: fallbackHouseholdID
              )
        else {
            sonoicPlaybackDebugLog(
                "cloudFavorite noStrictContextNoFallback title='\(favorite.title)' isPlaylistLike=\(favorite.isPlaylistLike)"
            )
            return false
        }

        sonoicPlaybackDebugLog(
            "cloudFavorite refreshingManualIdentity fallbackHousehold=\(sonoicPlaybackDebugID(fallbackHouseholdID)) title='\(favorite.title)'"
        )
        await refreshManualHostIdentityBeforeCloudContentPlaybackIfNeeded()

        guard let refreshedContext = await sonosControlAPICommandContext(
            requiresActiveTargetMatch: true,
            logPrefix: "cloudFavorite"
        ),
              case let .verified(refreshedSnapshot) = sonosControlAPICloudState.status,
              let refreshedHouseholdID = refreshedContext.householdID
        else {
            sonoicPlaybackDebugLog("cloudFavorite noRefreshedContext title='\(favorite.title)'")
            return false
        }

        sonoicPlaybackDebugLog(
            "cloudFavorite refreshedContext household=\(sonoicPlaybackDebugID(refreshedHouseholdID)) group=\(sonoicPlaybackDebugID(refreshedContext.groupID)) title='\(favorite.title)'"
        )
        return await loadMatchedSonosControlAPICloudContent(
            favorite,
            snapshot: refreshedSnapshot,
            householdID: refreshedHouseholdID,
            context: refreshedContext
        ) ?? false
    }

    private func refreshManualHostIdentityBeforeCloudContentPlaybackIfNeeded() async {
        guard activeTarget.id.hasPrefix("manual-host:") else {
            return
        }

        await refreshManualHostIdentityIfNeeded()
    }

    private func loadMatchedSonosControlAPICloudContent(
        _ favorite: SonosFavoriteItem,
        snapshot: SonosControlAPICloudSnapshot,
        householdID: String,
        context: SonosControlAPICommandContext
    ) async -> Bool? {
        sonoicPlaybackDebugLog(
            "cloudFavorite matchContent start title='\(favorite.title)' household=\(sonoicPlaybackDebugID(householdID)) favorites=\(snapshot.favoritesByHouseholdID[householdID]?.count ?? 0) playlists=\(snapshot.playlistsByHouseholdID[householdID]?.count ?? 0)"
        )
        if let cloudFavorite = snapshot.uniqueFavorite(
            matchingTitle: favorite.title,
            householdID: householdID,
            serviceName: favorite.service?.name
        ) {
            sonoicPlaybackDebugLog(
                "cloudFavorite matchedCloudFavorite title='\(favorite.title)' cloudID=\(sonoicPlaybackDebugID(cloudFavorite.id))"
            )
            return await loadSonosControlAPICloudFavorite(
                cloudFavorite,
                localFavorite: favorite,
                context: context
            )
        }

        if favorite.isPlaylistLike,
           let cloudPlaylist = snapshot.uniquePlaylist(
               matchingTitle: favorite.title,
               householdID: householdID
           )
        {
            sonoicPlaybackDebugLog(
                "cloudFavorite matchedCloudPlaylist title='\(favorite.title)' playlistID=\(sonoicPlaybackDebugID(cloudPlaylist.id))"
            )
            return await loadSonosControlAPICloudPlaylist(
                cloudPlaylist,
                localFavorite: favorite,
                context: context
            )
        }

        sonoicPlaybackDebugLog("cloudFavorite noCloudMatch title='\(favorite.title)'")
        return nil
    }

    private func hasMatchedSonosControlAPICloudContent(
        _ favorite: SonosFavoriteItem,
        snapshot: SonosControlAPICloudSnapshot,
        householdID: String
    ) -> Bool {
        if snapshot.uniqueFavorite(
            matchingTitle: favorite.title,
            householdID: householdID,
            serviceName: favorite.service?.name
        ) != nil {
            return true
        }

        return favorite.isPlaylistLike
            && snapshot.uniquePlaylist(matchingTitle: favorite.title, householdID: householdID) != nil
    }

    private func sonosControlAPICloudContentFallbackHouseholdID(
        snapshot: SonosControlAPICloudSnapshot
    ) -> String? {
        if let selectedHouseholdID = sonosControlAPIState.settings.selectedHouseholdID?.sonoicNonEmptyTrimmed {
            return selectedHouseholdID
        }

        guard snapshot.households.count == 1 else {
            return nil
        }

        return snapshot.households[0].id.sonoicNonEmptyTrimmed
    }

    private func hasValidSonosControlAPITokenForPlayback(logPrefix: String? = nil) async -> Bool {
        await validSonosControlAPITokenSetForCommands(logPrefix: logPrefix) != nil
    }

    private func sonosControlAPICommandContext(
        requiresActiveTargetMatch: Bool = false,
        logPrefix: String? = nil
    ) async -> SonosControlAPICommandContext? {
        guard sonosControlAPIState.settings.mode.canSendCommands else {
            return nil
        }

        let commandTarget = activeSonosControlAPICommandTarget(requiresActiveTargetMatch: requiresActiveTargetMatch)
        if requiresActiveTargetMatch && commandTarget == nil {
            return nil
        }

        let groupID = commandTarget?.groupID
            ?? sonosControlAPIState.settings.selectedGroupID?.sonoicNonEmptyTrimmed
        let householdID = commandTarget?.householdID
            ?? sonosControlAPIState.settings.selectedHouseholdID?.sonoicNonEmptyTrimmed

        guard let groupID else {
            return nil
        }

        guard let tokenSet = await validSonosControlAPITokenSetForCommands(logPrefix: logPrefix) else {
            return nil
        }

        return SonosControlAPICommandContext(
            householdID: householdID,
            groupID: groupID,
            accessToken: tokenSet.accessToken
        )
    }

    private func activeSonosControlAPICommandTarget(
        requiresActiveTargetMatch: Bool = false
    ) -> SonosControlAPITargetIdentity? {
        guard case let .verified(snapshot) = sonosControlAPICloudState.status else {
            return nil
        }

        if let activeTarget = snapshot.commandTarget(activeTargetID: activeTarget.id) {
            return activeTarget
        }

        guard !requiresActiveTargetMatch else {
            return nil
        }

        guard activeTarget.kind == .group else {
            return nil
        }

        return snapshot.selectedCommandTarget(settings: sonosControlAPIState.settings)
    }

    private func loadSonosControlAPICloudFavorite(
        _ cloudFavorite: SonosControlAPIFavorite,
        localFavorite: SonosFavoriteItem,
        context: SonosControlAPICommandContext
    ) async -> Bool {
        await loadSonosControlAPIContent(
            localFavorite: localFavorite,
            description: "Cloud favorite",
            action: {
                try await sonosControlAPIClient.loadFavorite(
                    groupID: context.groupID,
                    favoriteID: cloudFavorite.id,
                    accessToken: context.accessToken
                )
            }
        )
    }

    private func loadSonosControlAPICloudPlaylist(
        _ cloudPlaylist: SonosControlAPIPlaylist,
        localFavorite: SonosFavoriteItem,
        context: SonosControlAPICommandContext
    ) async -> Bool {
        await loadSonosControlAPIContent(
            localFavorite: localFavorite,
            description: "Cloud playlist",
            action: {
                try await sonosControlAPIClient.loadPlaylist(
                    groupID: context.groupID,
                    playlistID: cloudPlaylist.id,
                    accessToken: context.accessToken
                )
            }
        )
    }

    func skipSonosControlAPICloudQueueItemIfAvailable(at position: Int) async -> Bool {
        guard position > 0 else {
            return false
        }

        let index = position - 1
        guard let sessionID = sonosControlAPICloudQueueSessionID?.sonoicNonEmptyTrimmed,
              let itemIDs = sonosControlAPICloudQueueItemIDs,
              itemIDs.indices.contains(index),
              let itemID = itemIDs[index].sonoicNonEmptyTrimmed
        else {
            sonoicPlaybackDebugLog(
                "cloudQueueSkip unavailable position=\(position) session=\(sonoicPlaybackDebugID(sonosControlAPICloudQueueSessionID)) itemCount=\(sonosControlAPICloudQueueItemIDs?.count ?? 0)"
            )
            return false
        }

        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudQueueSkip") else {
            sonoicPlaybackDebugLog("cloudQueueSkip unavailable contextMissing position=\(position)")
            return false
        }

        let previousQueueState = queueState
        let previousNowPlaying = nowPlaying
        let previousNowPlayingObservedAt = nowPlayingObservedAt
        let previousPlaybackContextPayload = manualPlaybackContextPayload
        let payload = manualQueueContextPayloads.flatMap { $0.indices.contains(index) ? $0[index] : nil }
        let track = sonosControlAPICloudQueueTracks.flatMap { $0.indices.contains(index) ? $0[index] : nil }

        manualPlaybackContextPayload = payload
        beginManualPlayTransitionGrace()
        if let payload {
            markLocalNowPlaying(from: payload)
        } else {
            markLocalPlaybackState(.playing)
        }
        if let snapshot = sonosControlAPICloudQueueSnapshot(
            currentItemIndex: index,
            sourceURI: queueState.snapshot?.sourceURI
        ) {
            queueState = .loaded(snapshot)
        }

        let didSkip = await performSonosControlAPITransportCommand(
            description: "Cloud queue item",
            refreshQueueAfterSuccess: false
        ) {
            try await sonosControlAPIClient.skipToItem(
                sessionID: sessionID,
                itemID: itemID,
                queueVersion: sonosControlAPICloudQueueVersion,
                positionMillis: 0,
                playOnCompletion: true,
                trackMetadata: track,
                accessToken: context.accessToken
            )
        }

        if didSkip {
            updateSonosControlAPICloudQueueCurrentItem(itemID: itemID)
        } else {
            queueState = previousQueueState
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousNowPlayingObservedAt
            manualPlaybackContextPayload = previousPlaybackContextPayload
        }

        sonoicPlaybackDebugLog(
            "cloudQueueSkip result=\(didSkip) position=\(position) itemID=\(sonoicPlaybackDebugID(itemID))"
        )
        return didSkip
    }

    func playSonosControlAPICloudQueueIfAvailable(
        parentItem: SonoicSourceItem,
        plan: SonoicSourcePlaylistPlaybackPlan
    ) async -> Bool {
        sonoicPlaybackDebugLog(
            "cloudQueue start parent='\(parentItem.title)' itemCount=\(plan.items.count) payloadCount=\(plan.payloads.count) canSend=\(sonosControlAPIState.settings.mode.canSendCommands) configured=\(sonosOAuthConfiguration.canCreateCloudQueues)"
        )

        guard sonosOAuthConfiguration.canCreateCloudQueues else {
            sonoicPlaybackDebugLog("cloudQueue unavailable missingCreateURL parent='\(parentItem.title)'")
            return false
        }

        guard plan.items.count == plan.payloads.count,
              let request = sonosControlAPICloudQueueCreateRequest(parentItem: parentItem, plan: plan)
        else {
            sonoicPlaybackDebugLog("cloudQueue unavailable invalidPlan parent='\(parentItem.title)'")
            return false
        }

        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudQueue") else {
            sonoicPlaybackDebugLog(
                "cloudQueue unavailable contextMissing auth=\(String(describing: sonosControlAPIState.authorizationStatus)) mode=\(sonosControlAPIState.settings.mode.rawValue) selectedGroup=\(sonoicPlaybackDebugID(sonosControlAPIState.settings.selectedGroupID))"
            )
            return false
        }

        let previousQueueState = queueState
        let previousNowPlaying = nowPlaying
        let previousNowPlayingObservedAt = nowPlayingObservedAt
        let previousPlaybackContextPayload = manualPlaybackContextPayload
        let previousQueueContextPayloads = manualQueueContextPayloads
        let previousRecentPlaybackContextPayload = manualRecentPlaybackContextPayload
        let previousCloudQueueSessionID = sonosControlAPICloudQueueSessionID
        let previousCloudQueueVersion = sonosControlAPICloudQueueVersion
        let previousCloudQueueItemIDs = sonosControlAPICloudQueueItemIDs
        let previousCloudQueueTracks = sonosControlAPICloudQueueTracks
        let startIndex = max(0, min(plan.startingTrackNumber - 1, plan.payloads.count - 1))
        let confirmationPayload = plan.payloads[startIndex]
        let queueItemIDs = request.items.compactMap(\.id)
        let queueTracks = request.items.compactMap(\.track)

        if let snapshot = queueState.snapshot {
            queueState = .loaded(SonosQueueSnapshot(
                items: snapshot.items,
                currentItemIndex: nil,
                sourceURI: snapshot.sourceURI
            ))
        }

        beginManualPlayTransitionGrace()
        manualQueueContextPayloads = plan.payloads
        manualRecentPlaybackContextPayload = plan.recentPlaybackPayload
        manualPlaybackContextPayload = confirmationPayload
        sonosControlAPICloudQueueSessionID = nil
        sonosControlAPICloudQueueVersion = nil
        sonosControlAPICloudQueueItemIDs = queueItemIDs
        sonosControlAPICloudQueueTracks = queueTracks
        markLocalNowPlaying(from: plan.localNowPlayingPayload ?? confirmationPayload)

        let didLoad = await performSonosControlAPITransportCommand(
            description: "Cloud queue",
            refreshQueueAfterSuccess: false
        ) {
            let cloudQueue = try await sonoicCloudQueueClient.createQueue(
                request,
                configuration: sonosOAuthConfiguration,
                accessToken: context.accessToken
            )
            let sessionStatus = try await sonosControlAPIClient.createPlaybackSession(
                groupID: context.groupID,
                appID: "Sonoic",
                appContext: parentItem.title,
                accountID: nil,
                customData: parentItem.id,
                accessToken: context.accessToken
            )
            guard let sessionID = sessionStatus.sessionId?.sonoicNonEmptyTrimmed else {
                throw SonosControlAPITransport.TransportError.invalidResponse
            }
            sonoicPlaybackDebugLog(
                "cloudQueue load session=\(sonoicPlaybackDebugID(sessionID)) queue=\(sonoicPlaybackDebugID(cloudQueue.queueId)) startItem=\(sonoicPlaybackDebugID(cloudQueue.startItemId))"
            )
            try await sonosControlAPIClient.loadCloudQueue(
                sessionID: sessionID,
                request: SonosControlAPILoadCloudQueueRequest(
                    queueBaseUrl: cloudQueue.queueBaseUrl,
                    httpAuthorization: nil,
                    useHttpAuthorizationForMedia: nil,
                    itemId: cloudQueue.startItemId,
                    queueVersion: cloudQueue.queueVersion,
                    positionMillis: 0,
                    playOnCompletion: true,
                    trackMetadata: cloudQueue.trackMetadata
                ),
                accessToken: context.accessToken
            )
            sonosControlAPICloudQueueSessionID = sessionID
            sonosControlAPICloudQueueVersion = cloudQueue.queueVersion
            sonosControlAPICloudQueueItemIDs = queueItemIDs
            sonosControlAPICloudQueueTracks = queueTracks
            if let snapshot = sonosControlAPICloudQueueSnapshot(
                currentItemIndex: startIndex,
                sourceURI: "sonoic-cloud-queue:\(cloudQueue.queueId)"
            ) {
                queueState = .loaded(snapshot)
                queueDiagnostics = SonosQueueDiagnostics(
                    observedAt: Date(),
                    currentURI: snapshot.sourceURI,
                    itemCount: snapshot.items.count,
                    lastRefreshErrorDetail: nil,
                    lastMutationErrorDetail: queueDiagnostics.lastMutationErrorDetail
                )
            }
        }

        if !didLoad {
            queueState = previousQueueState
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousNowPlayingObservedAt
            manualPlaybackContextPayload = previousPlaybackContextPayload
            manualQueueContextPayloads = previousQueueContextPayloads
            manualRecentPlaybackContextPayload = previousRecentPlaybackContextPayload
            sonosControlAPICloudQueueSessionID = previousCloudQueueSessionID
            sonosControlAPICloudQueueVersion = previousCloudQueueVersion
            sonosControlAPICloudQueueItemIDs = previousCloudQueueItemIDs
            sonosControlAPICloudQueueTracks = previousCloudQueueTracks
        }

        sonoicPlaybackDebugLog(
            "cloudQueue result=\(didLoad) parent='\(parentItem.title)'"
        )
        return didLoad
    }

    private func sonosControlAPICloudQueueCreateRequest(
        parentItem: SonoicSourceItem,
        plan: SonoicSourcePlaylistPlaybackPlan
    ) -> SonoicCloudQueueCreateRequest? {
        var queueItems: [SonosControlAPIQueueItem] = []
        var seenItemIDs: Set<String> = []

        for (index, pair) in zip(plan.items, plan.payloads).enumerated() {
            guard let objectID = sonosControlAPIObjectID(for: pair.1, item: pair.0),
                  let contentType = sonosControlAPIContentType(for: pair.1.uri)
            else {
                return nil
            }

            var queueItemID = sonosControlAPICloudQueueItemID(index: index, objectID: objectID, item: pair.0)
            if seenItemIDs.contains(queueItemID) {
                queueItemID = "\(queueItemID)-\(index + 1)"
            }
            seenItemIDs.insert(queueItemID)

            queueItems.append(SonosControlAPIQueueItem(
                id: queueItemID,
                track: sonosControlAPITrack(
                    item: pair.0,
                    payload: pair.1,
                    objectID: objectID,
                    contentType: contentType,
                    trackNumber: index + 1
                ),
                deleted: nil,
                policies: sonosControlAPICloudQueuePlaybackPolicy()
            ))
        }

        guard !queueItems.isEmpty else {
            return nil
        }

        let startIndex = max(0, min(plan.startingTrackNumber - 1, queueItems.count - 1))
        return SonoicCloudQueueCreateRequest(
            container: sonosControlAPIContainer(for: parentItem),
            items: queueItems,
            startItemId: queueItems[startIndex].id
        )
    }

    private func sonosControlAPIContainer(for item: SonoicSourceItem) -> SonosControlAPIContainer {
        SonosControlAPIContainer(
            name: item.title,
            type: item.kind.rawValue,
            id: sonosControlAPICollectionObjectID(for: item).map(sonosControlAPIUniversalMusicObjectID),
            service: sonosControlAPIAppleMusicService(for: item),
            imageUrl: item.artworkURL?.sonoicNonEmptyTrimmed
        )
    }

    private func sonosControlAPITrack(
        item: SonoicSourceItem,
        payload: SonosPlayablePayload,
        objectID: String,
        contentType: String,
        trackNumber: Int
    ) -> SonosControlAPITrack {
        let subtitleParts = sonosControlAPISubtitleParts(from: item.subtitle ?? payload.subtitle)
        let artist = subtitleParts.first.map { SonosControlAPIArtist(name: $0, id: nil) }
        let albumName = subtitleParts.dropFirst().first
        return SonosControlAPITrack(
            type: "track",
            name: item.title,
            mediaUrl: nil,
            imageUrl: item.artworkURL?.sonoicNonEmptyTrimmed ?? payload.artworkURL?.sonoicNonEmptyTrimmed,
            contentType: contentType,
            album: albumName.map { SonosControlAPIAlbum(name: $0, artist: artist, id: nil) },
            artist: artist,
            id: sonosControlAPIUniversalMusicObjectID(objectID),
            service: sonosControlAPIAppleMusicService(for: item),
            durationMillis: sonosControlAPIDurationMillis(item.duration ?? payload.duration),
            trackNumber: trackNumber,
            quality: nil
        )
    }

    private func sonosControlAPICloudQueuePlaybackPolicy() -> SonosControlAPIPlaybackPolicy {
        SonosControlAPIPlaybackPolicy(
            canSkip: true,
            canSkipBack: true,
            limitedSkips: false,
            canSeek: true,
            canSkipToItem: true,
            canRepeat: true,
            canRepeatOne: true,
            canCrossfade: true,
            canShuffle: true,
            canResume: true,
            pauseAtEndOfQueue: false,
            refreshAuthWhilePaused: false,
            showNNextTracks: nil,
            showNPreviousTracks: nil,
            isVisible: true,
            notifyUserIntent: true,
            pauseTtlSec: nil
        )
    }

    private func sonosControlAPIAppleMusicService(for item: SonoicSourceItem) -> SonosControlAPIService? {
        guard item.service.kind == .appleMusic else {
            return nil
        }

        return SonosControlAPIService(
            id: item.service.sonosServiceID ?? "204",
            name: item.service.name,
            imageUrl: nil
        )
    }

    private func sonosControlAPIUniversalMusicObjectID(_ objectID: String) -> SonosControlAPIUniversalMusicObjectID {
        SonosControlAPIUniversalMusicObjectID(
            serviceId: SonosServiceDescriptor.appleMusic.sonosServiceID ?? "204",
            objectId: objectID,
            accountId: nil
        )
    }

    private func sonosControlAPIObjectID(
        for payload: SonosPlayablePayload,
        item: SonoicSourceItem
    ) -> String? {
        sonosControlAPIObjectID(from: payload.uri)
            ?? sonosControlAPIObjectID(from: item.sourceReference)
            ?? item.serviceItemID?.sonoicNonEmptyTrimmed.map { "song:\($0)" }
    }

    private func sonosControlAPICollectionObjectID(for item: SonoicSourceItem) -> String? {
        guard let reference = item.sourceReference else {
            return nil
        }

        let rawID = reference.libraryID?.sonoicNonEmptyTrimmed
            ?? reference.catalogID?.sonoicNonEmptyTrimmed
            ?? item.serviceItemID?.sonoicNonEmptyTrimmed
        guard let rawID else {
            return nil
        }

        switch item.kind {
        case .album:
            return "album:\(rawID)"
        case .artist:
            return "artist:\(rawID)"
        case .playlist:
            return "playlist:\(rawID)"
        case .song:
            return "song:\(rawID)"
        case .station:
            return "station:\(rawID)"
        case .unknown:
            return rawID
        }
    }

    private func sonosControlAPIObjectID(from reference: SonoicSourceItemReference?) -> String? {
        guard let reference else {
            return nil
        }

        if let libraryID = reference.libraryID?.sonoicNonEmptyTrimmed {
            return "librarytrack:\(libraryID)"
        }

        if let catalogID = reference.catalogID?.sonoicNonEmptyTrimmed {
            switch reference.kind {
            case .album:
                return "album:\(catalogID)"
            case .artist:
                return "artist:\(catalogID)"
            case .playlist:
                return "playlist:\(catalogID)"
            case .song:
                return "song:\(catalogID)"
            case .station:
                return "station:\(catalogID)"
            case .unknown:
                return catalogID
            }
        }

        return nil
    }

    private func sonosControlAPIObjectID(from uri: String) -> String? {
        let normalizedURI = uri.replacingOccurrences(of: "&amp;", with: "&")
        let lowercasedURI = normalizedURI.lowercased()
        let prefixes = [
            "x-sonosapi-hls-static:",
            "x-sonosapi-hls:",
            "x-sonos-http:",
        ]

        guard let prefix = prefixes.first(where: { lowercasedURI.hasPrefix($0) }) else {
            return nil
        }

        let startIndex = normalizedURI.index(normalizedURI.startIndex, offsetBy: prefix.count)
        guard let encodedObjectID = normalizedURI[startIndex...]
            .split(separator: "?", maxSplits: 1)
            .first
            .map(String.init),
            var objectID = encodedObjectID.removingPercentEncoding?.sonoicNonEmptyTrimmed
        else {
            return nil
        }

        if objectID.hasSuffix(".m4p") {
            objectID.removeLast(4)
        }

        return objectID
    }

    private func sonosControlAPIContentType(for uri: String) -> String? {
        let normalizedURI = uri.replacingOccurrences(of: "&amp;", with: "&").lowercased()
        if normalizedURI.hasPrefix("x-sonosapi-hls:") || normalizedURI.hasPrefix("x-sonosapi-hls-static:") {
            return "application/vnd.apple.mpegurl"
        }

        if normalizedURI.hasPrefix("x-sonos-http:") {
            return "audio/mp4"
        }

        return nil
    }

    private func sonosControlAPICloudQueueItemID(
        index: Int,
        objectID: String,
        item: SonoicSourceItem
    ) -> String {
        let rawValue = "sonoic-\(index + 1)-\(objectID)-\(item.id)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        let sanitizedScalars = rawValue.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(sanitizedScalars)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .sonoicTrimmed
        return String(sanitized.prefix(128))
    }

    private func sonosControlAPISubtitleParts(from subtitle: String?) -> [String] {
        subtitle?
            .components(separatedBy: "•")
            .map(\.sonoicTrimmed)
            .filter { !$0.isEmpty } ?? []
    }

    private func sonosControlAPIDurationMillis(_ duration: TimeInterval?) -> Int? {
        guard let duration,
              duration.isFinite,
              duration > 0
        else {
            return nil
        }

        return Int((duration * 1_000).rounded())
    }

    private func loadSonosControlAPIContent(
        localFavorite: SonosFavoriteItem,
        description: String,
        action: () async throws -> Void
    ) async -> Bool {
        sonoicPlaybackDebugLog("cloudFavorite loadStart description='\(description)' title='\(localFavorite.title)'")
        let previousQueueState = queueState
        let previousNowPlaying = nowPlaying
        let previousNowPlayingObservedAt = nowPlayingObservedAt
        let previousPlaybackContextPayload = manualPlaybackContextPayload
        let previousQueueContextPayloads = manualQueueContextPayloads
        let previousRecentPlaybackContextPayload = manualRecentPlaybackContextPayload
        let previousCloudQueueSessionID = sonosControlAPICloudQueueSessionID
        let previousCloudQueueVersion = sonosControlAPICloudQueueVersion
        let previousCloudQueueItemIDs = sonosControlAPICloudQueueItemIDs
        let previousCloudQueueTracks = sonosControlAPICloudQueueTracks

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
        if let payload = localFavorite.playablePayload {
            manualPlaybackContextPayload = payload
            markLocalNowPlaying(from: payload)
        } else {
            manualPlaybackContextPayload = nil
            markLocalCloudFavoriteNowPlaying(from: localFavorite)
        }

        let didLoad = await performSonosControlAPITransportCommand(
            description: description,
            refreshQueueAfterSuccess: true
        ) {
            try await action()
        }

        if didLoad {
            recordRecentFavoritePlayback(localFavorite)
        } else {
            queueState = previousQueueState
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousNowPlayingObservedAt
            manualPlaybackContextPayload = previousPlaybackContextPayload
            manualQueueContextPayloads = previousQueueContextPayloads
            manualRecentPlaybackContextPayload = previousRecentPlaybackContextPayload
            sonosControlAPICloudQueueSessionID = previousCloudQueueSessionID
            sonosControlAPICloudQueueVersion = previousCloudQueueVersion
            sonosControlAPICloudQueueItemIDs = previousCloudQueueItemIDs
            sonosControlAPICloudQueueTracks = previousCloudQueueTracks
        }

        sonoicPlaybackDebugLog(
            "cloudFavorite loadResult=\(didLoad) description='\(description)' title='\(localFavorite.title)'"
        )
        return didLoad
    }

    private func markLocalCloudFavoriteNowPlaying(from favorite: SonosFavoriteItem) {
        let subtitleParts = favorite.subtitle?
            .components(separatedBy: " • ")
            .map(\.sonoicTrimmed)
            .filter { !$0.isEmpty } ?? []

        nowPlaying = SonosNowPlayingSnapshot(
            title: favorite.title,
            artistName: subtitleParts.first,
            albumTitle: subtitleParts.dropFirst().first,
            sourceName: favorite.service?.name ?? nowPlaying.sourceName,
            playbackState: .playing,
            artworkURL: favorite.artworkURL,
            artworkIdentifier: nil,
            elapsedTime: 0,
            duration: nil,
            transportActions: nowPlaying.transportActions
        )
    }

    private func performSonosControlAPITransportCommand(
        description: String,
        refreshQueueAfterSuccess: Bool,
        syncDelay: Duration? = nil,
        _ action: () async throws -> Void
    ) async -> Bool {
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
            recordSonosControlAPICommand(description)
            scheduleManualStateSync(
                after: syncDelay ?? Self.sonosControlAPITransportSyncDelay,
                restartRefreshLoop: true,
                refreshQueueAfterSync: refreshQueueAfterSuccess
            )
            return true
        } catch {
            manualPlayTransitionGraceDeadline = nil
            setManualPlayTransitionAwaitingConfirmation(false)
            clearManualSeekConfirmation()
            recordSonosControlAPIError(error)
            if isSonosControlAPIAuthorizationFailure(error) {
                sonosControlAPIState.authorizationStatus = .expired
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
            }
            manualHostRefreshStatus = .failed(error.localizedDescription)
            startManualHostRefreshLoopIfPossible()
            return false
        }
    }

    private func isSonosControlAPIAuthorizationFailure(_ error: Error) -> Bool {
        guard let transportError = error as? SonosControlAPITransport.TransportError else {
            return false
        }

        return transportError.isAuthorizationFailure
    }
}

private enum SonosControlAPISeekFailure: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "Sonos reported that the current item cannot seek."
        }
    }
}
