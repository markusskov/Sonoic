import SwiftUI

struct AppleMusicItemDetailView: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem

    private var state: SonoicAppleMusicItemDetailState {
        model.appleMusicItemDetailState(for: item)
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 24) {
                    AppleMusicItemDetailHeader(item: item)
                    AppleMusicItemCapabilityCard(item: item)
                    content
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle(item.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) {
            model.loadAppleMusicItemDetail(for: item)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: refreshTapped) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(state.isLoading)
                .accessibilityLabel("Refresh \(item.title)")
            }
        }
        .refreshable {
            refreshTapped()
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            AppleMusicItemDetailMessageCard(
                title: "Loading \(item.kind.title)",
                detail: "Reading Apple Music metadata.",
                systemImage: "icloud.and.arrow.down"
            )
        } else if let failureDetail = state.failureDetail {
            AppleMusicItemDetailMessageCard(
                title: "Could Not Load Details",
                detail: failureDetail,
                systemImage: "exclamationmark.triangle"
            )
        } else if state.sections.isEmpty {
            AppleMusicItemDetailMessageCard(
                title: "No More Metadata",
                detail: "Apple Music did not return extra detail sections for this item yet.",
                systemImage: item.kind.systemImage
            )
        } else {
            ForEach(state.sections) { section in
                AppleMusicItemDetailSectionView(section: section)
            }
        }
    }

    private func refreshTapped() {
        model.loadAppleMusicItemDetail(for: item, force: true)
    }
}

private struct AppleMusicItemDetailHeader: View {
    let item: SonoicSourceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HomeFavoriteArtworkView(
                artworkURL: item.artworkURL,
                artworkIdentifier: item.artworkIdentifier,
                maximumDisplayDimension: 260
            )
            .frame(width: 260, height: 260)
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                Label(item.kind.title, systemImage: item.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(item.title)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    AppleMusicItemDetailChip(title: item.service.name, systemImage: item.service.systemImage)
                    AppleMusicItemDetailChip(title: originTitle, systemImage: originSystemImage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var originTitle: String {
        switch item.origin {
        case .catalogSearch:
            "Catalog"
        case .favorite:
            "Favorite"
        case .library:
            "Library"
        case .recentPlay:
            "Recent"
        }
    }

    private var originSystemImage: String {
        switch item.origin {
        case .catalogSearch:
            "magnifyingglass"
        case .favorite:
            "star"
        case .library:
            "rectangle.stack"
        case .recentPlay:
            "clock"
        }
    }
}

private struct AppleMusicItemCapabilityCard: View {
    let item: SonoicSourceItem

    var body: some View {
        RoomSurfaceCard {
            Label("Metadata Only", systemImage: "lock.circle")
                .font(.headline)

            Text("Sonoic can browse this Apple Music item, but still needs a Sonos-native playback payload before it can start playback on your speakers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppleMusicItemDetailSectionView: View {
    let section: SonoicAppleMusicItemDetailSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: section.title,
                subtitle: section.subtitle ?? "Apple Music metadata"
            )

            RoomSurfaceCard {
                VStack(spacing: 0) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        SourceItemNavigationRow(item: item)

                        if index < section.items.count - 1 {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
            }
        }
    }
}

private struct AppleMusicItemDetailMessageCard: View {
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

private struct AppleMusicItemDetailChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.45), in: Capsule())
    }
}

#Preview {
    NavigationStack {
        AppleMusicItemDetailView(
            item: SonoicSourceItem.appleMusicMetadata(
                id: "preview-album",
                title: "The Mollusk",
                subtitle: "Ween",
                artworkURL: nil,
                kind: .album,
                origin: .catalogSearch
            )
        )
        .environment(SonoicModel())
    }
}
