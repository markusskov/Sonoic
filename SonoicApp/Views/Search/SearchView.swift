import SwiftUI

struct SearchView: View {
    @Environment(SonoicModel.self) private var model
    @State private var selectedServiceID = SonosServiceDescriptor.appleMusic.id
    @State private var isSearchFieldFocused = false

    private var services: [SonosServiceDescriptor] {
        orderedServices(model.homeSources.map(\.service) + SonosServiceCatalog.browsableServices)
            .filter(supportsCatalogSearch)
    }

    private var selectedService: SonosServiceDescriptor {
        services.first { $0.id == selectedServiceID } ?? .appleMusic
    }

    private var selectedSource: SonoicSource {
        model.homeSources.first { $0.service.id == selectedService.id } ?? SonoicSource(
            service: selectedService,
            favoriteCount: 0,
            collectionCount: 0,
            recentCount: 0,
            isCurrent: false,
            status: .availableForSetup
        )
    }

    private var searchState: SonoicSourceSearchState {
        model.sourceSearchState(for: selectedSource)
    }

    private var supportsSelectedCatalogSearch: Bool {
        supportsCatalogSearch(selectedService)
    }

    private var selectedRecentSearches: [SonoicRecentSourceSearch] {
        model.recentSourceSearches(for: selectedSource)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if services.count > 1 {
                    SearchServicePicker(
                        services: services,
                        selectedServiceID: $selectedServiceID
                    )
                }

                if supportsSelectedCatalogSearch {
                    SearchInputCard(
                        query: searchQueryBinding,
                        isFocused: $isSearchFieldFocused,
                        service: selectedService,
                        state: searchState,
                        supportsCatalogSearch: supportsSelectedCatalogSearch,
                        submit: searchCatalog
                    )

                    if shouldShowSearchResults {
                        SearchResultsSection(
                            state: searchState,
                            availabilityMessage: appleMusicAvailabilityMessage,
                            canRequestAuthorization: model.appleMusicAuthorizationState.canRequestAuthorization,
                            requestAuthorization: requestAppleMusicAuthorization
                        )
                    } else if isSearchFieldFocused && !selectedRecentSearches.isEmpty {
                        SearchRecentQueriesSection(
                            recentSearches: selectedRecentSearches,
                            select: selectRecentSearch,
                            clear: clearRecentSearches
                        )
                    } else {
                        SearchDiscoverySection(
                            service: selectedService,
                            isAppleMusicAvailable: model.appleMusicAuthorizationState.allowsCatalogSearch
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedServiceID) {
            if selectedService.kind == .appleMusic {
                await model.refreshSonosMusicServiceProbeIfNeeded()
            }
        }
    }

    private func orderedServices(_ services: [SonosServiceDescriptor]) -> [SonosServiceDescriptor] {
        var seen = Set<String>()
        return services.filter { service in
            if seen.contains(service.id) {
                return false
            }

            seen.insert(service.id)
            return true
        }
    }

    private func supportsCatalogSearch(_ service: SonosServiceDescriptor) -> Bool {
        service.kind == .appleMusic
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: {
                model.sourceSearchState(for: selectedSource).query
            },
            set: { query in
                model.updateSourceSearchQuery(query, for: selectedSource)
            }
        )
    }

    private var shouldShowSearchResults: Bool {
        appleMusicAvailabilityMessage != nil
            || searchState.isSearching
            || searchState.failureDetail != nil
            || (searchState.status == .loaded && searchState.hasQuery)
            || !searchState.items.isEmpty
    }

    private func searchCatalog() {
        model.updateSourceSearchScope(.all, for: selectedSource)

        Task {
            await model.searchSourceCatalog(for: selectedSource)
        }
    }

    private func selectRecentSearch(_ recentSearch: SonoicRecentSourceSearch) {
        model.updateSourceSearchQuery(recentSearch.query, for: selectedSource)
        searchCatalog()
    }

    private func clearRecentSearches() {
        model.clearRecentSourceSearches(for: selectedSource)
    }

    private func requestAppleMusicAuthorization() {
        Task {
            await model.requestAppleMusicAuthorization()
        }
    }

    private var appleMusicAvailabilityMessage: SearchMessage? {
        guard selectedService.kind == .appleMusic,
              !model.appleMusicAuthorizationState.allowsCatalogSearch
        else {
            return nil
        }

        return SearchMessage(
            title: model.appleMusicAuthorizationState.title,
            detail: model.appleMusicAuthorizationState.detail,
            systemImage: model.appleMusicAuthorizationState.systemImage
        )
    }
}

#Preview {
    NavigationStack {
        SearchView()
            .environment(SonoicModel())
    }
}
