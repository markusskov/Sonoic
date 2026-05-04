import SwiftUI

struct SearchView: View {
    @Environment(SonoicModel.self) private var model
    @State private var isSearchFieldFocused = false

    private var searchableSources: [SonoicSource] {
        orderedServices(model.homeSources.map(\.service) + SonosServiceCatalog.browsableServices)
            .filter { model.sourceAdapter(for: $0).capabilities.supportsCatalogSearch }
            .map { service in
                model.homeSources.first { $0.service.id == service.id } ?? SonoicSource(
                    service: service,
                    favoriteCount: 0,
                    collectionCount: 0,
                    recentCount: 0,
                    isCurrent: false,
                    status: .availableForSetup
                )
            }
    }

    private var recentSearches: [SonoicRecentSourceSearch] {
        model.recentSourceSearches(for: searchableSources)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !searchableSources.isEmpty {
                    SearchInputCard(
                        query: searchQueryBinding,
                        isFocused: $isSearchFieldFocused,
                        placeholder: searchPlaceholder,
                        isSearching: model.sourceSearchSession.isSearching(
                            in: model.sourceSearchStates,
                            sources: searchableSources
                        ),
                        hasQuery: model.sourceSearchSession.hasQuery,
                        submit: searchCatalog
                    )

                    if shouldShowSearchResults {
                        SearchResultsSection(
                            session: model.sourceSearchSession,
                            sources: searchableSources,
                            states: model.sourceSearchStates,
                            availabilityMessage: appleMusicAvailabilityMessage,
                            canRequestAuthorization: model.appleMusicAuthorizationState.canRequestAuthorization,
                            requestAuthorization: requestAppleMusicAuthorization,
                            selectSource: selectSource,
                            selectScope: selectScope
                        )
                    } else if isSearchFieldFocused && !recentSearches.isEmpty {
                        SearchRecentQueriesSection(
                            recentSearches: recentSearches,
                            select: selectRecentSearch,
                            clear: clearRecentSearches
                        )
                    } else {
                        SearchDiscoverySection(
                            service: .appleMusic,
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
        .task {
            if searchableSources.contains(where: { $0.service.kind == .appleMusic }) {
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

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: {
                model.sourceSearchSession.query
            },
            set: { query in
                model.updateSourceSearchSessionQuery(query)
            }
        )
    }

    private var searchPlaceholder: String {
        guard searchableSources.count == 1,
              let source = searchableSources.first
        else {
            return "Search"
        }

        return "Search \(source.service.name)"
    }

    private var shouldShowSearchResults: Bool {
        if appleMusicAvailabilityMessage != nil {
            return true
        }

        guard model.sourceSearchSession.hasActiveSubmittedQuery else {
            return false
        }

        return model.sourceSearchSession.isSearching(
                in: model.sourceSearchStates,
                sources: searchableSources
            )
            || model.sourceSearchSession.failureDetail(
                in: model.sourceSearchStates,
                sources: searchableSources
            ) != nil
            || model.sourceSearchSession.hasLoadedEmptyResults(
                in: model.sourceSearchStates,
                sources: searchableSources
            )
            || !model.sourceSearchSession.visibleItems(
                in: model.sourceSearchStates,
                sources: searchableSources
            ).isEmpty
    }

    private func searchCatalog() {
        Task {
            await model.searchSourceCatalog(in: searchableSources)
        }
    }

    private func selectRecentSearch(_ recentSearch: SonoicRecentSourceSearch) {
        model.updateSourceSearchSessionQuery(recentSearch.query)
        searchCatalog()
    }

    private func clearRecentSearches() {
        model.clearRecentSourceSearches(for: searchableSources)
    }

    private func selectSource(_ serviceID: String?) {
        model.updateSourceSearchSessionServiceFilter(serviceID)
    }

    private func selectScope(_ scope: SonoicSourceSearchScope) {
        model.updateSourceSearchSessionScope(scope)
    }

    private func requestAppleMusicAuthorization() {
        Task {
            await model.requestAppleMusicAuthorization()
        }
    }

    private var appleMusicAvailabilityMessage: SearchMessage? {
        guard searchableSources.contains(where: { $0.service.kind == .appleMusic }),
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
