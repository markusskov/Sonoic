import Foundation

extension SonoicModel {
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
}
