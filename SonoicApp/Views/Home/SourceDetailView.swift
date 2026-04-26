import SwiftUI

struct SourceDetailView: View {
    @Environment(SonoicModel.self) private var model
    @State private var selectedItem: SonoicSourceItem?

    let source: SonoicSource

    private var favoriteItems: [SonoicSourceItem] {
        model.favoriteSourceItems(for: source)
    }

    private var recentItems: [SonoicSourceItem] {
        model.recentSourceItems(for: source)
    }

    private var catalogSearchState: SonoicSourceSearchState {
        model.sourceSearchState(for: source)
    }

    private var showsCatalogSearch: Bool {
        source.service.kind == .appleMusic
    }

    private var isAppleMusic: Bool {
        source.service.kind == .appleMusic
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 28) {
                    if isAppleMusic {
                        AppleMusicSourceHeader(
                            source: source,
                            authorizationState: model.appleMusicAuthorizationState,
                            serviceDetails: model.appleMusicServiceDetails
                        )
                        AppleMusicLibrarySection()
                        AppleMusicRecentlyAddedSection()
                        AppleMusicDiscoverySection()
                    } else {
                        SourceHeaderCard(source: source)
                    }

                    if showsCatalogSearch {
                        SourceSearchSection(
                            serviceName: source.service.name,
                            query: catalogSearchBinding,
                            state: catalogSearchState,
                            recentSearches: model.recentSourceSearches(for: source),
                            availabilityMessage: appleMusicAvailabilityMessage,
                            search: searchCatalog,
                            selectRecentSearch: selectRecentSearch,
                            clearRecentSearches: clearRecentSearches
                        )
                    }

                    if !favoriteItems.isEmpty {
                        sourceSection(
                            title: "Favorites",
                            subtitle: "Saved Sonos favorites from \(source.service.name).",
                            items: favoriteItems
                        )
                    }

                    if !recentItems.isEmpty {
                        sourceSection(
                            title: "Recently Played",
                            subtitle: "History Sonoic has seen from this source.",
                            items: recentItems
                        )
                    }

                    if !isAppleMusic && favoriteItems.isEmpty && recentItems.isEmpty {
                        SourceEmptyCard(serviceName: source.service.name)
                    }

                    if !showsCatalogSearch {
                        SourceCatalogPlaceholderCard(serviceName: source.service.name)
                    }
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle(source.service.name)
        .task(id: source.id) {
            if isAppleMusic {
                await model.refreshAppleMusicServiceDetails()
                model.loadAppleMusicRecentlyAdded()
            }
        }
        .sheet(item: $selectedItem) { item in
            SourceItemDetailSheet(item: item) {
                await play(item)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func sourceSection(
        title: String,
        subtitle: String,
        items: [SonoicSourceItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(title: title, subtitle: subtitle)

            RoomSurfaceCard {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        SourceItemRow(item: item) {
                            selectedItem = item
                        } playAction: {
                            await play(item)
                        }

                        if index < items.count - 1 {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
            }
        }
    }

    private func play(_ item: SonoicSourceItem) async {
        guard case let .sonosNative(payload) = item.playbackCapability else {
            return
        }

        _ = await model.playManualSonosPayload(payload)
    }

    private var catalogSearchBinding: Binding<String> {
        Binding(
            get: {
                model.sourceSearchState(for: source).query
            },
            set: { query in
                model.updateSourceSearchQuery(query, for: source)
            }
        )
    }

    private func searchCatalog() async {
        await model.searchSourceCatalog(for: source)
    }

    private func selectRecentSearch(_ recentSearch: SonoicRecentSourceSearch) {
        model.updateSourceSearchQuery(recentSearch.query, for: source)
        Task {
            await model.searchSourceCatalog(for: source)
        }
    }

    private func clearRecentSearches() {
        model.clearRecentSourceSearches(for: source)
    }

    private var appleMusicAvailabilityMessage: SourceSearchAvailabilityMessage? {
        guard source.service.kind == .appleMusic,
              !model.appleMusicAuthorizationState.allowsCatalogSearch
        else {
            return nil
        }

        return SourceSearchAvailabilityMessage(
            title: model.appleMusicAuthorizationState.title,
            detail: model.appleMusicAuthorizationState.detail,
            systemImage: model.appleMusicAuthorizationState.systemImage
        )
    }
}

private struct SourceHeaderCard: View {
    let source: SonoicSource

    var body: some View {
        RoomSurfaceCard {
            HStack(spacing: 16) {
                RoomSurfaceIconView(
                    systemImage: source.service.systemImage,
                    size: 58,
                    cornerRadius: 20,
                    font: .title3.weight(.semibold),
                    style: .glass
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(source.service.name)
                            .font(.title2.weight(.semibold))
                            .lineLimit(1)

                        if source.isCurrent {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(source.detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
        }
    }
}
