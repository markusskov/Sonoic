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
        let services = orderedUniqueServices(favoriteServices + recentServices + [currentService].compactMap { $0 })

        return services.map { service in
            let matchingFavorites = favorites.filter { $0.service?.id == service.id }
            let matchingRecentPlays = recentPlays.filter { $0.service?.id == service.id }

            return SonoicSource(
                service: service,
                favoriteCount: matchingFavorites.count,
                collectionCount: matchingFavorites.filter(\.isCollectionLike).count,
                recentCount: matchingRecentPlays.count,
                isCurrent: currentService?.id == service.id
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

        upsertRecentPlay(recentPlay)
    }

    func recordRecentFavoritePlayback(_ favorite: SonosFavoriteItem) {
        upsertRecentPlay(
            SonoicRecentPlayItem(
                favorite: favorite,
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

        var nextRecentPlays = recentPlays.filter {
            $0.isVisibleInHomeHistory
                && $0.id != resolvedRecentPlay.id
                && !$0.matchesHomeHistoryIdentity(of: resolvedRecentPlay)
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
