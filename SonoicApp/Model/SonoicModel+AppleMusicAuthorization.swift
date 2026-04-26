import Foundation

extension SonoicModel {
    func refreshAppleMusicAuthorizationState() {
        musicKitDiagnostics = .current
        appleMusicAuthorizationState = appleMusicCatalogSearchClient.currentAuthorizationState()

        if !appleMusicAuthorizationState.allowsCatalogSearch {
            appleMusicRequestReadiness = .idle
        }
    }

    func requestAppleMusicAuthorization() async {
        guard appleMusicAuthorizationState.canRequestAuthorization else {
            refreshAppleMusicAuthorizationState()
            return
        }

        appleMusicAuthorizationState = SonoicAppleMusicAuthorizationState(status: .requesting)
        appleMusicAuthorizationState = await appleMusicCatalogSearchClient.requestAuthorizationState()

        if appleMusicAuthorizationState.allowsCatalogSearch {
            await refreshAppleMusicServiceDetails()
        }
    }

    func refreshAppleMusicServiceDetails() async {
        refreshAppleMusicAuthorizationState()
        guard appleMusicAuthorizationState.allowsCatalogSearch else {
            appleMusicServiceDetails = .idle
            return
        }

        appleMusicServiceDetails.status = .loading

        do {
            appleMusicServiceDetails = try await appleMusicCatalogSearchClient.fetchServiceDetails()
            recordAppleMusicRequestSuccess()
        } catch {
            appleMusicServiceDetails = .failed(
                appleMusicFailureDetail(from: error, endpointFamily: .serviceDetails)
            )
        }
    }

    func appleMusicLibraryState(for destination: SonoicAppleMusicLibraryDestination) -> SonoicAppleMusicLibraryState {
        appleMusicLibraryStates[destination] ?? SonoicAppleMusicLibraryState(destination: destination)
    }

    func appleMusicBrowseState(for destination: SonoicAppleMusicBrowseDestination) -> SonoicAppleMusicBrowseState {
        appleMusicBrowseStates[destination] ?? SonoicAppleMusicBrowseState(destination: destination)
    }

    func appleMusicItemDetailState(for item: SonoicSourceItem) -> SonoicAppleMusicItemDetailState {
        appleMusicItemDetailStates[item.appleMusicDetailCacheKey] ?? SonoicAppleMusicItemDetailState(item: item)
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
        appleMusicRecentlyAddedState = SonoicAppleMusicRecentlyAddedState(status: .loading)

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
                    status: .loaded
                )
                self.recordAppleMusicRequestSuccess()
            } catch is CancellationError {
                if self.appleMusicRecentlyAddedState.isLoading {
                    self.appleMusicRecentlyAddedState = SonoicAppleMusicRecentlyAddedState()
                }
            } catch {
                self.appleMusicRecentlyAddedState = SonoicAppleMusicRecentlyAddedState(
                    status: .failed(
                        self.appleMusicFailureDetail(from: error, endpointFamily: .recentlyAdded)
                    )
                )
            }

            self.appleMusicRecentlyAddedLoadTask = nil
        }
    }

    func loadAppleMusicBrowseDestination(
        _ destination: SonoicAppleMusicBrowseDestination,
        force: Bool = false
    ) {
        let currentState = appleMusicBrowseState(for: destination)

        if currentState.isLoading || (!force && currentState.status == .loaded) {
            return
        }

        refreshAppleMusicAuthorizationState()
        guard appleMusicAuthorizationState.allowsCatalogSearch else {
            appleMusicBrowseStates[destination] = SonoicAppleMusicBrowseState(
                destination: destination,
                status: .failed(appleMusicAuthorizationState.detail)
            )
            return
        }

        appleMusicBrowseLoadTasks[destination]?.cancel()
        appleMusicBrowseStates[destination] = SonoicAppleMusicBrowseState(destination: destination, status: .loading)

        appleMusicBrowseLoadTasks[destination] = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let state = try await self.appleMusicCatalogSearchClient.fetchBrowseState(for: destination)
                guard !Task.isCancelled else {
                    return
                }

                self.appleMusicBrowseStates[destination] = state
                self.recordAppleMusicRequestSuccess()
            } catch is CancellationError {
                if self.appleMusicBrowseState(for: destination).isLoading {
                    self.appleMusicBrowseStates[destination] = SonoicAppleMusicBrowseState(destination: destination)
                }
            } catch {
                self.appleMusicBrowseStates[destination] = SonoicAppleMusicBrowseState(
                    destination: destination,
                    status: .failed(
                        self.appleMusicFailureDetail(from: error, endpointFamily: .browse)
                    )
                )
            }

            self.appleMusicBrowseLoadTasks[destination] = nil
        }
    }

    func loadAppleMusicItemDetail(
        for item: SonoicSourceItem,
        force: Bool = false
    ) {
        let detailCacheKey = item.appleMusicDetailCacheKey
        let currentState = appleMusicItemDetailState(for: item)

        if currentState.isLoading || (!force && currentState.status == .loaded) {
            return
        }

        guard item.service.kind == .appleMusic,
              item.appleMusicIdentity?.routedID(for: item.origin) ?? item.serviceItemID != nil
        else {
            appleMusicItemDetailStates[detailCacheKey] = SonoicAppleMusicItemDetailState(
                item: item,
                status: .loaded
            )
            return
        }

        refreshAppleMusicAuthorizationState()
        guard appleMusicAuthorizationState.allowsCatalogSearch else {
            appleMusicItemDetailStates[detailCacheKey] = SonoicAppleMusicItemDetailState(
                item: item,
                status: .failed(appleMusicAuthorizationState.detail)
            )
            return
        }

        appleMusicItemDetailLoadTasks[detailCacheKey]?.cancel()
        appleMusicItemDetailStates[detailCacheKey] = SonoicAppleMusicItemDetailState(item: item, status: .loading)

        appleMusicItemDetailLoadTasks[detailCacheKey] = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sections = try await self.appleMusicCatalogSearchClient.fetchItemDetailSections(for: item)
                guard !Task.isCancelled else {
                    return
                }

                self.appleMusicItemDetailStates[detailCacheKey] = SonoicAppleMusicItemDetailState(
                    item: item,
                    sections: sections,
                    status: .loaded
                )
                self.recordAppleMusicRequestSuccess()
            } catch is CancellationError {
                if self.appleMusicItemDetailState(for: item).isLoading {
                    self.appleMusicItemDetailStates[detailCacheKey] = SonoicAppleMusicItemDetailState(item: item)
                }
            } catch {
                self.appleMusicItemDetailStates[detailCacheKey] = SonoicAppleMusicItemDetailState(
                    item: item,
                    status: .failed(
                        self.appleMusicFailureDetail(from: error, endpointFamily: .itemDetail)
                    )
                )
            }

            self.appleMusicItemDetailLoadTasks[detailCacheKey] = nil
        }
    }

    func loadAppleMusicLibraryDestination(
        _ destination: SonoicAppleMusicLibraryDestination,
        force: Bool = false
    ) {
        let currentState = appleMusicLibraryState(for: destination)

        if currentState.isLoading || (!force && currentState.status == .loaded) {
            return
        }

        refreshAppleMusicAuthorizationState()
        guard appleMusicAuthorizationState.allowsCatalogSearch else {
            appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(
                destination: destination,
                status: .failed(appleMusicAuthorizationState.detail)
            )
            return
        }

        if appleMusicServiceDetails.hasCloudLibraryEnabled == .some(false) {
            appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(
                destination: destination,
                status: .failed("iCloud Music Library is not enabled for this Apple Music account.")
            )
            return
        }

        appleMusicLibraryLoadTasks[destination]?.cancel()
        appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(destination: destination, status: .loading)

        appleMusicLibraryLoadTasks[destination] = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let items = try await self.fetchAppleMusicLibraryItems(for: destination)
                guard !Task.isCancelled else {
                    return
                }

                self.appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(
                    destination: destination,
                    items: items,
                    status: .loaded
                )
                self.recordAppleMusicRequestSuccess()
            } catch is CancellationError {
                if self.appleMusicLibraryState(for: destination).isLoading {
                    self.appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(destination: destination)
                }
            } catch {
                self.appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(
                    destination: destination,
                    status: .failed(
                        self.appleMusicFailureDetail(from: error, endpointFamily: .library)
                    )
                )
            }

            self.appleMusicLibraryLoadTasks[destination] = nil
        }
    }

    private func fetchAppleMusicLibraryItems(
        for destination: SonoicAppleMusicLibraryDestination
    ) async throws -> [SonoicSourceItem] {
        switch destination {
        case .playlists:
            try await appleMusicCatalogSearchClient.fetchLibraryPlaylists()
        case .albums:
            try await appleMusicCatalogSearchClient.fetchLibraryAlbums()
        case .songs:
            try await appleMusicCatalogSearchClient.fetchLibrarySongs()
        case .artists:
            try await appleMusicCatalogSearchClient.fetchLibraryArtists()
        }
    }

    func recordAppleMusicRequestSuccess() {
        appleMusicRequestReadiness = .ready(preserving: appleMusicRequestReadiness)
    }

    func appleMusicFailureDetail(
        from error: Error,
        endpointFamily: SonoicAppleMusicEndpointFamily
    ) -> String {
        let failure = SonoicAppleMusicCatalogSearchClient.appleMusicRequestFailure(
            from: error,
            endpointFamily: endpointFamily
        )
        appleMusicRequestReadiness = .failed(failure)
        return failure.displayDetail
    }
}
