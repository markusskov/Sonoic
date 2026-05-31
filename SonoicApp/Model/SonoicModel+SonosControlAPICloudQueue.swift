import Foundation

extension SonoicModel {
    private struct SonosControlAPICloudQueueLoadResult {
        var cloudQueue: SonoicCloudQueueCreateResponse
        var sessionID: String
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
