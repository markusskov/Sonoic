import Foundation

extension SonoicModel {
    func sourceSearchState(for source: SonoicSource) -> SonoicSourceSearchState {
        sourceSearchStates[source.service.id] ?? SonoicSourceSearchState(service: source.service)
    }

    func recentSourceSearches(for sources: [SonoicSource]) -> [SonoicRecentSourceSearch] {
        let sourceIDs = Set(sources.map(\.service.id))
        var seenQueries = Set<String>()

        return recentSourceSearches
            .filter { sourceIDs.contains($0.serviceID) }
            .filter { search in
                guard let normalizedQuery = search.query.sonoicNonEmptyTrimmed?.lowercased() else {
                    return false
                }

                return seenQueries.insert(normalizedQuery).inserted
            }
    }

    func clearRecentSourceSearches(for sources: [SonoicSource]) {
        let sourceIDs = Set(sources.map(\.service.id))
        let nextSearches = recentSourceSearches.filter { !sourceIDs.contains($0.serviceID) }
        guard nextSearches != recentSourceSearches else {
            return
        }

        recentSourceSearches = nextSearches
        settingsStore.saveRecentSourceSearches(nextSearches)
    }

    func updateSourceSearchSessionQuery(_ query: String) {
        sourceSearchSession.query = query
    }

    func updateSourceSearchSessionScope(_ scope: SonoicSourceSearchScope) {
        sourceSearchSession.scope = scope
    }

    func updateSourceSearchSessionServiceFilter(_ serviceID: String?) {
        sourceSearchSession.selectedServiceID = serviceID
    }

    func updateSourceSearchQuery(_ query: String, for source: SonoicSource) {
        let currentState = sourceSearchState(for: source)
        let shouldPreserveResults = currentState.query.sonoicNonEmptyTrimmed == query.sonoicNonEmptyTrimmed
        sourceSearchStates[source.service.id] = SonoicSourceSearchState(
            query: query,
            service: source.service,
            scope: currentState.scope,
            items: shouldPreserveResults ? currentState.items : [],
            status: shouldPreserveResults ? currentState.status : .idle,
            lastUpdatedAt: shouldPreserveResults ? currentState.lastUpdatedAt : nil
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

    func searchSourceCatalog(in sources: [SonoicSource]) async {
        guard let query = sourceSearchSession.query.sonoicNonEmptyTrimmed else {
            sourceSearchSession = SonoicSourceSearchSessionState()
            return
        }

        let searchableSources = sources.filter { source in
            sourceAdapter(for: source.service).capabilities.supportsCatalogSearch
        }
        guard !searchableSources.isEmpty else {
            return
        }

        sourceSearchSession.query = query
        sourceSearchSession.scope = .all
        sourceSearchSession.lastSubmittedQuery = query
        if searchableSources.count == 1 {
            sourceSearchSession.selectedServiceID = searchableSources.first?.service.id
        } else if let selectedServiceID = sourceSearchSession.selectedServiceID,
                  !searchableSources.contains(where: { $0.service.id == selectedServiceID }) {
            sourceSearchSession.selectedServiceID = nil
        }

        for source in searchableSources {
            updateSourceSearchQuery(query, for: source)
            updateSourceSearchScope(.all, for: source)
        }

        for source in searchableSources {
            await searchSourceCatalog(for: source)
        }
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
            let adapter = sourceAdapter(for: source.service)
            let items = try await adapter.searchCatalog(
                term: query,
                scope: searchScope,
                model: self
            )

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

            let adapter = sourceAdapter(for: source.service)
            sourceSearchStates[source.service.id] = SonoicSourceSearchState(
                query: query,
                service: source.service,
                scope: searchScope,
                items: sourceSearchStates[source.service.id]?.items ?? currentState.items,
                status: .failed(adapter.failureDetail(from: error, model: self)),
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
}
