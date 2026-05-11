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
        (try? sourcePlayablePayload(for: item, purpose: .directPlay)) != nil
    }

    func sourcePlaylistFallbackPayload(for item: SonoicSourceItem) -> SonosPlayablePayload? {
        try? sourcePlayablePayload(for: item, purpose: .metadata)
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

        // Direct source payload starts still use the local Sonos content bridge
        // until Sonoic owns a Cloud Queue API for arbitrary service items.
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

        let sourceIndex = startIndex ?? 0
        if !shuffled,
           sourceIndex == 0,
           let favorite = sonosFavoriteBackedPlaylist(for: parentItem, log: true)
        {
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
            if await playSonosFavorite(favorite) {
                recordRecentSourceItem(parentItem, replayPayload: sourcePlaylistFallbackPayload(for: parentItem))
                sonoicPlaybackDebugLog(
                    "playlistQueue favoritePath success parent='\(parentItem.title)'"
                )
                return true
            } else {
                sonoicPlaybackDebugLog(
                    "playlistQueue favoritePath favoriteLoadFailed favorite='\(favorite.title)' fallingBackToGeneratedPlan=true"
                )
            }
        }

        if !shuffled,
           sourceIndex > 0,
           sonosFavoriteBackedPlaylist(for: parentItem) != nil
        {
            sonoicPlaybackDebugLog(
                "playlistQueue favoritePath specificTrackUsesGeneratedQueueUntilCloudQueueAPI parent='\(parentItem.title)' sourceIndex=\(sourceIndex)"
            )
        }

        return await playGeneratedSourcePlaylistQueue(
            parentItem: parentItem,
            trackItems: trackItems,
            startingAtIndex: startIndex,
            shuffled: shuffled
        )
    }

    private func playGeneratedSourcePlaylistQueue(
        parentItem: SonoicSourceItem,
        trackItems: [SonoicSourceItem],
        startingAtIndex startIndex: Int?,
        shuffled: Bool
    ) async -> Bool {
        await refreshSourcePlaybackContextIfNeeded(for: parentItem.service)

        guard let plan = sourcePlaylistPlaybackPlan(
            parentItem: parentItem,
            trackItems: trackItems,
            startingAtIndex: startIndex,
            shuffled: shuffled
        ) else {
            sonoicPlaybackDebugLog(
                "playlistQueue generatedPlanUnavailable parent='\(parentItem.title)' trackCount=\(trackItems.count) startIndex=\(String(describing: startIndex))"
            )
            return false
        }

        let startingTrackNumber = plan.startingTrackNumber
        sonoicPlaybackDebugLog(
            "playlistQueue generatedPlan start payloadCount=\(plan.payloads.count) startingTrack=\(startingTrackNumber)"
        )
        // Generated source queues are an explicit local bridge for now. They
        // should move to Cloud Queue API once the worker hosts the required
        // context/itemWindow/version endpoints.
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
