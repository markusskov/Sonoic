import Foundation

extension SonoicModel {
    var homeFavoriteCollections: [SonosFavoriteItem] {
        homeFavoritesState.snapshot?.collectionItems ?? []
    }

    var homeSourceSummaries: [SonoicHomeSourceSummary] {
        let favorites = homeFavoritesState.snapshot?.items ?? []
        let favoriteServices = favorites.compactMap(\.service)
        let recentServices = recentPlays.compactMap(\.service)
        let currentService = SonosServiceCatalog.descriptor(named: nowPlaying.sourceName)
        let services = orderedUniqueServices(favoriteServices + recentServices + [currentService].compactMap { $0 })

        return services.map { service in
            let matchingFavorites = favorites.filter { $0.service?.id == service.id }
            let matchingRecentPlays = recentPlays.filter { $0.service?.id == service.id }

            return SonoicHomeSourceSummary(
                service: service,
                favoriteCount: matchingFavorites.count,
                collectionCount: matchingFavorites.filter(\.isCollectionLike).count,
                recentCount: matchingRecentPlays.count,
                isCurrent: currentService?.id == service.id
            )
        }
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
        if let firstRecentPlay = recentPlays.first,
           firstRecentPlay.id == recentPlay.id
        {
            let enrichedRecentPlay = firstRecentPlay.enriched(with: recentPlay)
            guard enrichedRecentPlay != firstRecentPlay else {
                return
            }

            recentPlays[0] = enrichedRecentPlay
            settingsStore.saveRecentPlays(recentPlays)
            return
        }

        var nextRecentPlays = recentPlays.filter { $0.id != recentPlay.id }
        nextRecentPlays.insert(recentPlay, at: 0)

        if nextRecentPlays.count > Self.homeRecentPlayLimit {
            nextRecentPlays = Array(nextRecentPlays.prefix(Self.homeRecentPlayLimit))
        }

        guard nextRecentPlays != recentPlays else {
            return
        }

        recentPlays = nextRecentPlays
        settingsStore.saveRecentPlays(nextRecentPlays)
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
