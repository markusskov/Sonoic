import Foundation

extension SonoicModel {
    func appleMusicLibraryState(for destination: SonoicAppleMusicLibraryDestination) -> SonoicAppleMusicLibraryState {
        appleMusicLibraryStates[destination] ?? SonoicAppleMusicLibraryState(destination: destination)
    }

    func loadAppleMusicRecentlyAdded(force: Bool = false) {
        if appleMusicRecentlyAddedState.isLoading || (!force && appleMusicRecentlyAddedState.status == .loaded) {
            return
        }

        refreshAppleMusicAuthorizationState()
        guard appleMusicAuthorizationState.allowsCatalogSearch else {
            appleMusicRecentlyAddedState = SonoicAppleMusicRecentlyAddedState(
                status: .failed(appleMusicAuthorizationState.detail)
            )
            return
        }

        if appleMusicServiceDetails.hasCloudLibraryEnabled == .some(false) {
            appleMusicRecentlyAddedState = SonoicAppleMusicRecentlyAddedState(
                status: .failed("iCloud Music Library is not enabled for this Apple Music account.")
            )
            return
        }

        appleMusicRecentlyAddedLoadTask?.cancel()
        appleMusicRecentlyAddedState = SonoicAppleMusicRecentlyAddedState(
            items: appleMusicRecentlyAddedState.items,
            status: .loading,
            lastUpdatedAt: appleMusicRecentlyAddedState.lastUpdatedAt
        )

        appleMusicRecentlyAddedLoadTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let items = try await self.appleMusicCatalogSearchClient.fetchRecentlyAdded()
                guard !Task.isCancelled else {
                    return
                }

                self.appleMusicRecentlyAddedState = SonoicAppleMusicRecentlyAddedState(
                    items: items,
                    status: .loaded,
                    lastUpdatedAt: .now
                )
                self.recordAppleMusicRequestSuccess()
            } catch where SonoicAppleMusicCatalogSearchClient.isCancellation(error) {
                return
            } catch {
                self.appleMusicRecentlyAddedState = SonoicAppleMusicRecentlyAddedState(
                    items: self.appleMusicRecentlyAddedState.items,
                    status: .failed(
                        self.appleMusicFailureDetail(from: error, endpointFamily: .recentlyAdded)
                    ),
                    lastUpdatedAt: self.appleMusicRecentlyAddedState.lastUpdatedAt
                )
            }

            self.appleMusicRecentlyAddedLoadTask = nil
        }
    }

    func loadAppleMusicLibraryDestination(
        _ destination: SonoicAppleMusicLibraryDestination,
        force: Bool = false,
        append: Bool = false
    ) {
        let currentState = appleMusicLibraryState(for: destination)

        if currentState.isLoading || (!append && !force && currentState.status == .loaded) {
            return
        }

        let offset = append ? currentState.nextOffset : nil
        if append && offset == nil {
            return
        }

        refreshAppleMusicAuthorizationState()
        guard appleMusicAuthorizationState.allowsCatalogSearch else {
            appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(
                destination: destination,
                items: append ? currentState.items : [],
                status: .failed(appleMusicAuthorizationState.detail),
                lastUpdatedAt: currentState.lastUpdatedAt,
                nextOffset: append ? currentState.nextOffset : nil
            )
            return
        }

        if appleMusicServiceDetails.hasCloudLibraryEnabled == .some(false) {
            appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(
                destination: destination,
                items: append ? currentState.items : [],
                status: .failed("iCloud Music Library is not enabled for this Apple Music account."),
                lastUpdatedAt: currentState.lastUpdatedAt,
                nextOffset: append ? currentState.nextOffset : nil
            )
            return
        }

        appleMusicLibraryLoadTasks[destination]?.cancel()
        appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(
            destination: destination,
            items: currentState.items,
            status: .loading,
            lastUpdatedAt: currentState.lastUpdatedAt,
            nextOffset: currentState.nextOffset
        )

        appleMusicLibraryLoadTasks[destination] = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let page = try await self.fetchAppleMusicLibraryItems(
                    for: destination,
                    offset: offset
                )
                guard !Task.isCancelled else {
                    return
                }
                let nextItems = append ? currentState.items + page.items : page.items

                self.appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(
                    destination: destination,
                    items: nextItems,
                    status: .loaded,
                    lastUpdatedAt: .now,
                    nextOffset: page.nextOffset
                )
                self.recordAppleMusicRequestSuccess()
            } catch where SonoicAppleMusicCatalogSearchClient.isCancellation(error) {
                return
            } catch {
                self.appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(
                    destination: destination,
                    items: self.appleMusicLibraryState(for: destination).items,
                    status: .failed(
                        self.appleMusicFailureDetail(from: error, endpointFamily: .library)
                    ),
                    lastUpdatedAt: self.appleMusicLibraryState(for: destination).lastUpdatedAt,
                    nextOffset: self.appleMusicLibraryState(for: destination).nextOffset
                )
            }

            self.appleMusicLibraryLoadTasks[destination] = nil
        }
    }

    private func fetchAppleMusicLibraryItems(
        for destination: SonoicAppleMusicLibraryDestination,
        offset: Int?
    ) async throws -> SonoicSourceItemPage {
        switch destination {
        case .playlists:
            try await appleMusicCatalogSearchClient.fetchLibraryPlaylists(
                limit: destination.initialLoadLimit,
                offset: offset
            )
        case .albums:
            try await appleMusicCatalogSearchClient.fetchLibraryAlbums(
                limit: destination.initialLoadLimit,
                offset: offset
            )
        case .songs:
            try await appleMusicCatalogSearchClient.fetchLibrarySongs(
                limit: destination.initialLoadLimit,
                offset: offset
            )
        case .artists:
            try await appleMusicCatalogSearchClient.fetchLibraryArtists(
                limit: destination.initialLoadLimit,
                offset: offset
            )
        }
    }
}
