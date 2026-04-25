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
