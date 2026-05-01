import SwiftUI

struct SourceDetailView: View {
    @Environment(SonoicModel.self) private var model
    @State private var selectedGenericItem: SonoicSourceItem?

    let source: SonoicSource

    private var favoriteItems: [SonoicSourceItem] {
        model.favoriteSourceItems(for: source)
    }

    private var recentItems: [SonoicSourceItem] {
        model.recentSourceItems(for: source)
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
                            requestAuthorization: requestAppleMusicAuthorization
                        )
                        AppleMusicSearchEntrySection(openSearch: openSearch)
                        AppleMusicLibrarySection()
                        AppleMusicRecentlyAddedSection()
                        AppleMusicDiscoverySection()
                    } else {
                        SourceHeaderCard(source: source)
                    }

                    if !favoriteItems.isEmpty {
                        sourceSection(
                            title: "Favorites",
                            items: favoriteItems
                        )
                    }

                    if !recentItems.isEmpty {
                        sourceSection(
                            title: "Recently Played",
                            items: recentItems
                        )
                    }

                    if !isAppleMusic && favoriteItems.isEmpty && recentItems.isEmpty {
                        SourceEmptyCard(serviceName: source.service.name)
                    }

                    if !isAppleMusic {
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
                await model.refreshSonosMusicServiceProbeIfNeeded()
                model.loadAppleMusicRecentlyAdded()
            }
        }
        .sheet(item: $selectedGenericItem) { item in
            SourceItemDetailSheet(item: item) {
                await play(item)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func sourceSection(
        title: String,
        items: [SonoicSourceItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(title: title)

            SonoicListCard {
                SonoicListRows(items) { item, _ in
                    if isAppleMusic {
                        SourceItemNavigationRow(item: item)
                    } else {
                        SourceItemRow(item: item) {
                            selectedGenericItem = item
                        } playAction: {
                            await play(item)
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

    private func requestAppleMusicAuthorization() {
        Task {
            await model.requestAppleMusicAuthorization()
        }
    }

    private func openSearch() {
        model.selectedTab = .search
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
