import Foundation

extension SonoicModel {
    func refreshAppleMusicAuthorizationState() {
        musicKitDiagnostics = .current
        appleMusicAuthorizationState = appleMusicCatalogSearchClient.currentAuthorizationState()
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
        } catch {
            appleMusicServiceDetails = .failed(error.localizedDescription)
        }
    }

    func appleMusicLibraryState(for destination: SonoicAppleMusicLibraryDestination) -> SonoicAppleMusicLibraryState {
        appleMusicLibraryStates[destination] ?? SonoicAppleMusicLibraryState(destination: destination)
    }

    func appleMusicItemDetailState(for item: SonoicSourceItem) -> SonoicAppleMusicItemDetailState {
        appleMusicItemDetailStates[item.id] ?? SonoicAppleMusicItemDetailState(item: item)
    }

    func loadAppleMusicItemDetail(
        for item: SonoicSourceItem,
        force: Bool = false
    ) {
        let currentState = appleMusicItemDetailState(for: item)

        if currentState.isLoading || (!force && currentState.status == .loaded) {
            return
        }

        guard item.service.kind == .appleMusic,
              item.serviceItemID != nil
        else {
            appleMusicItemDetailStates[item.id] = SonoicAppleMusicItemDetailState(
                item: item,
                status: .loaded
            )
            return
        }

        refreshAppleMusicAuthorizationState()
        guard appleMusicAuthorizationState.allowsCatalogSearch else {
            appleMusicItemDetailStates[item.id] = SonoicAppleMusicItemDetailState(
                item: item,
                status: .failed(appleMusicAuthorizationState.detail)
            )
            return
        }

        appleMusicItemDetailLoadTasks[item.id]?.cancel()
        appleMusicItemDetailStates[item.id] = SonoicAppleMusicItemDetailState(item: item, status: .loading)

        appleMusicItemDetailLoadTasks[item.id] = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let sections = try await self.appleMusicCatalogSearchClient.fetchItemDetailSections(for: item)
                guard !Task.isCancelled else {
                    return
                }

                self.appleMusicItemDetailStates[item.id] = SonoicAppleMusicItemDetailState(
                    item: item,
                    sections: sections,
                    status: .loaded
                )
            } catch is CancellationError {
                if self.appleMusicItemDetailState(for: item).isLoading {
                    self.appleMusicItemDetailStates[item.id] = SonoicAppleMusicItemDetailState(item: item)
                }
            } catch {
                self.appleMusicItemDetailStates[item.id] = SonoicAppleMusicItemDetailState(
                    item: item,
                    status: .failed(error.localizedDescription)
                )
            }

            self.appleMusicItemDetailLoadTasks[item.id] = nil
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
            } catch is CancellationError {
                if self.appleMusicLibraryState(for: destination).isLoading {
                    self.appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(destination: destination)
                }
            } catch {
                self.appleMusicLibraryStates[destination] = SonoicAppleMusicLibraryState(
                    destination: destination,
                    status: .failed(error.localizedDescription)
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
}
