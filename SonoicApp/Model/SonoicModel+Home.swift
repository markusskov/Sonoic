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

    func sourceSearchState(for source: SonoicSource) -> SonoicSourceSearchState {
        sourceSearchStates[source.service.id] ?? SonoicSourceSearchState(service: source.service)
    }

    func recentSourceSearches(for source: SonoicSource) -> [SonoicRecentSourceSearch] {
        recentSourceSearches.filter { $0.serviceID == source.service.id }
    }

    func clearRecentSourceSearches(for source: SonoicSource) {
        let nextSearches = recentSourceSearches.filter { $0.serviceID != source.service.id }
        guard nextSearches != recentSourceSearches else {
            return
        }

        recentSourceSearches = nextSearches
        settingsStore.saveRecentSourceSearches(nextSearches)
    }

    func updateSourceSearchQuery(_ query: String, for source: SonoicSource) {
        let currentState = sourceSearchState(for: source)
        sourceSearchStates[source.service.id] = SonoicSourceSearchState(
            query: query,
            service: source.service,
            scope: currentState.scope
        )
    }

    func updateSourceSearchScope(_ scope: SonoicSourceSearchScope, for source: SonoicSource) {
        let currentState = sourceSearchState(for: source)
        let shouldPreserveResults = scope != currentState.scope && currentState.hasQuery && !currentState.items.isEmpty

        sourceSearchStates[source.service.id] = SonoicSourceSearchState(
            query: currentState.query,
            service: source.service,
            scope: scope,
            items: scope == currentState.scope || shouldPreserveResults ? currentState.items : [],
            status: scope == currentState.scope || shouldPreserveResults ? currentState.status : .idle,
            lastUpdatedAt: scope == currentState.scope || shouldPreserveResults ? currentState.lastUpdatedAt : nil
        )
    }

    func searchSourceCatalog(for source: SonoicSource) async {
        let currentState = sourceSearchState(for: source)
        guard let query = currentState.query.sonoicNonEmptyTrimmed else {
            updateSourceSearchQuery("", for: source)
            return
        }
        let searchScope = currentState.scope

        sourceSearchStates[source.service.id] = SonoicSourceSearchState(
            query: query,
            service: source.service,
            scope: searchScope,
            items: currentState.items,
            status: .loading,
            lastUpdatedAt: currentState.lastUpdatedAt
        )

        do {
            let items: [SonoicSourceItem]
            switch source.service.kind {
            case .appleMusic:
                refreshAppleMusicAuthorizationState()
                guard appleMusicAuthorizationState.allowsCatalogSearch else {
                    guard shouldApplySourceSearchResponse(
                        serviceID: source.service.id,
                        query: query,
                        scope: searchScope
                    ) else {
                        return
                    }

                    sourceSearchStates[source.service.id] = SonoicSourceSearchState(
                        query: query,
                        service: source.service,
                        scope: searchScope,
                        items: currentState.items,
                        status: .failed(appleMusicAuthorizationState.detail),
                        lastUpdatedAt: currentState.lastUpdatedAt
                    )
                    return
                }

                items = try await appleMusicCatalogSearchClient.searchCatalog(
                    term: query,
                    scope: searchScope
                )
                recordAppleMusicRequestSuccess()
            case .spotify, .sonosRadio, .genericStreaming:
                items = []
            }

            guard shouldApplySourceSearchResponse(
                serviceID: source.service.id,
                query: query,
                scope: searchScope
            ) else {
                return
            }

            sourceSearchStates[source.service.id] = SonoicSourceSearchState(
                query: query,
                service: source.service,
                scope: searchScope,
                items: items,
                status: .loaded,
                lastUpdatedAt: .now
            )
            recordRecentSourceSearch(query, for: source)
        } catch where SonoicAppleMusicCatalogSearchClient.isCancellation(error) {
            guard shouldApplySourceSearchResponse(
                serviceID: source.service.id,
                query: query,
                scope: searchScope
            ) else {
                return
            }

            sourceSearchStates[source.service.id] = SonoicSourceSearchState(
                query: query,
                service: source.service,
                scope: searchScope,
                items: sourceSearchStates[source.service.id]?.items ?? currentState.items,
                status: .idle,
                lastUpdatedAt: sourceSearchStates[source.service.id]?.lastUpdatedAt ?? currentState.lastUpdatedAt
            )
        } catch {
            guard shouldApplySourceSearchResponse(
                serviceID: source.service.id,
                query: query,
                scope: searchScope
            ) else {
                return
            }

            sourceSearchStates[source.service.id] = SonoicSourceSearchState(
                query: query,
                service: source.service,
                scope: searchScope,
                items: sourceSearchStates[source.service.id]?.items ?? currentState.items,
                status: .failed(
                    appleMusicFailureDetail(from: error, endpointFamily: .search)
                ),
                lastUpdatedAt: sourceSearchStates[source.service.id]?.lastUpdatedAt ?? currentState.lastUpdatedAt
            )
        }
    }

    func appleMusicArtistRouteItem(named artistName: String) async -> SonoicSourceItem? {
        guard let trimmedName = artistName.sonoicNonEmptyTrimmed else {
            return nil
        }

        refreshAppleMusicAuthorizationState()
        guard appleMusicAuthorizationState.allowsCatalogSearch else {
            return nil
        }

        do {
            let items = try await appleMusicCatalogSearchClient.searchCatalog(
                term: trimmedName,
                scope: .artists
            )
            recordAppleMusicRequestSuccess()

            return items.first { item in
                item.kind == .artist
                    && item.title.compare(
                        trimmedName,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame
            } ?? items.first { $0.kind == .artist }
        } catch {
            return nil
        }
    }

    private func shouldApplySourceSearchResponse(
        serviceID: String,
        query: String,
        scope: SonoicSourceSearchScope
    ) -> Bool {
        let state = sourceSearchStates[serviceID]
        return state?.query.sonoicNonEmptyTrimmed == query && state?.scope == scope
    }

    private func recordRecentSourceSearch(_ query: String, for source: SonoicSource) {
        guard let trimmedQuery = query.sonoicNonEmptyTrimmed else {
            return
        }

        let recentSearch = SonoicRecentSourceSearch(
            serviceID: source.service.id,
            query: trimmedQuery,
            searchedAt: .now
        )
        var nextSearches = recentSourceSearches.filter { $0.id != recentSearch.id }
        nextSearches.insert(recentSearch, at: 0)

        if nextSearches.count > Self.recentSourceSearchLimit {
            nextSearches = Array(nextSearches.prefix(Self.recentSourceSearchLimit))
        }

        guard nextSearches != recentSourceSearches else {
            return
        }

        recentSourceSearches = nextSearches
        settingsStore.saveRecentSourceSearches(nextSearches)
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
                appleMusicCatalogID: item.appleMusicIdentity?.catalogID,
                appleMusicLibraryID: item.appleMusicIdentity?.libraryID,
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
