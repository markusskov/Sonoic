import SwiftUI

struct AppleMusicLibraryDestinationView: View {
    @Environment(SonoicModel.self) private var model

    let destination: SonoicAppleMusicLibraryDestination

    private var state: SonoicAppleMusicLibraryState {
        model.appleMusicLibraryState(for: destination)
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    content
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle(destination.title)
        .task(id: destination.id) {
            model.loadAppleMusicLibraryDestination(destination)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: refreshTapped) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(state.isLoading)
                .accessibilityLabel("Refresh \(destination.title)")
            }
        }
        .refreshable {
            refreshTapped()
        }
    }

    private var header: some View {
        Label(destination.title, systemImage: destination.systemImage)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading && state.items.isEmpty {
            AppleMusicLibraryMessageCard(
                title: "Loading \(destination.title)",
                detail: "Loading...",
                systemImage: "icloud.and.arrow.down"
            )
        } else if let failureDetail = state.failureDetail, state.items.isEmpty {
            AppleMusicLibraryMessageCard(
                title: "Could Not Load \(destination.title)",
                detail: failureDetail,
                systemImage: "exclamationmark.triangle"
            )
        } else if state.status == .loaded && state.items.isEmpty {
            AppleMusicLibraryMessageCard(
                title: "No \(destination.title)",
                detail: "Nothing here yet.",
                systemImage: "music.note.list"
            )
        } else if state.status == .loaded || !state.items.isEmpty {
            libraryItemsSection
        } else {
            AppleMusicLibraryMessageCard(
                title: destination.title,
                detail: "Pull to refresh.",
                systemImage: destination.systemImage
            )
        }
    }

    @ViewBuilder
    private var libraryItemsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: destination.title
            )

            if let failureDetail = state.failureDetail {
                AppleMusicLibraryMessageCard(
                    title: "Showing Cached \(destination.title)",
                    detail: staleDetail(failureDetail),
                    systemImage: "exclamationmark.triangle"
                )
            }

            if destination == .songs {
                RoomSurfaceCard {
                    VStack(spacing: 0) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                            SourceItemNavigationRow(item: item)

                            if index < state.items.count - 1 {
                                Divider()
                                    .padding(.leading, 76)
                            }
                        }
                    }
                }
            } else {
                AppleMusicLibraryGrid(items: state.items)
            }

            if state.canLoadMore || state.isLoading {
                Button(action: loadMoreTapped) {
                    if state.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading More")
                        }
                    } else {
                        Label("Load More", systemImage: "chevron.down")
                    }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(state.isLoading)
                .accessibilityLabel("Load more \(destination.title)")
            }
        }
    }

    private func staleDetail(_ failureDetail: String) -> String {
        guard let lastUpdatedAt = state.lastUpdatedAt else {
            return failureDetail
        }

        return "Last successful load was \(lastUpdatedAt.formatted(.dateTime.hour().minute())).\n\n\(failureDetail)"
    }

    private func refreshTapped() {
        model.loadAppleMusicLibraryDestination(destination, force: true)
    }

    private func loadMoreTapped() {
        model.loadAppleMusicLibraryDestination(destination, append: true)
    }
}

private struct AppleMusicLibraryGrid: View {
    let items: [SonoicSourceItem]

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(items) { item in
                AppleMusicLibraryGridCard(item: item)
            }
        }
    }
}

private struct AppleMusicLibraryGridCard: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem

    private var exactPlaybackCandidate: SonoicSonosPlaybackCandidate? {
        model.appleMusicExactPlaybackCandidate(for: item)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                AppleMusicItemDetailView(item: item)
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HomeFavoriteArtworkView(
                        artworkURL: item.artworkURL,
                        artworkIdentifier: item.artworkIdentifier,
                        maximumDisplayDimension: 220
                    )
                    .aspectRatio(1, contentMode: .fit)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)

            if let exactPlaybackCandidate {
                Button {
                    Task {
                        _ = await model.playManualSonosPayload(exactPlaybackCandidate.payload)
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(8)
                .accessibilityLabel("Play \(item.title)")
            }
        }
    }
}

private struct AppleMusicLibraryMessageCard: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        RoomSurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppleMusicLibraryDestinationView(destination: .albums)
            .environment(SonoicModel())
    }
}
