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
        VStack(alignment: .leading, spacing: 10) {
            Label(destination.title, systemImage: destination.systemImage)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)

            Text(destination.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            AppleMusicLibraryMessageCard(
                title: "Loading \(destination.title)",
                detail: "Reading your Apple Music library metadata.",
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
                detail: "Apple Music did not return saved \(destination.title.lowercased()) for this library.",
                systemImage: "music.note.list"
            )
        } else if state.status == .loaded || !state.items.isEmpty {
            libraryItemsSection
        } else {
            AppleMusicLibraryMessageCard(
                title: "\(destination.title) Ready",
                detail: "Tap refresh to load this Apple Music library lane.",
                systemImage: destination.systemImage
            )
        }
    }

    @ViewBuilder
    private var libraryItemsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: destination.title,
                subtitle: sectionSubtitle
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
        }
    }

    private var sectionSubtitle: String {
        let base = [
            "Showing \(state.items.count) items from the first Apple Music library page.",
            "Sonoic still needs Sonos-native payloads before playback."
        ].joined(separator: " ")

        guard let lastUpdatedAt = state.lastUpdatedAt else {
            return base
        }

        return "\(base) Updated \(lastUpdatedAt.formatted(.dateTime.hour().minute()))."
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

    private var playbackCandidate: SonoicSonosPlaybackCandidate? {
        model.appleMusicPlaybackCandidate(for: item)
    }

    var body: some View {
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

                    if let playbackCandidate {
                        Label(playbackCandidate.confidence.badgeTitle, systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(playbackCandidate.confidence == .exact ? .green : .secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
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
