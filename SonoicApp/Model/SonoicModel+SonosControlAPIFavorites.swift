import Foundation

extension SonoicModel {
    func playSonosControlAPIFavoriteIfAvailable(_ favorite: SonosFavoriteItem) async -> Bool {
        sonoicPlaybackDebugLog(
            "cloudFavorite start title='\(favorite.title)' canSend=\(sonosControlAPIState.canSendCommands) auth=\(String(describing: sonosControlAPIState.authorizationStatus)) target=\(activeTarget.id)"
        )
        guard sonosPlaybackCommandRoute.routesCommandsToSonosControlAPI else {
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
            "cloudFavorite matchContent start title='\(favorite.title)' household=\(sonoicPlaybackDebugID(householdID)) \(sonosControlAPICloudContentFetchDiagnosticsDescription(snapshot: snapshot, householdID: householdID))"
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

    func sonosControlAPICloudContentFetchDiagnosticsDescription(
        snapshot: SonosControlAPICloudSnapshot,
        householdID: String
    ) -> String {
        let diagnostics = snapshot.contentFetchDiagnosticsByHouseholdID[householdID]
        return [
            "favorites=\(sonosControlAPICloudContentFetchResultDescription(diagnostics?.favorites, fallbackCount: snapshot.favoritesByHouseholdID[householdID]?.count))",
            "playlists=\(sonosControlAPICloudContentFetchResultDescription(diagnostics?.playlists, fallbackCount: snapshot.playlistsByHouseholdID[householdID]?.count))"
        ].joined(separator: " ")
    }

    private func sonosControlAPICloudContentFetchResultDescription(
        _ result: SonosControlAPICloudContentFetchResult?,
        fallbackCount: Int?
    ) -> String {
        if let result {
            switch result.status {
            case let .loaded(count, version):
                let state = count == 0 ? "loadedEmpty" : "loaded"
                return "\(state) count=\(count) version=\(sonoicPlaybackDebugID(version))"
            case let .failed(detail, isAuthorizationFailure):
                return "failed auth=\(isAuthorizationFailure) detail='\(sonosControlAPIDebugDetail(detail))'"
            }
        }

        guard let fallbackCount else {
            return "missing"
        }

        return "\(fallbackCount == 0 ? "loadedEmpty" : "loaded") count=\(fallbackCount) version=nil"
    }

    private func sonosControlAPIDebugDetail(_ detail: String) -> String {
        let singleLine = detail
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .sonoicTrimmed
        return String(singleLine.prefix(180))
    }

    private func hasValidSonosControlAPITokenForPlayback(logPrefix: String? = nil) async -> Bool {
        await validSonosControlAPITokenSetForCommands(logPrefix: logPrefix) != nil
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
        let rollbackState = SonosControlAPILoadRollbackState(self)

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
            rollbackState.restoreFailedLoad(
                on: self,
                didLoseAuthorization: sonosControlAPIState.authorizationStatus == .expired,
                clearManualContextOnAuthorizationLoss: true
            )
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
}
