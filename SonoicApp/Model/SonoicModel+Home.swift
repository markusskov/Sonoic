import Foundation

extension SonoicModel {
    var homeFavoriteCollections: [SonosFavoriteItem] {
        homeFavoritesState.snapshot?.collectionItems ?? []
    }

    var homeRecentPlays: [SonoicRecentPlayItem] {
        visibleUniqueRecentPlays(from: recentPlays)
    }

    var homeSources: [SonoicSource] {
        let favorites = homeFavoritesState.snapshot?.items ?? []
        let favoriteServices = favorites.compactMap(\.service)
        let recentPlays = homeRecentPlays
        let recentServices = recentPlays.compactMap(\.service)
        let currentService = SonosServiceCatalog.descriptor(named: nowPlaying.sourceName)
        let services = orderedUniqueServices(
            favoriteServices
                + recentServices
                + [currentService].compactMap { $0 }
                + SonosServiceCatalog.browsableServices
        )

        return services.map { service in
            let matchingFavorites = favorites.filter { $0.service?.id == service.id }
            let matchingRecentPlays = recentPlays.filter { $0.service?.id == service.id }
            let isVisibleThroughSonos = !matchingFavorites.isEmpty || !matchingRecentPlays.isEmpty || currentService?.id == service.id

            return SonoicSource(
                service: service,
                favoriteCount: matchingFavorites.count,
                collectionCount: matchingFavorites.filter(\.isCollectionLike).count,
                recentCount: matchingRecentPlays.count,
                isCurrent: currentService?.id == service.id,
                status: isVisibleThroughSonos ? .visibleThroughSonos : .availableForSetup
            )
        }
    }

    func favoriteSourceItems(for source: SonoicSource) -> [SonoicSourceItem] {
        let favorites = homeFavoritesState.snapshot?.items ?? []
        return favorites
            .filter { $0.service?.id == source.service.id }
            .map(SonoicSourceItem.init(favorite:))
    }

    func recentSourceItems(for source: SonoicSource) -> [SonoicSourceItem] {
        homeRecentPlays
            .filter { $0.service?.id == source.service.id }
            .map(SonoicSourceItem.init(recentPlay:))
    }

    func refreshHomeFavorites(showLoading: Bool = true) async {
        guard hasManualSonosHost else {
            homeFavoritesState = .idle
            isHomeFavoritesRefreshing = false
            return
        }

        guard !isHomeFavoritesRefreshing else {
            return
        }

        isHomeFavoritesRefreshing = true
        defer {
            isHomeFavoritesRefreshing = false
        }

        if showLoading {
            homeFavoritesState = .loading
        }

        do {
            let snapshot = try await favoritesClient.fetchSnapshot(host: manualSonosHost)
            homeFavoritesState = snapshot.items.isEmpty ? .empty : .loaded(snapshot)
            reconcileAppleMusicFavoriteOverrides()
        } catch {
            homeFavoritesState = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func addSonosFavorite(_ payload: SonosPlayablePayload) async throws -> String {
        guard hasManualSonosHost else {
            throw SonosControlTransport.TransportError.invalidHost
        }

        let objectID = try await favoritesClient.addFavorite(host: manualSonosHost, payload: payload)
        await refreshHomeFavorites(showLoading: false)
        return objectID
    }

    func removeSonosFavorite(objectID: String) async throws {
        guard hasManualSonosHost else {
            throw SonosControlTransport.TransportError.invalidHost
        }

        try await favoritesClient.removeFavorite(host: manualSonosHost, objectID: objectID)
        await refreshHomeFavorites(showLoading: false)
    }

    func loadHomeFavoritesIfNeeded() async {
        guard hasManualSonosHost else {
            homeFavoritesState = .idle
            return
        }

        guard !homeFavoritesState.hasLoadedValue else {
            return
        }

        await refreshHomeFavorites()
    }

    func recordRecentPlayIfNeeded(_ snapshot: SonosNowPlayingSnapshot) {
        guard hasManualSonosHost,
              let recentPlay = SonoicRecentPlayItem(snapshot: snapshot, observedAt: nowPlayingObservedAt)
        else {
            return
        }

        guard !shouldSuppressSnapshotRecentPlayDuringManualQueue() else {
            return
        }

        upsertRecentPlay(recentPlay)
    }

    func recordRecentFavoritePlayback(_ favorite: SonosFavoriteItem) {
        guard let payload = favorite.playablePayload else {
            return
        }

        recordRecentPlayablePayload(payload)
    }

    func recordRecentPlayablePayload(_ payload: SonosPlayablePayload) {
        upsertRecentPlay(
            SonoicRecentPlayItem(
                payload: payload,
                playedAt: .now
            )
        )
    }

    func recordRecentSourceItem(_ item: SonoicSourceItem, replayPayload providedReplayPayload: SonosPlayablePayload? = nil) {
        let replayPayload: SonosPlayablePayload?
        if let providedPayload = providedReplayPayload {
            replayPayload = providedPayload
        } else if case .sonosNative(let payload) = item.playbackCapability {
            replayPayload = payload
        } else {
            replayPayload = nil
        }

        upsertRecentPlay(
            SonoicRecentPlayItem(
                id: "source-\(item.service.id)-\(item.kind.rawValue)-\(item.serviceItemID ?? item.id)",
                title: item.title,
                artistName: item.subtitle,
                albumTitle: nil,
                sourceName: item.service.name,
                artworkURL: item.artworkURL,
                artworkIdentifier: item.artworkIdentifier,
                service: item.service,
                lastPlayedAt: .now,
                playbackURI: replayPayload?.uri,
                playbackMetadataXML: replayPayload?.metadataXML,
                favoriteKind: recentFavoriteKind(for: item),
                sourceItemID: item.serviceItemID,
                appleMusicCatalogID: item.sourceReference?.catalogID,
                appleMusicLibraryID: item.sourceReference?.libraryID,
                sourceItemKindRawValue: item.kind.rawValue
            )
        )
    }

    func playRecentItem(_ recentItem: SonoicRecentPlayItem) async -> Bool {
        guard let favorite = recentItem.replayFavorite else {
            return false
        }

        return await playManualSonosFavorite(favorite)
    }

    private func upsertRecentPlay(_ recentPlay: SonoicRecentPlayItem) {
        guard shouldIncludeInHomeRecentHistory(recentPlay) else {
            return
        }

        let existingRecentPlay = recentPlays.first {
            shouldIncludeInHomeRecentHistory($0)
                && ($0.id == recentPlay.id || $0.matchesHomeHistoryIdentity(of: recentPlay))
        }
        let resolvedRecentPlay = existingRecentPlay?.enriched(with: recentPlay) ?? recentPlay
        let launchedQueueRecentItems = recentPlay.favoriteKind == .collection ? manualQueueRecentItems() : []

        var nextRecentPlays = recentPlays.filter { item in
            shouldIncludeInHomeRecentHistory(item)
                && item.id != resolvedRecentPlay.id
                && !item.matchesHomeHistoryIdentity(of: resolvedRecentPlay)
                && !launchedQueueRecentItems.contains { queueItem in
                    queueItem.matchesHomeHistoryIdentity(of: item)
                }
        }
        nextRecentPlays.insert(resolvedRecentPlay, at: 0)

        if nextRecentPlays.count > Self.homeRecentPlayLimit {
            nextRecentPlays = Array(nextRecentPlays.prefix(Self.homeRecentPlayLimit))
        }

        guard nextRecentPlays != recentPlays else {
            return
        }

        recentPlays = nextRecentPlays
        settingsStore.saveRecentPlays(nextRecentPlays)
    }

    private func visibleUniqueRecentPlays(from recentPlays: [SonoicRecentPlayItem]) -> [SonoicRecentPlayItem] {
        var seenIdentities: Set<String> = []

        return recentPlays.compactMap { recentPlay in
            guard shouldIncludeInHomeRecentHistory(recentPlay),
                  seenIdentities.insert(recentPlay.homeHistoryIdentity).inserted
            else {
                return nil
            }

            return recentPlay
        }
    }

    private func shouldIncludeInHomeRecentHistory(_ item: SonoicRecentPlayItem) -> Bool {
        guard item.isVisibleInHomeHistory else {
            return false
        }

        guard item.service == .appleMusic else {
            return true
        }

        // Match Sonos Home: Apple Music recents are collection launches
        // (albums/playlists), not every individual track that happens to play.
        return item.favoriteKind == .collection
    }

    private func shouldSuppressSnapshotRecentPlayDuringManualQueue() -> Bool {
        guard let payloads = manualQueueContextPayloads,
              !payloads.isEmpty
        else {
            return false
        }

        return true
    }

    private func manualQueueRecentItems() -> [SonoicRecentPlayItem] {
        manualQueueContextPayloads?.map {
            SonoicRecentPlayItem(payload: $0, playedAt: .now)
        } ?? []
    }

    private func recentFavoriteKind(for item: SonoicSourceItem) -> SonosFavoriteItem.Kind {
        switch item.kind {
        case .album, .artist, .playlist, .station:
            .collection
        case .song, .unknown:
            .item
        }
    }

    private func orderedUniqueServices(_ services: [SonosServiceDescriptor]) -> [SonosServiceDescriptor] {
        var seenServiceIDs: Set<String> = []

        return services.compactMap { service in
            guard seenServiceIDs.insert(service.id).inserted else {
                return nil
            }

            return service
        }
    }
}
