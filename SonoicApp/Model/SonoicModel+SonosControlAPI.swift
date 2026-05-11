import Foundation

extension SonoicModel {
    private static let sonosControlAPITransportSyncDelay: Duration = .milliseconds(350)
    private static let sonosControlAPISeekPollDelay: Duration = .milliseconds(350)
    private static let sonosControlAPISeekPollAttempts = 5

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
        guard sonosControlAPIState.canSendCommands else {
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
        guard let context = sonosControlAPICommandContext() else {
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
        guard let context = sonosControlAPICommandContext() else {
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
        guard let context = sonosControlAPICommandContext() else {
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
        guard let context = sonosControlAPICommandContext() else {
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
        guard let context = sonosControlAPICommandContext() else {
            return false
        }

        guard !isManualTransportCommandInFlight else {
            return false
        }

        let boundedElapsedTime = max(timeInterval, 0)
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
        let requestedAt = Date()
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
            try await sonosControlAPIClient.seek(
                groupID: context.groupID,
                positionMillis: Int((boundedElapsedTime * 1_000).rounded()),
                itemID: status.itemId,
                accessToken: context.accessToken
            )
            for _ in 0 ..< Self.sonosControlAPISeekPollAttempts {
                try await Task.sleep(for: Self.sonosControlAPISeekPollDelay)
                let observedStatus: SonosControlAPIPlaybackStatus
                do {
                    observedStatus = try await sonosControlAPIClient.playbackStatus(
                        groupID: context.groupID,
                        accessToken: context.accessToken
                    )
                } catch {
                    pollingErrorDetail = error.localizedDescription
                    return
                }
                observedPlaybackState = observedStatus.playbackState
                observedElapsedTime = observedStatus.positionMillis.map { TimeInterval($0) / 1_000 }
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
            recordSeekDiagnostics(
                status: didConfirmSeek ? .succeeded : .pending,
                host: "Sonos Control API",
                target: boundedElapsedTime,
                observed: observedElapsedTime,
                errorDetail: didConfirmSeek ? nil : pollingErrorDetail.map {
                    "Cloud accepted; status polling failed: \($0)"
                } ?? "Cloud accepted; awaiting Sonos position update."
            )
            return true
        }

        recordSeekDiagnostics(
            status: .failed,
            host: "Sonos Control API",
            target: boundedElapsedTime,
            observed: observedElapsedTime,
            errorDetail: sonosControlAPIState.lastErrorDetail
        )
        return false
    }

    func playSonosControlAPIFavoriteIfAvailable(_ favorite: SonosFavoriteItem) async -> Bool {
        sonoicPlaybackDebugLog(
            "cloudFavorite start title='\(favorite.title)' canSend=\(sonosControlAPIState.canSendCommands) auth=\(String(describing: sonosControlAPIState.authorizationStatus)) target=\(activeTarget.id)"
        )
        guard sonosControlAPIState.canSendCommands else {
            sonoicPlaybackDebugLog("cloudFavorite unavailable canSend=false title='\(favorite.title)'")
            return false
        }

        guard hasValidSonosControlAPITokenForPlayback() else {
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

        if let context = sonosControlAPICommandContext(requiresActiveTargetMatch: true),
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

        guard let refreshedContext = sonosControlAPICommandContext(requiresActiveTargetMatch: true),
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

    private func hasValidSonosControlAPITokenForPlayback() -> Bool {
        do {
            guard let tokenSet = try keychainStore.loadSonosTokenSet() else {
                sonosControlAPIAuthorizationState = .disconnected
                markSonosControlAPIAuthorizationUnavailable()
                return false
            }

            guard !tokenSet.isExpired() else {
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
                sonosControlAPIState.authorizationStatus = .expired
                return false
            }

            return true
        } catch {
            recordSonosControlAPIError(error)
            return false
        }
    }

    private func sonosControlAPICommandContext(
        requiresActiveTargetMatch: Bool = false
    ) -> SonosControlAPICommandContext? {
        guard sonosControlAPIState.canSendCommands else {
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

        do {
            guard let tokenSet = try keychainStore.loadSonosTokenSet() else {
                sonosControlAPIAuthorizationState = .disconnected
                markSonosControlAPIAuthorizationUnavailable()
                return nil
            }

            guard !tokenSet.isExpired() else {
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
                sonosControlAPIState.authorizationStatus = .expired
                return nil
            }

            markSonosControlAPIAuthorizationReady()
            return SonosControlAPICommandContext(
                householdID: householdID,
                groupID: groupID,
                accessToken: tokenSet.accessToken
            )
        } catch {
            recordSonosControlAPIError(error)
            return nil
        }
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
