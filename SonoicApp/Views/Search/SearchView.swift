import SwiftUI

struct SearchView: View {
    @Environment(SonoicModel.self) private var model
    @State private var selectedServiceID = SonosServiceDescriptor.appleMusic.id

    private var services: [SonosServiceDescriptor] {
        orderedServices(model.homeSources.map(\.service) + SonosServiceCatalog.browsableServices)
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

    private var supportsCatalogSearch: Bool {
        selectedService.kind == .appleMusic
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 28) {
                    SearchHeader()

                    SearchServicePicker(
                        services: services,
                        selectedServiceID: $selectedServiceID
                    )

                    if supportsCatalogSearch {
                        SearchInputCard(
                            query: searchQueryBinding,
                            service: selectedService,
                            state: searchState,
                            supportsCatalogSearch: supportsCatalogSearch,
                            submit: searchCatalog
                        )

                        SearchRecentQueriesSection(
                            service: selectedService,
                            recentSearches: model.recentSourceSearches(for: selectedSource),
                            select: selectRecentSearch,
                            clear: clearRecentSearches
                        )

                        SearchScopeSection(
                            service: selectedService,
                            selectedScope: searchState.scope,
                            selectScope: selectScope
                        )

                        SearchResultsSection(
                            service: selectedService,
                            state: searchState,
                            availabilityMessage: appleMusicAvailabilityMessage,
                            canRequestAuthorization: model.appleMusicAuthorizationState.canRequestAuthorization,
                            requestAuthorization: requestAppleMusicAuthorization
                        )
                    } else {
                        SearchComingSoonCard(service: selectedService)
                    }
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle("Search")
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

    private func searchCatalog() {
        Task {
            await model.searchSourceCatalog(for: selectedSource)
        }
    }

    private func selectScope(_ scope: SonoicSourceSearchScope) {
        let shouldSearch = scope != searchState.scope && searchState.hasQuery
        model.updateSourceSearchScope(scope, for: selectedSource)

        if shouldSearch {
            searchCatalog()
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
