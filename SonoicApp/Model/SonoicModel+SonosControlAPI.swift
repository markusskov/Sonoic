import Foundation

extension SonoicModel {
    private static let sonosControlAPITransportSyncDelay: Duration = .milliseconds(350)
    private static let sonosControlAPISeekPollDelay: Duration = .milliseconds(350)
    private static let sonosControlAPISeekPollAttempts = 5
    private static let sonosControlAPISeekSlotWaitDelay: Duration = .milliseconds(100)
    private static let sonosControlAPISeekSlotWaitAttempts = 36

    struct SonosControlAPICommandContext {
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
        clearSonosControlAPIPlaybackContextAfterAuthorizationLoss()
    }

    func clearSonosControlAPIPlaybackContextAfterAuthorizationLoss() {
        let queueSnapshotIsCloudOwned = queueState.snapshot?.sourceURI?
            .lowercased()
            .hasPrefix("sonoic-cloud-queue") == true
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

        if settings.mode == .off {
            settings.mode = .preferred
            didChangeSettings = true
        }

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

            if let nextActiveTarget = sonosActiveTarget(from: target, snapshot: snapshot) {
                if activeTarget != nextActiveTarget {
                    sonoicPlaybackDebugLog(
                        "cloudSnapshot activeTarget name='\(nextActiveTarget.name)' id=\(sonoicPlaybackDebugID(nextActiveTarget.id)) group=\(sonoicPlaybackDebugID(target.groupID)) household=\(sonoicPlaybackDebugID(target.householdID))"
                    )
                    activeTarget = nextActiveTarget
                }

                if nowPlaying.isIdlePlaceholder {
                    nowPlaying = .connectedIdle(targetName: nextActiveTarget.name)
                }
            }

            manualHostIdentityStatus = .resolved
            manualHostTopologyStatus = .resolved
        }

        if didChangeSettings {
            updateSonosControlAPISettings(settings)
        }
    }

    private func sonosActiveTarget(
        from target: SonosControlAPITargetIdentity,
        snapshot: SonosControlAPICloudSnapshot
    ) -> SonosActiveTarget? {
        guard let groupSnapshot = snapshot.groupsByHouseholdID[target.householdID],
              let group = groupSnapshot.groups.first(where: { $0.id == target.groupID })
        else {
            return nil
        }

        let playersByID = Dictionary(uniqueKeysWithValues: groupSnapshot.players.map { ($0.id, $0) })
        let groupedPlayers = group.playerIds.compactMap { playersByID[$0] }
        let memberNames = groupedPlayers
            .map { player in
                player.roomName?.sonoicNonEmptyTrimmed
                    ?? player.name?.sonoicNonEmptyTrimmed
                    ?? player.id
            }
        let fallbackName = group.name?.sonoicNonEmptyTrimmed
            ?? memberNames.first
            ?? groupedPlayers.first?.name?.sonoicNonEmptyTrimmed
            ?? "Sonos"
        let primaryPlayer = target.coordinatorPlayerID
            .flatMap { playersByID[$0] }
            ?? target.playerID.flatMap { playersByID[$0] }
            ?? groupedPlayers.first
        let localRoomMetadata = localDiscoveredPlayerMatchingCloudRoom(
            roomName: primaryPlayer?.roomName ?? fallbackName,
            productName: primaryPlayer?.name
        )
        let primaryProductName = localRoomMetadata?.modelName?.sonoicNonEmptyTrimmed
            ?? primaryPlayer?.name?.sonoicNonEmptyTrimmed
            ?? primaryPlayer?.roomName?.sonoicNonEmptyTrimmed
            ?? "Sonos"
        let bondedAccessories = localRoomMetadata?.bondedAccessories ?? []
        let kind: SonosActiveTarget.Kind = groupedPlayers.count > 1 ? .group : .room
        let activeTargetID = kind == .group
            ? group.id
            : (primaryPlayer?.id ?? target.playerID ?? group.id)

        return SonosActiveTarget(
            id: activeTargetID,
            name: fallbackName,
            householdName: primaryProductName,
            kind: kind,
            memberNames: memberNames.isEmpty ? [fallbackName] : memberNames,
            bondedAccessories: bondedAccessories
        )
    }

    private func localDiscoveredPlayerMatchingCloudRoom(
        roomName: String?,
        productName: String?
    ) -> SonosDiscoveredPlayer? {
        let normalizedRoomName = roomName?.sonoicNonEmptyTrimmed?.localizedLowercase
        let normalizedProductName = productName?.sonoicNonEmptyTrimmed?.localizedLowercase

        return discoveredPlayers.first { player in
            let discoveredName = player.name.localizedLowercase
            let discoveredModel = player.modelName?.sonoicNonEmptyTrimmed?.localizedLowercase
            return discoveredName == normalizedRoomName
                || discoveredModel == normalizedProductName
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
        let previousNowPlayingObservedAt = nowPlayingObservedAt
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
            nowPlayingObservedAt = previousNowPlayingObservedAt
            persistSharedExternalControlState()
        }

        return didPlay
    }

    func pauseSonosControlAPIPlaybackIfAvailable() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudPause") else {
            return false
        }

        let previousNowPlaying = nowPlaying
        let previousNowPlayingObservedAt = nowPlayingObservedAt
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
            nowPlayingObservedAt = previousNowPlayingObservedAt
            persistSharedExternalControlState()
        }

        return didPause
    }

    func skipToNextSonosControlAPITrackIfAvailable() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudNext") else {
            return false
        }

        let previousNowPlaying = nowPlaying
        let previousNowPlayingObservedAt = nowPlayingObservedAt
        let previousPlaybackContextPayload = manualPlaybackContextPayload
        manualPlaybackContextPayload = nil
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }

        let didSkip = await performSonosControlAPITransportCommand(
            description: "Cloud next",
            refreshQueueAfterSuccess: true
        ) {
            try await sonosControlAPIClient.skipToNextTrack(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }

        if !didSkip {
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousNowPlayingObservedAt
            manualPlaybackContextPayload = previousPlaybackContextPayload
            persistSharedExternalControlState()
        }

        return didSkip
    }

    func skipToPreviousSonosControlAPITrackIfAvailable() async -> Bool {
        guard let context = await sonosControlAPICommandContext(logPrefix: "cloudPrevious") else {
            return false
        }

        let previousNowPlaying = nowPlaying
        let previousNowPlayingObservedAt = nowPlayingObservedAt
        let previousPlaybackContextPayload = manualPlaybackContextPayload
        manualPlaybackContextPayload = nil
        if nowPlaying.playbackState == .playing || nowPlaying.playbackState == .buffering {
            beginManualPlayTransitionGrace()
            markLocalPlaybackState(.playing)
        }

        let didSkip = await performSonosControlAPITransportCommand(
            description: "Cloud previous",
            refreshQueueAfterSuccess: true
        ) {
            try await sonosControlAPIClient.skipToPreviousTrack(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
        }

        if !didSkip {
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousNowPlayingObservedAt
            manualPlaybackContextPayload = previousPlaybackContextPayload
            persistSharedExternalControlState()
        }

        return didSkip
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
            let metadataStatus = try? await sonosControlAPIClient.playbackMetadata(
                groupID: context.groupID,
                accessToken: context.accessToken
            )
            if status.availablePlaybackActions?.canSeek == false {
                throw SonosControlAPISeekFailure.unsupported
            }
            if metadataStatus?.currentItem?.policies?.canSeek == false {
                throw SonosControlAPISeekFailure.unsupported
            }
            sonoicPlaybackDebugLog(
                "cloudseek status canSeek=\(String(describing: status.availablePlaybackActions?.canSeek)) itemID=\(sonoicPlaybackDebugID(status.itemId)) metadataItemID=\(sonoicPlaybackDebugID(metadataStatus?.currentItem?.id)) positionMillis=\(String(describing: status.positionMillis))"
            )
            let didRestoreCloudQueueContext = restoreSonosControlAPICloudQueueContextIfNeeded(
                groupID: context.groupID,
                queueVersion: status.queueVersion
            )
            sonoicPlaybackDebugLog(
                "cloudseek cloudQueueContext restored=\(didRestoreCloudQueueContext) session=\(sonoicPlaybackDebugID(sonosControlAPICloudQueueSessionID)) itemCount=\(sonosControlAPICloudQueueItemIDs?.count ?? 0) rawItemID=\(sonoicPlaybackDebugID(status.itemId)) queueVersion=\(sonoicPlaybackDebugID(status.queueVersion))"
            )
            let itemIDCandidates = sonosControlAPISeekItemIDCandidates(from: status)
            sonoicPlaybackDebugLog(
                "cloudseek seekPayload candidates=\(itemIDCandidates.map { "\($0.label):\($0.itemID.map(sonoicPlaybackDebugID) ?? "omitted")" }.joined(separator: ",")) rawItemID=\(sonoicPlaybackDebugID(status.itemId))"
            )
            requestedAt = Date()
            let targetMillis = Int((boundedElapsedTime * 1_000).rounded())
            if let sessionSeekTarget = sonosControlAPICloudQueueSeekTarget(
                from: status,
                metadataStatus: metadataStatus
            ) {
                sonoicPlaybackDebugLog(
                    "cloudseek sessionSeek itemID=\(sonoicPlaybackDebugID(sessionSeekTarget.itemID)) session=\(sonoicPlaybackDebugID(sessionSeekTarget.sessionID)) targetMillis=\(targetMillis)"
                )
                try await sonosControlAPIClient.seekPlaybackSession(
                    sessionID: sessionSeekTarget.sessionID,
                    itemID: sessionSeekTarget.itemID,
                    positionMillis: targetMillis,
                    accessToken: context.accessToken
                )
                try await confirmSonosControlAPISeek(
                    groupID: context.groupID,
                    accessToken: context.accessToken,
                    targetElapsedTime: boundedElapsedTime,
                    requestedAt: requestedAt,
                    observedElapsedTime: &observedElapsedTime,
                    observedPlaybackState: &observedPlaybackState,
                    didConfirmSeek: &didConfirmSeek,
                    pollingErrorDetail: &pollingErrorDetail
                )
                return
            }

            if sonosControlAPIHasCloudQueueContext {
                sonoicPlaybackDebugLog(
                    "cloudseek sessionContextUnmapped sessionSeekRequired rawItemID=\(sonoicPlaybackDebugID(status.itemId)) metadataItemID=\(sonoicPlaybackDebugID(metadataStatus?.currentItem?.id)) session=\(sonoicPlaybackDebugID(sonosControlAPICloudQueueSessionID)) itemCount=\(sonosControlAPICloudQueueItemIDs?.count ?? 0)"
                )
                throw SonosControlAPISeekFailure.sessionItemUnavailable
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
                    if sonosControlAPIError(error, matchesStatus: 499, detailContains: "ERROR_DISALLOWED_BY_POLICY") {
                        sonoicPlaybackDebugLog(
                            "cloudseek disallowedByPolicy currentMillis=\(String(describing: status.positionMillis)) targetMillis=\(targetMillis) candidate=\(candidate.label) itemID=\(candidate.itemID.map(sonoicPlaybackDebugID) ?? "omitted")"
                        )
                        throw error
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
            try await confirmSonosControlAPISeek(
                groupID: context.groupID,
                accessToken: context.accessToken,
                targetElapsedTime: boundedElapsedTime,
                requestedAt: requestedAt,
                observedElapsedTime: &observedElapsedTime,
                observedPlaybackState: &observedPlaybackState,
                didConfirmSeek: &didConfirmSeek,
                pollingErrorDetail: &pollingErrorDetail
            )
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

    private func confirmSonosControlAPISeek(
        groupID: String,
        accessToken: String,
        targetElapsedTime: TimeInterval,
        requestedAt: Date,
        observedElapsedTime: inout TimeInterval?,
        observedPlaybackState: inout SonosControlAPIPlaybackState?,
        didConfirmSeek: inout Bool,
        pollingErrorDetail: inout String?
    ) async throws {
        for attempt in 1 ... Self.sonosControlAPISeekPollAttempts {
            try await Task.sleep(for: Self.sonosControlAPISeekPollDelay)
            let observedStatus: SonosControlAPIPlaybackStatus
            do {
                observedStatus = try await sonosControlAPIClient.playbackStatus(
                    groupID: groupID,
                    accessToken: accessToken
                )
            } catch {
                pollingErrorDetail = error.localizedDescription
                sonoicPlaybackDebugLog(
                    "cloudseek pollFailed attempt=\(attempt) target=\(targetElapsedTime) error='\(error.localizedDescription)'"
                )
                return
            }
            observedPlaybackState = observedStatus.playbackState
            observedElapsedTime = observedStatus.positionMillis.map { TimeInterval($0) / 1_000 }
            sonoicPlaybackDebugLog(
                "cloudseek poll attempt=\(attempt) target=\(targetElapsedTime) observed=\(String(describing: observedElapsedTime)) state=\(String(describing: observedPlaybackState)) itemID=\(sonoicPlaybackDebugID(observedStatus.itemId))"
            )
            if SonosSeekConfirmation.isConfirmed(
                targetElapsedTime: targetElapsedTime,
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

        guard Int(statusItemID) == nil else {
            return [SonosControlAPISeekItemIDCandidate(label: "omitted", itemID: nil)]
        }

        return [
            SonosControlAPISeekItemIDCandidate(label: "status", itemID: statusItemID),
            SonosControlAPISeekItemIDCandidate(label: "omitted", itemID: nil)
        ]
    }

    private func sonosControlAPICloudQueueSeekTarget(
        from status: SonosControlAPIPlaybackStatus,
        metadataStatus: SonosControlAPIMetadataStatus?
    ) -> (sessionID: String, itemID: String, track: SonosControlAPITrack?)? {
        guard let sessionID = sonosControlAPICloudQueueSessionID?.sonoicNonEmptyTrimmed,
              let itemIDs = sonosControlAPICloudQueueItemIDs,
              !itemIDs.isEmpty
        else {
            return nil
        }

        if let index = sonosControlAPICloudQueueCurrentIndex(
            from: status,
            metadataStatus: metadataStatus,
            itemIDs: itemIDs
        ),
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

    private var sonosControlAPIHasCloudQueueContext: Bool {
        guard sonosControlAPICloudQueueSessionID?.sonoicNonEmptyTrimmed != nil,
              sonosControlAPICloudQueueItemIDs?.isEmpty == false
        else {
            return false
        }

        return true
    }

    private func sonosControlAPICloudQueueCurrentIndex(
        from status: SonosControlAPIPlaybackStatus,
        metadataStatus: SonosControlAPIMetadataStatus?,
        itemIDs: [String]
    ) -> Int? {
        SonoicSonosControlAPIQueueCurrentIndexResolver.currentIndex(
            itemIDs: itemIDs,
            candidates: [
                status.itemId,
                metadataStatus?.currentItem?.id,
                queueState.snapshot?.currentItemIndex.map { String($0 + 1) },
                manualPlaybackContextPayload.flatMap { payload in
                    manualQueueContextPayloads?.firstIndex { $0.id == payload.id }.map {
                        String($0 + 1)
                    }
                }
            ]
        )
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
            sonosControlAPICloudQueueTracks.flatMap { $0.indices.contains(index) ? $0[index] : nil }
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
           let durationMillis = sonosControlAPICloudQueueTracks.flatMap({ tracks in
            tracks.indices.contains(cloudQueueIndex) ? tracks[cloudQueueIndex].durationMillis : nil
           }),
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

    func sonosControlAPICommandContext(
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

        let serviceAccount = sonosControlAPICloudQueueAccountID(for: parentItem)
        let serviceAccountID: String? = nil
        sonoicPlaybackDebugLog(
            "cloudQueue accountID=omitted rawAccountID=\(sonoicPlaybackDebugID(serviceAccount?.raw)) parent='\(parentItem.title)'"
        )
        guard plan.items.count == plan.payloads.count,
              let request = sonosControlAPICloudQueueCreateRequest(
                parentItem: parentItem,
                plan: plan,
                accountID: serviceAccountID
              )
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
        let previousCloudQueueGroupID = sonosControlAPICloudQueueGroupID
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
        sonosControlAPICloudQueueGroupID = context.groupID
        sonosControlAPICloudQueueVersion = nil
        sonosControlAPICloudQueueItemIDs = queueItemIDs
        sonosControlAPICloudQueueTracks = queueTracks
        markLocalNowPlaying(from: plan.localNowPlayingPayload ?? confirmationPayload)

        let didLoad = await performSonosControlAPITransportCommand(
            description: "Cloud queue",
            refreshQueueAfterSuccess: false
        ) {
            sonoicPlaybackDebugLog(
                "cloudQueue createQueue start parent='\(parentItem.title)' items=\(request.items.count) startItem=\(sonoicPlaybackDebugID(request.startItemId)) accountID=\(sonoicPlaybackDebugID(serviceAccountID))"
            )
            let cloudQueue: SonoicCloudQueueCreateResponse
            do {
                cloudQueue = try await sonoicCloudQueueClient.createQueue(
                    request,
                    configuration: sonosOAuthConfiguration,
                    accessToken: context.accessToken
                )
            } catch {
                sonoicPlaybackDebugLog(
                    "cloudQueue createQueue failed parent='\(parentItem.title)' error='\(error.localizedDescription)'"
                )
                throw error
            }
            sonoicPlaybackDebugLog(
                "cloudQueue createQueue success queue=\(sonoicPlaybackDebugID(cloudQueue.queueId)) version=\(sonoicPlaybackDebugID(cloudQueue.queueVersion)) startItem=\(sonoicPlaybackDebugID(cloudQueue.startItemId)) base='\(cloudQueue.queueBaseUrl)'"
            )
            sonoicPlaybackDebugLog(
                "cloudQueue createSession start group=\(sonoicPlaybackDebugID(context.groupID)) accountID=\(sonoicPlaybackDebugID(serviceAccountID))"
            )
            let sessionStatus: SonosControlAPISessionStatus
            do {
                sessionStatus = try await sonosControlAPIClient.createPlaybackSession(
                    groupID: context.groupID,
                    appID: "Sonoic",
                    appContext: parentItem.title,
                    accountID: serviceAccountID,
                    customData: parentItem.id,
                    accessToken: context.accessToken
                )
            } catch {
                sonoicPlaybackDebugLog(
                    "cloudQueue createSession failed group=\(sonoicPlaybackDebugID(context.groupID)) accountID=\(sonoicPlaybackDebugID(serviceAccountID)) error='\(error.localizedDescription)'"
                )
                throw error
            }
            guard let sessionID = sessionStatus.sessionId?.sonoicNonEmptyTrimmed else {
                sonoicPlaybackDebugLog(
                    "cloudQueue createSession invalidSessionID group=\(sonoicPlaybackDebugID(context.groupID))"
                )
                throw SonosControlAPITransport.TransportError.invalidResponse
            }
            sonoicPlaybackDebugLog(
                "cloudQueue createSession success session=\(sonoicPlaybackDebugID(sessionID))"
            )
            sonoicPlaybackDebugLog(
                "cloudQueue load session=\(sonoicPlaybackDebugID(sessionID)) queue=\(sonoicPlaybackDebugID(cloudQueue.queueId)) startItem=\(sonoicPlaybackDebugID(cloudQueue.startItemId))"
            )
            do {
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
            } catch {
                sonoicPlaybackDebugLog(
                    "cloudQueue load failed session=\(sonoicPlaybackDebugID(sessionID)) queue=\(sonoicPlaybackDebugID(cloudQueue.queueId)) startItem=\(sonoicPlaybackDebugID(cloudQueue.startItemId)) version=\(sonoicPlaybackDebugID(cloudQueue.queueVersion)) base='\(cloudQueue.queueBaseUrl)' error='\(error.localizedDescription)'"
                )
                throw error
            }
            sonoicPlaybackDebugLog(
                "cloudQueue load success session=\(sonoicPlaybackDebugID(sessionID))"
            )
            sonosControlAPICloudQueueSessionID = sessionID
            sonosControlAPICloudQueueGroupID = context.groupID
            sonosControlAPICloudQueueVersion = cloudQueue.queueVersion
            sonosControlAPICloudQueueItemIDs = queueItemIDs
            sonosControlAPICloudQueueTracks = queueTracks
            persistSonosControlAPICloudQueueContext()
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
            sonosControlAPICloudQueueGroupID = previousCloudQueueGroupID
            sonosControlAPICloudQueueVersion = previousCloudQueueVersion
            sonosControlAPICloudQueueItemIDs = previousCloudQueueItemIDs
            sonosControlAPICloudQueueTracks = previousCloudQueueTracks
            persistSonosControlAPICloudQueueContext()
        }

        if didLoad {
            sonoicPlaybackDebugLog(
                "cloudQueue result=true parent='\(parentItem.title)'"
            )
        } else {
            sonoicPlaybackDebugLog(
                "cloudQueue result=false parent='\(parentItem.title)' error='\(sonosControlAPIState.lastErrorDetail ?? "unknown")'"
            )
        }
        return didLoad
    }

    private func sonosControlAPICloudQueueCreateRequest(
        parentItem: SonoicSourceItem,
        plan: SonoicSourcePlaylistPlaybackPlan,
        accountID: String?
    ) -> SonoicCloudQueueCreateRequest? {
        var queueItems: [SonosControlAPIQueueItem] = []
        var seenItemIDs: Set<String> = []

        for (index, pair) in zip(plan.items, plan.payloads).enumerated() {
            guard let objectID = sonosControlAPIObjectID(for: pair.1, item: pair.0),
                  let contentType = sonosControlAPIContentType(for: pair.1.uri)
            else {
                return nil
            }

            let queueItemID = SonoicSonosControlAPIQueueItemIDBuilder.uniqueID(
                index: index,
                objectID: objectID,
                itemID: pair.0.id,
                usedIDs: seenItemIDs
            )
            seenItemIDs.insert(queueItemID)

            queueItems.append(SonosControlAPIQueueItem(
                id: queueItemID,
                track: sonosControlAPITrack(
                    item: pair.0,
                    payload: pair.1,
                    objectID: objectID,
                    contentType: contentType,
                    accountID: accountID,
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
            container: sonosControlAPIContainer(for: parentItem, accountID: accountID),
            items: queueItems,
            startItemId: queueItems[startIndex].id
        )
    }

    private func sonosControlAPIContainer(
        for item: SonoicSourceItem,
        accountID: String?
    ) -> SonosControlAPIContainer {
        SonosControlAPIContainer(
            name: item.title,
            type: item.kind.rawValue,
            id: sonosControlAPICollectionObjectID(for: item).map {
                sonosControlAPIUniversalMusicObjectID($0, accountID: accountID)
            },
            service: sonosControlAPIAppleMusicService(for: item),
            imageUrl: item.artworkURL?.sonoicNonEmptyTrimmed
        )
    }

    private func sonosControlAPITrack(
        item: SonoicSourceItem,
        payload: SonosPlayablePayload,
        objectID: String,
        contentType: String,
        accountID: String?,
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
            id: sonosControlAPIUniversalMusicObjectID(objectID, accountID: accountID),
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

    private func sonosControlAPIUniversalMusicObjectID(
        _ objectID: String,
        accountID: String?
    ) -> SonosControlAPIUniversalMusicObjectID {
        SonosControlAPIUniversalMusicObjectID(
            serviceId: SonosServiceDescriptor.appleMusic.sonosServiceID ?? "204",
            objectId: objectID,
            accountId: accountID?.sonoicNonEmptyTrimmed
        )
    }

    private func sonosControlAPICloudQueueAccountID(for item: SonoicSourceItem) -> (raw: String, formatted: String)? {
        guard item.service.kind == .appleMusic else {
            return nil
        }

        let appleMusicRow = sonosMusicServiceProbeState.snapshot?.knownServiceRows.first { $0.service == .appleMusic }
        let playbackHint = appleMusicRow?.playbackHint
        let rawAccountID = playbackHint?.preferredLaunchSerial?.sonoicNonEmptyTrimmed
            ?? playbackHint?.trackSerials.first?.sonoicNonEmptyTrimmed
            ?? appleMusicRow?.accounts.first?.serialNumber.sonoicNonEmptyTrimmed
        guard let rawAccountID else {
            return nil
        }

        return (
            raw: rawAccountID,
            formatted: sonosControlAPIFormattedMusicAccountID(rawAccountID)
        )
    }

    private func sonosControlAPIFormattedMusicAccountID(_ rawAccountID: String) -> String {
        let trimmed = rawAccountID.sonoicTrimmed
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("sn_") || lowercased.hasPrefix("mhhid_") {
            return trimmed
        }

        if lowercased.hasPrefix("sn ") {
            let serial = String(trimmed.dropFirst(3)).sonoicTrimmed
            if let serial = serial.sonoicNonEmptyTrimmed {
                return "sn_\(serial)"
            }
        }

        if trimmed.allSatisfy(\.isNumber) {
            return "sn_\(trimmed)"
        }

        return trimmed
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
        let previousCloudQueueGroupID = sonosControlAPICloudQueueGroupID
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
            sonosControlAPICloudQueueGroupID = previousCloudQueueGroupID
            sonosControlAPICloudQueueVersion = previousCloudQueueVersion
            sonosControlAPICloudQueueItemIDs = previousCloudQueueItemIDs
            sonosControlAPICloudQueueTracks = previousCloudQueueTracks
            persistSonosControlAPICloudQueueContext()
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
            sonoicPlaybackDebugLog("cloudCommand skipped description='\(description)' reason=inFlight")
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
            sonoicPlaybackDebugLog(
                "cloudCommand failed description='\(description)' error='\(error.localizedDescription)'"
            )
            if isSonosControlAPIAuthorizationFailure(error) {
                sonosControlAPIState.authorizationStatus = .expired
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
                clearSonosControlAPIPlaybackContextAfterAuthorizationLoss()
            }
            manualHostRefreshStatus = .failed(error.localizedDescription)
            startManualHostRefreshLoopIfPossible()
            return false
        }
    }

    func isSonosControlAPIAuthorizationFailure(_ error: Error) -> Bool {
        if let transportError = error as? SonosControlAPITransport.TransportError {
            return transportError.isAuthorizationFailure
        }

        if let cloudQueueError = error as? SonoicCloudQueueClient.ClientError {
            return cloudQueueError.isAuthorizationFailure
        }

        return false
    }
}

private enum SonosControlAPISeekFailure: LocalizedError {
    case unsupported
    case sessionItemUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "Sonos reported that the current item cannot seek."
        case .sessionItemUnavailable:
            "Sonoic could not match the current Cloud Queue item for seeking."
        }
    }
}
