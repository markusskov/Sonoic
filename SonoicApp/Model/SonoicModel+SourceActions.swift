import Foundation

func sonoicPlaybackDebugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    print("[SonoicPlaylistPlayback] \(message())")
#endif
}

func sonoicPlaybackDebugID(_ value: String?) -> String {
    guard let value = value?.sonoicNonEmptyTrimmed else {
        return "nil"
    }

    return value.count > 8 ? String(value.suffix(8)) : value
}

func sonoicPlaybackDebugCloudStatus(_ status: SonosControlAPICloudState.Status) -> String {
    switch status {
    case .idle:
        "idle"
    case .loading:
        "loading"
    case let .verified(snapshot):
        "verified households=\(snapshot.households.count) groups=\(snapshot.groupCount) players=\(snapshot.playerCount) favorites=\(snapshot.favoriteCount) playlists=\(snapshot.playlistCount)"
    case .failed:
        "failed"
    }
}

enum SonoicSourceActionError: LocalizedError {
    case playbackPayloadUnavailable

    var errorDescription: String? {
        switch self {
        case .playbackPayloadUnavailable:
            "This item does not have a Sonos playback payload yet."
        }
    }
}

extension SonoicModel {
    func canPlaySourceItem(_ item: SonoicSourceItem) -> Bool {
        guard canSendPrimarySourcePlaybackCommands else {
            return false
        }

        return (try? sourcePlayablePayload(for: item, purpose: .directPlay)) != nil
    }

    private var canSendPrimarySourcePlaybackCommands: Bool {
        if sonosControlAPIState.settings.mode.canSendCommands {
            return hasSonosControlAPICommandTarget
        }

        return hasManualSonosHost
    }

    func sourcePlaylistFallbackPayload(for item: SonoicSourceItem) -> SonosPlayablePayload? {
        try? sourcePlayablePayload(for: item, purpose: .metadata)
    }

    private var allowsLocalSourcePlaybackFallback: Bool {
        !sonosControlAPIState.settings.mode.canSendCommands
    }

    func canPlaySourcePlaylistQueue(
        parentItem: SonoicSourceItem,
        trackItems: [SonoicSourceItem]
    ) -> Bool {
        sonosFavoriteBackedPlaylist(for: parentItem) != nil
            || sourcePlaylistPlaybackPlan(parentItem: parentItem, trackItems: trackItems) != nil
    }

    @discardableResult
    func playSourceItem(_ item: SonoicSourceItem) async throws -> Bool {
        await refreshSourcePlaybackContextIfNeeded(for: item.service)

        guard let payload = try sourcePlayablePayload(for: item, purpose: .directPlay) else {
            throw SonoicSourceActionError.playbackPayloadUnavailable
        }

        if let plan = sourceSingleItemPlaybackPlan(for: item, payload: payload),
           await playSonosControlAPICloudQueueIfAvailable(parentItem: item, plan: plan)
        {
            recordRecentSourceItem(item, replayPayload: plan.recentPlaybackPayload)
            return true
        }

        guard allowsLocalSourcePlaybackFallback else {
            return false
        }

        return await playManualSonosPayload(payload)
    }

    @discardableResult
    func playSourcePlaylistQueue(
        parentItem: SonoicSourceItem,
        trackItems: [SonoicSourceItem],
        startingAtIndex startIndex: Int? = nil,
        shuffled: Bool = false
    ) async -> Bool {
        sonoicPlaybackDebugLog(
            "playlistQueue start parent='\(parentItem.title)' kind=\(parentItem.kind.rawValue) origin=\(parentItem.origin.rawValue) service=\(parentItem.service.name) trackCount=\(trackItems.count) startIndex=\(String(describing: startIndex)) shuffled=\(shuffled)"
        )

        await refreshSourcePlaybackContextIfNeeded(for: parentItem.service)
        let generatedPlan = sourcePlaylistPlaybackPlan(
            parentItem: parentItem,
            trackItems: trackItems,
            startingAtIndex: startIndex,
            shuffled: shuffled
        )
        let favoriteCloudFallback = sourcePlaylistFavoriteFallback(
            for: parentItem,
            startIndex: startIndex,
            shuffled: shuffled,
            allowStartOffset: false,
            log: false
        )

        if let generatedPlan,
           await playSonosControlAPICloudQueueIfAvailable(parentItem: parentItem, plan: generatedPlan)
        {
            recordRecentSourceItem(parentItem, replayPayload: generatedPlan.recentPlaybackPayload)
            sonoicPlaybackDebugLog(
                "playlistQueue cloudQueue result=true parent='\(parentItem.title)'"
            )
            return true
        }

        if sonosControlAPIState.settings.mode.canSendCommands,
           let favorite = favoriteCloudFallback,
           await playManualSonosFavorite(favorite)
        {
            recordRecentSourceItem(parentItem, replayPayload: sourcePlaylistFallbackPayload(for: parentItem))
            sonoicPlaybackDebugLog(
                "playlistQueue cloudFavoriteFallback result=true parent='\(parentItem.title)'"
            )
            return true
        }

        guard allowsLocalSourcePlaybackFallback else {
            sonoicPlaybackDebugLog(
                "playlistQueue cloudQueue result=false noLocalPlaybackFallback=true parent='\(parentItem.title)'"
            )
            return false
        }

        if let favorite = sourcePlaylistFavoriteFallback(
            for: parentItem,
            startIndex: startIndex,
            shuffled: shuffled,
            allowStartOffset: true,
            log: true
        )
        {
            let sourceIndex = startIndex ?? 0
            guard sourceIndex >= 0,
                  startIndex == nil || sourceIndex < trackItems.count
            else {
                sonoicPlaybackDebugLog(
                    "playlistQueue favoritePath invalidIndex parent='\(parentItem.title)' sourceIndex=\(sourceIndex) trackCount=\(trackItems.count)"
                )
                return false
            }

            sonoicPlaybackDebugLog(
                "playlistQueue favoritePath loading favorite='\(favorite.title)' favoriteID=\(sonoicPlaybackDebugID(favorite.id)) sourceIndex=\(sourceIndex)"
            )
            guard await playManualSonosFavorite(favorite) else {
                sonoicPlaybackDebugLog(
                    "playlistQueue favoritePath favoriteLoadFailed favorite='\(favorite.title)' fallingBackToGeneratedPlan=true"
                )
                return await playGeneratedSourcePlaylistQueue(
                    parentItem: parentItem,
                    plan: generatedPlan,
                    trackItemsCount: trackItems.count,
                    startIndex: startIndex
                )
            }

            let startingTrackNumber = sourceIndex + 1
            if startingTrackNumber > 1 {
                sonoicPlaybackDebugLog(
                    "playlistQueue favoritePath seekingToTrack=\(startingTrackNumber)"
                )
                guard await playManualSonosQueueItem(at: startingTrackNumber) else {
                    sonoicPlaybackDebugLog(
                        "playlistQueue favoritePath seekFailed track=\(startingTrackNumber) fallingBackToGeneratedPlan=true"
                    )
                    return await playGeneratedSourcePlaylistQueue(
                        parentItem: parentItem,
                        plan: generatedPlan,
                        trackItemsCount: trackItems.count,
                        startIndex: startIndex
                    )
                }
            }
            recordRecentSourceItem(parentItem, replayPayload: sourcePlaylistFallbackPayload(for: parentItem))
            sonoicPlaybackDebugLog(
                "playlistQueue favoritePath success parent='\(parentItem.title)' track=\(startingTrackNumber)"
            )
            return true
        }

        return await playGeneratedSourcePlaylistQueue(
            parentItem: parentItem,
            plan: generatedPlan,
            trackItemsCount: trackItems.count,
            startIndex: startIndex
        )
    }

    private func sourcePlaylistFavoriteFallback(
        for parentItem: SonoicSourceItem,
        startIndex: Int?,
        shuffled: Bool,
        allowStartOffset: Bool,
        log: Bool
    ) -> SonosFavoriteItem? {
        guard !shuffled,
              allowStartOffset || startIndex == nil || startIndex == 0
        else {
            return nil
        }

        return sonosFavoriteBackedPlaylist(for: parentItem, log: log)
    }

    private func playGeneratedSourcePlaylistQueue(
        parentItem: SonoicSourceItem,
        plan: SonoicSourcePlaylistPlaybackPlan?,
        trackItemsCount: Int,
        startIndex: Int?
    ) async -> Bool {
        guard allowsLocalSourcePlaybackFallback else {
            sonoicPlaybackDebugLog(
                "playlistQueue generatedPlanSkipped noLocalPlaybackFallback=true parent='\(parentItem.title)'"
            )
            return false
        }

        guard let plan else {
            sonoicPlaybackDebugLog(
                "playlistQueue generatedPlanUnavailable parent='\(parentItem.title)' trackCount=\(trackItemsCount) startIndex=\(String(describing: startIndex))"
            )
            return false
        }

        let startingTrackNumber = plan.startingTrackNumber
        sonoicPlaybackDebugLog(
            "playlistQueue generatedPlan start payloadCount=\(plan.payloads.count) startingTrack=\(startingTrackNumber)"
        )
        let didStartPlayback = await playManualSonosQueuePayloads(
            plan.payloads,
            startingTrackNumber: startingTrackNumber,
            localNowPlayingPayload: plan.localNowPlayingPayload,
            recentPlaybackPayload: plan.recentPlaybackPayload
        )

        if didStartPlayback {
            recordRecentSourceItem(parentItem, replayPayload: plan.recentPlaybackPayload)
        }

        sonoicPlaybackDebugLog(
            "playlistQueue generatedPlan result=\(didStartPlayback) parent='\(parentItem.title)'"
        )
        return didStartPlayback
    }

    private func sourceSingleItemPlaybackPlan(
        for item: SonoicSourceItem,
        payload: SonosPlayablePayload
    ) -> SonoicSourcePlaylistPlaybackPlan? {
        guard sourceAdapter(for: item).capabilities.supportsSonosPlaybackPayloads else {
            return nil
        }

        let queuePayload = (try? sourcePlayablePayload(for: item, purpose: .queueEntry)) ?? payload
        let metadataPayload = (try? sourcePlayablePayload(for: item, purpose: .metadata)) ?? queuePayload
        return SonoicSourcePlaylistPlaybackPlan(
            payloads: [queuePayload],
            items: [item],
            startingTrackNumber: 1,
            localNowPlayingPayload: metadataPayload,
            recentPlaybackPayload: metadataPayload
        )
    }

    private func refreshSourcePlaybackContextIfNeeded(for service: SonosServiceDescriptor) async {
        guard service.kind == .appleMusic else {
            return
        }

        await refreshSonosMusicServiceProbeIfNeeded()

        let appleMusicRow = sonosMusicServiceProbeState.snapshot?.knownServiceRows.first { $0.service == .appleMusic }
        let hint = appleMusicRow?.playbackHint
        sonoicPlaybackDebugLog(
            "sourcePlaybackContext service='\(service.name)' probeStatus=\(sonosMusicServiceProbeState.status.sonoicDebugTitle) launchSerials=\(hint?.launchSerials.joined(separator: ",") ?? "none") trackSerials=\(hint?.trackSerials.joined(separator: ",") ?? "none")"
        )
    }

    @discardableResult
    func playSourcePlaylistFallback(_ item: SonoicSourceItem) async throws -> Bool {
        guard let payload = sourcePlaylistFallbackPayload(for: item) else {
            throw SonoicSourceActionError.playbackPayloadUnavailable
        }

        guard allowsLocalSourcePlaybackFallback else {
            sonoicPlaybackDebugLog(
                "sourceFallback noLocalPlaybackFallback=true item='\(item.title)'"
            )
            return false
        }

        let didStartPlayback = await playManualSonosPayload(
            payload,
            localNowPlayingPayload: payload,
            recentPlaybackPayload: payload
        )

        if didStartPlayback {
            recordRecentSourceItem(item, replayPayload: payload)
        }

        return didStartPlayback
    }

    @discardableResult
    func playSourcePlaylist(
        parentItem: SonoicSourceItem,
        trackItems: [SonoicSourceItem],
        shuffled: Bool = false
    ) async throws -> Bool {
        if canPlaySourcePlaylistQueue(parentItem: parentItem, trackItems: trackItems) {
            return await playSourcePlaylistQueue(
                parentItem: parentItem,
                trackItems: trackItems,
                shuffled: shuffled
            )
        }

        return try await playSourcePlaylistFallback(parentItem)
    }

    private func sonosFavoriteBackedPlaylist(for item: SonoicSourceItem, log: Bool = false) -> SonosFavoriteItem? {
        guard item.kind == .playlist,
              item.service.kind == .appleMusic
        else {
            if log {
                sonoicPlaybackDebugLog(
                    "favoriteMatch skipped item='\(item.title)' kind=\(item.kind.rawValue) service=\(item.service.name)"
                )
            }
            return nil
        }

        let itemCatalogID = item.sourceReference?.catalogID?.sonoicNonEmptyTrimmed
        let itemLibraryID = item.sourceReference?.libraryID?.sonoicNonEmptyTrimmed
        let itemServiceID = item.serviceItemID?.sonoicNonEmptyTrimmed
        let sourceIDs = [itemCatalogID, itemLibraryID, itemServiceID].compactMap(\.self)
        let favorites = homeFavoritesState.snapshot?.items ?? []

        if log {
            sonoicPlaybackDebugLog(
                "favoriteMatch start item='\(item.title)' sourceIDs=\(sourceIDs.map(sonoicPlaybackDebugID).joined(separator: ",")) favoriteCount=\(favorites.count)"
            )
        }

        for favorite in favorites {
            guard favorite.service?.kind == .appleMusic,
                  favorite.isPlaylistLike,
                  sourceActionMatchText(favorite.title) == sourceActionMatchText(item.title)
            else {
                continue
            }

            guard !sourceIDs.isEmpty else {
                if log {
                    sonoicPlaybackDebugLog(
                        "favoriteMatch matchedByTitle favorite='\(favorite.title)' favoriteID=\(sonoicPlaybackDebugID(favorite.id))"
                    )
                }
                return favorite
            }

            let normalizedFavoritePayload = sourceActionPayloadSearchText(for: favorite)

            let hasSourceIDMatch = sourceIDs.contains { sourceID in
                normalizedFavoritePayload.contains(sourceActionPayloadID(sourceID))
            }

            if hasSourceIDMatch {
                if log {
                    sonoicPlaybackDebugLog(
                        "favoriteMatch matchedByPayload favorite='\(favorite.title)' favoriteID=\(sonoicPlaybackDebugID(favorite.id))"
                    )
                }
                return favorite
            }
        }

        if log {
            sonoicPlaybackDebugLog(
                "favoriteMatch noMatch item='\(item.title)' sourceIDs=\(sourceIDs.map(sonoicPlaybackDebugID).joined(separator: ","))"
            )
        }

        return nil
    }

    private func sourceActionPayloadSearchText(for favorite: SonosFavoriteItem) -> String {
        [
            favorite.playbackURI,
            favorite.playbackURI.removingPercentEncoding,
            favorite.playbackMetadataXML,
            favorite.playbackMetadataXML?.removingPercentEncoding
        ]
        .compactMap(\.self)
        .map(sourceActionPayloadID)
        .joined(separator: " ")
    }

    private func sourceActionPayloadID(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    private func sourceActionMatchText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension SonosMusicServiceProbeState.Status {
    var sonoicDebugTitle: String {
        switch self {
        case .idle:
            "idle"
        case .loading:
            "loading"
        case .loaded:
            "loaded"
        case .failed:
            "failed"
        }
    }
}
