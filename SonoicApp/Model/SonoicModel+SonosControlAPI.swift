import Foundation

extension SonoicModel {
    struct SonosControlAPICommandContext {
        var householdID: String?
        var groupID: String
        var accessToken: String
    }

    private struct SonosControlAPICommandUnavailableError: LocalizedError {
        var errorDescription: String? {
            "Sonos Cloud control is unavailable."
        }
    }

    private struct SonosControlAPICloudQueueLoadResult {
        var cloudQueue: SonoicCloudQueueCreateResponse
        var sessionID: String
    }

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

    func activeSonosControlAPIGroupID() -> String? {
        guard sonosPlaybackCommandRoute.routesCommandsToSonosControlAPI else {
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

    func sonosControlAPICommandContext(
        requiresActiveTargetMatch: Bool = false,
        logPrefix: String? = nil
    ) async -> SonosControlAPICommandContext? {
        guard sonosPlaybackCommandRoute.routesCommandsToSonosControlAPI else {
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

    func skipSonosControlAPICloudQueueItemIfAvailable(at position: Int) async -> Bool {
        guard position > 0 else {
            return false
        }

        let index = position - 1
        guard let target = sonosControlAPICloudQueueRuntimeState.playbackTarget(at: index)
        else {
            sonoicPlaybackDebugLog(
                "cloudQueueSkip unavailable position=\(position) session=\(sonoicPlaybackDebugID(sonosControlAPICloudQueueRuntimeState.sessionID)) itemCount=\(sonosControlAPICloudQueueRuntimeState.itemCount)"
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
                sessionID: target.sessionID,
                itemID: target.itemID,
                queueVersion: target.queueVersion,
                positionMillis: 0,
                playOnCompletion: true,
                trackMetadata: target.track,
                accessToken: context.accessToken
            )
        }

        if didSkip {
            updateSonosControlAPICloudQueueCurrentItem(itemID: target.itemID)
        } else {
            queueState = previousQueueState
            nowPlaying = previousNowPlaying
            nowPlayingObservedAt = previousNowPlayingObservedAt
            manualPlaybackContextPayload = previousPlaybackContextPayload
        }

        sonoicPlaybackDebugLog(
            "cloudQueueSkip result=\(didSkip) position=\(position) itemID=\(sonoicPlaybackDebugID(target.itemID))"
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

        let rollbackState = SonosControlAPILoadRollbackState(self)
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
        sonosControlAPICloudQueueRuntimeState = SonosControlAPICloudQueueRuntimeState(
            sessionID: nil,
            groupID: context.groupID,
            queueVersion: nil,
            itemIDs: queueItemIDs,
            tracks: queueTracks
        )
        markLocalNowPlaying(from: plan.localNowPlayingPayload ?? confirmationPayload)

        let didLoad = await performSonosControlAPITransportCommand(
            description: "Cloud queue",
            refreshQueueAfterSuccess: false
        ) {
            let loadResult = try await loadSonosControlAPICloudQueue(
                parentItem: parentItem,
                request: request,
                context: context,
                serviceAccountID: serviceAccountID
            )
            sonosControlAPICloudQueueRuntimeState = SonosControlAPICloudQueueRuntimeState(
                sessionID: loadResult.sessionID,
                groupID: context.groupID,
                queueVersion: loadResult.cloudQueue.queueVersion,
                itemIDs: queueItemIDs,
                tracks: queueTracks
            )
            persistSonosControlAPICloudQueueContext()
            if let snapshot = sonosControlAPICloudQueueSnapshot(
                currentItemIndex: startIndex,
                sourceURI: "sonoic-cloud-queue:\(loadResult.cloudQueue.queueId)"
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
            rollbackState.restoreFailedLoad(
                on: self,
                didLoseAuthorization: sonosControlAPIState.authorizationStatus == .expired,
                clearManualContextOnAuthorizationLoss: false
            )
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

    private func loadSonosControlAPICloudQueue(
        parentItem: SonoicSourceItem,
        request: SonoicCloudQueueCreateRequest,
        context: SonosControlAPICommandContext,
        serviceAccountID: String?
    ) async throws -> SonosControlAPICloudQueueLoadResult {
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
        return SonosControlAPICloudQueueLoadResult(
            cloudQueue: cloudQueue,
            sessionID: sessionID
        )
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

}

private extension SonosQueueState {
    var isSonosControlAPICloudQueueBacked: Bool {
        snapshot?.sourceURI?
            .lowercased()
            .hasPrefix("sonoic-cloud-queue") == true
    }
}
