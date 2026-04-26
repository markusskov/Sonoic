import SwiftUI

struct AppleMusicItemDetailView: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem

    private var state: SonoicAppleMusicItemDetailState {
        model.appleMusicItemDetailState(for: item)
    }

    private var playbackCandidate: SonoicSonosPlaybackCandidate? {
        model.appleMusicPlaybackCandidate(for: item)
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 24) {
                    AppleMusicItemDetailHeader(item: item)
                    AppleMusicItemCapabilityCard(
                        item: item,
                        playbackCandidate: playbackCandidate,
                        play: playCandidate
                    )
                    content
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle(item.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.appleMusicDetailCacheKey) {
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

    private func playCandidate(_ candidate: SonoicSonosPlaybackCandidate) async {
        _ = await model.playManualSonosPayload(candidate.payload)
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
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 260)
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

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        AppleMusicItemDetailChip(title: item.service.name, systemImage: item.service.systemImage)
                        AppleMusicItemDetailChip(title: originTitle, systemImage: originSystemImage)
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
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
    let playbackCandidate: SonoicSonosPlaybackCandidate?
    let play: (SonoicSonosPlaybackCandidate) async -> Void

    var body: some View {
        RoomSurfaceCard {
            if let playbackCandidate {
                VStack(alignment: .leading, spacing: 12) {
                    Label(playbackCandidate.confidence.title, systemImage: playbackCandidate.confidence == .exact ? "play.circle" : "checkmark.circle")
                        .font(.headline)

                    Text(playbackCandidate.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if playbackCandidate.confidence == .exact {
                        Button {
                            Task {
                                await play(playbackCandidate)
                            }
                        } label: {
                            Label("Play with Sonos", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Text("This looks related to a saved Sonos favorite, but Sonoic needs a stronger match before it starts playback.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Metadata Only", systemImage: "lock.circle")
                        .font(.headline)

                    Text("Sonoic can browse this Apple Music item, but still needs a Sonos-native playback payload before it can start playback on your speakers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let serviceItemID = item.serviceItemID {
                        Text("MusicKit ID: \(serviceItemID)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }
}

private struct AppleMusicItemDetailSectionView: View {
    let section: SonoicAppleMusicItemDetailSection
    private let previewLimit = 8

    private var previewItems: [SonoicSourceItem] {
        Array(section.items.prefix(previewLimit))
    }

    private var showsViewAll: Bool {
        section.items.count > previewItems.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                HomeSectionHeader(
                    title: section.title,
                    subtitle: section.subtitle ?? "Apple Music metadata"
                )

                Spacer(minLength: 0)

                if showsViewAll {
                    NavigationLink {
                        AppleMusicItemCollectionView(
                            title: section.title,
                            subtitle: section.subtitle ?? "Apple Music metadata",
                            items: section.items
                        )
                    } label: {
                        Label("View All", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            RoomSurfaceCard {
                VStack(spacing: 0) {
                    ForEach(Array(previewItems.enumerated()), id: \.element.id) { index, item in
                        SourceItemNavigationRow(item: item)

                        if index < previewItems.count - 1 {
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
