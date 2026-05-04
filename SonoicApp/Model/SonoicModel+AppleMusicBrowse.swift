import Foundation

extension SonoicModel {
    func appleMusicBrowseState(for destination: SonoicAppleMusicBrowseDestination) -> SonoicAppleMusicBrowseState {
        appleMusicBrowseStates[destination] ?? SonoicAppleMusicBrowseState(destination: destination)
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
        appleMusicBrowseStates[destination] = SonoicAppleMusicBrowseState(
            destination: destination,
            sections: currentState.sections,
            genres: currentState.genres,
            status: .loading,
            lastUpdatedAt: currentState.lastUpdatedAt
        )

        appleMusicBrowseLoadTasks[destination] = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let state = try await self.appleMusicCatalogSearchClient.fetchBrowseState(for: destination)
                guard !Task.isCancelled else {
                    return
                }

                self.appleMusicBrowseStates[destination] = SonoicAppleMusicBrowseState(
                    destination: destination,
                    sections: state.sections,
                    genres: state.genres,
                    status: state.status,
                    lastUpdatedAt: .now
                )
                self.recordAppleMusicRequestSuccess()
            } catch where SonoicAppleMusicCatalogSearchClient.isCancellation(error) {
                return
            } catch {
                self.appleMusicBrowseStates[destination] = SonoicAppleMusicBrowseState(
                    destination: destination,
                    sections: self.appleMusicBrowseState(for: destination).sections,
                    genres: self.appleMusicBrowseState(for: destination).genres,
                    status: .failed(
                        self.appleMusicFailureDetail(from: error, endpointFamily: .browse)
                    ),
                    lastUpdatedAt: self.appleMusicBrowseState(for: destination).lastUpdatedAt
                )
            }

            self.appleMusicBrowseLoadTasks[destination] = nil
        }
    }
}
