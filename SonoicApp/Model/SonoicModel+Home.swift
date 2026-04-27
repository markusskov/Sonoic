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

    func playRecentItem(_ recentItem: SonoicRecentPlayItem) async -> Bool {
        guard let favorite = recentItem.replayFavorite else {
            return false
        }

        return await playManualSonosFavorite(favorite)
    }

    private func upsertRecentPlay(_ recentPlay: SonoicRecentPlayItem) {
        guard recentPlay.isVisibleInHomeHistory else {
            return
        }

        let existingRecentPlay = recentPlays.first {
            $0.isVisibleInHomeHistory
                && ($0.id == recentPlay.id || $0.matchesHomeHistoryIdentity(of: recentPlay))
        }
        let resolvedRecentPlay = existingRecentPlay?.enriched(with: recentPlay) ?? recentPlay
        let launchedQueueRecentItems = recentPlay.favoriteKind == .collection ? manualQueueRecentItems() : []

        var nextRecentPlays = recentPlays.filter { item in
            item.isVisibleInHomeHistory
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
            guard recentPlay.isVisibleInHomeHistory,
                  seenIdentities.insert(recentPlay.homeHistoryIdentity).inserted
            else {
                return nil
            }

            return recentPlay
        }
    }

    private func shouldSuppressSnapshotRecentPlayDuringManualQueue() -> Bool {
        guard let payloads = manualQueueContextPayloads,
              !payloads.isEmpty
        else {
            return false
        }

        let observedURIs = [
            normalizedRecentPlaybackURI(nowPlayingDiagnostics.currentURI),
            normalizedRecentPlaybackURI(nowPlayingDiagnostics.trackURI),
        ].compactMap(\.self)

        return payloads.contains { payload in
            guard let payloadURI = normalizedRecentPlaybackURI(payload.uri) else {
                return false
            }

            if observedURIs.contains(payloadURI) {
                return true
            }

            guard let itemID = recentPlaybackItemID(from: payload.uri) else {
                return false
            }

            return observedURIs.contains { $0.contains(itemID) }
        }
    }

    private func manualQueueRecentItems() -> [SonoicRecentPlayItem] {
        manualQueueContextPayloads?.map {
            SonoicRecentPlayItem(payload: $0, playedAt: .now)
        } ?? []
    }

    private func normalizedRecentPlaybackURI(_ uri: String?) -> String? {
        uri?
            .replacingOccurrences(of: "&amp;", with: "&")
            .sonoicNonEmptyTrimmed?
            .lowercased()
    }

    private func recentPlaybackItemID(from uri: String) -> String? {
        guard let normalizedURI = normalizedRecentPlaybackURI(uri),
              let idStartRange = normalizedURI.range(of: "%3a")
        else {
            return nil
        }

        let valueAfterPrefix = normalizedURI[idStartRange.upperBound...]
        let id = valueAfterPrefix.split(separator: "?", maxSplits: 1).first.map(String.init)
        return id?.sonoicNonEmptyTrimmed
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
