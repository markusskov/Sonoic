import SwiftUI

struct AppleMusicItemDetailView: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem

    private var state: SonoicAppleMusicItemDetailState {
        model.appleMusicItemDetailState(for: item)
    }

    private var exactPlaybackCandidate: SonoicSonosPlaybackCandidate? {
        model.appleMusicExactPlaybackCandidate(for: item)
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 24) {
                    AppleMusicItemDetailHeader(item: item)

                    if let exactPlaybackCandidate {
                        AppleMusicItemActionCard(
                            playbackCandidate: exactPlaybackCandidate,
                            play: playCandidate,
                            playNext: playCandidateNext
                        )
                    }

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
        if state.isLoading && state.sections.isEmpty {
            AppleMusicItemDetailMessageCard(
                title: "Loading \(item.kind.title)",
                detail: "Loading...",
                systemImage: "icloud.and.arrow.down"
            )
        } else if let failureDetail = state.failureDetail, state.sections.isEmpty {
            AppleMusicItemDetailMessageCard(
                title: "Could Not Load Details",
                detail: failureDetail,
                systemImage: "exclamationmark.triangle"
            )
        } else if state.sections.isEmpty {
            AppleMusicItemDetailMessageCard(
                title: "No Details",
                detail: "Nothing else here yet.",
                systemImage: item.kind.systemImage
            )
        } else {
            if state.isLoading {
                AppleMusicItemDetailMessageCard(
                    title: "Refreshing",
                    detail: "Updating...",
                    systemImage: "arrow.clockwise"
                )
            }

            if let failureDetail = state.failureDetail {
                AppleMusicItemDetailMessageCard(
                    title: "Showing Cached Details",
                    detail: staleDetail(failureDetail),
                    systemImage: "exclamationmark.triangle"
                )
            }

            ForEach(state.sections) { section in
                AppleMusicItemDetailSectionView(section: section)
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
        model.loadAppleMusicItemDetail(for: item, force: true)
    }

    private func playCandidate(_ candidate: SonoicSonosPlaybackCandidate) async {
        _ = await model.playManualSonosPayload(candidate.payload)
    }

    private func playCandidateNext(_ candidate: SonoicSonosPlaybackCandidate) async {
        _ = await model.playManualSonosPayloadNext(candidate.payload)
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
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

private struct AppleMusicItemActionCard: View {
    let playbackCandidate: SonoicSonosPlaybackCandidate
    let play: (SonoicSonosPlaybackCandidate) async -> Void
    let playNext: (SonoicSonosPlaybackCandidate) async -> Void

    private var canPlayNext: Bool {
        (try? SonosPlayablePayloadPreparer().prepare(playbackCandidate.payload.withLaunchMode(.queueNext))) != nil
    }

    var body: some View {
        RoomSurfaceCard {
            VStack(spacing: 10) {
                Button {
                    Task {
                        await play(playbackCandidate)
                    }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if canPlayNext {
                    Button {
                        Task {
                            await playNext(playbackCandidate)
                        }
                    } label: {
                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
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
                    subtitle: section.subtitle
                )

                Spacer(minLength: 0)

                if showsViewAll {
                    NavigationLink {
                        AppleMusicItemCollectionView(
                            title: section.title,
                            subtitle: section.subtitle,
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
