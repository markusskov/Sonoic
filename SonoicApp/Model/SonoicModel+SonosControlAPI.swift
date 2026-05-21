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
            let itemID = sonosControlAPISeekItemID(from: status)
            sonoicPlaybackDebugLog(
                "cloudseek seekPayload itemID=\(itemID.map(sonoicPlaybackDebugID) ?? "omitted") rawItemID=\(sonoicPlaybackDebugID(status.itemId))"
            )
            requestedAt = Date()
            try await sonosControlAPIClient.seek(
                groupID: context.groupID,
                positionMillis: Int((boundedElapsedTime * 1_000).rounded()),
                itemID: itemID,
                accessToken: context.accessToken
            )
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

    private func sonosControlAPISeekItemID(from status: SonosControlAPIPlaybackStatus) -> String? {
        guard let itemID = status.itemId?.sonoicNonEmptyTrimmed else {
            return nil
        }

        // Queue playback can report a numeric itemId that behaves like a queue index,
        // not a seekable cloud object id. Passing it makes Sonos reject the seek.
        guard !itemID.allSatisfy(\.isNumber) else {
            return nil
        }

        return itemID
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

        if let snapshot = queueState.snapshot {
            queueState = .loaded(SonosQueueSnapshot(
                items: snapshot.items,
                currentItemIndex: nil,
                sourceURI: snapshot.sourceURI
            ))
        }

        beginManualPlayTransitionGrace()
        manualQueueContextPayloads = nil
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
