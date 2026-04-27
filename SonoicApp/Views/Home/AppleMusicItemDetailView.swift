import SwiftUI

struct AppleMusicItemDetailView: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem
    @State private var generatedPlaybackFailure: GeneratedPlaybackFailure?

    private var state: SonoicAppleMusicItemDetailState {
        model.appleMusicItemDetailState(for: item)
    }

    private var exactPlaybackCandidate: SonoicSonosPlaybackCandidate? {
        model.appleMusicExactPlaybackCandidate(for: item)
    }

    private var generatedPlaybackCandidates: [SonoicAppleMusicGeneratedPayloadCandidate] {
        guard exactPlaybackCandidate == nil else {
            return []
        }

        return model.appleMusicGeneratedPayloadCandidates(for: item)
    }

    private var generatedPlaybackCandidate: SonoicAppleMusicGeneratedPayloadCandidate? {
        guard exactPlaybackCandidate == nil else {
            return nil
        }

        return model.appleMusicGeneratedPlaybackCandidate(for: item)
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 24) {
                    AppleMusicItemDetailHeader(item: item)

                    if let exactPlaybackCandidate {
                        AppleMusicItemActionCard(
                            play: {
                                await playCandidate(exactPlaybackCandidate)
                            }
                        )
                    } else if let generatedPlaybackCandidate {
                        AppleMusicItemActionCard(
                            play: {
                                await playGeneratedCandidate(generatedPlaybackCandidate)
                            }
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
            await refreshGeneratedPlaybackHintsIfNeeded()
        }
        .alert(item: $generatedPlaybackFailure) { failure in
            Alert(
                title: Text("Could Not Start"),
                message: Text(failure.detail),
                dismissButton: .default(Text("OK"))
            )
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
                AppleMusicItemDetailSectionView(parentItem: item, section: section)
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

    private func playGeneratedCandidate(_ candidate: SonoicAppleMusicGeneratedPayloadCandidate) async {
        do {
            let payload = try candidate.preparedPlaybackPayload(for: item)
            let didStart = await model.playManualSonosPayload(payload)

            if !didStart {
                generatedPlaybackFailure = GeneratedPlaybackFailure(detail: "Sonos could not start this Apple Music song.")
            }
        } catch {
            generatedPlaybackFailure = GeneratedPlaybackFailure(detail: error.localizedDescription)
        }
    }

    private func refreshGeneratedPlaybackHintsIfNeeded() async {
        guard item.service.kind == .appleMusic,
              item.kind == .song || item.kind == .playlist,
              exactPlaybackCandidate == nil,
              generatedPlaybackCandidates.isEmpty
        else {
            return
        }

        await model.refreshSonosMusicServiceProbeIfNeeded()
    }
}

private struct GeneratedPlaybackFailure: Identifiable {
    let id = UUID()
    var detail: String
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
    let play: () async -> Void

    var body: some View {
        RoomSurfaceCard {
            Button {
                Task {
                    await play()
                }
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private struct AppleMusicItemDetailSectionView: View {
    @Environment(SonoicModel.self) private var model

    let parentItem: SonoicSourceItem
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
                        SourceItemNavigationRow(
                            item: item,
                            playOverride: playlistTrackPlayAction(for: item, at: index)
                        )

                        if index < previewItems.count - 1 {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
            }
        }
    }

    private func playlistTrackPlayAction(
        for item: SonoicSourceItem,
        at index: Int
    ) -> (() async -> Void)? {
        guard parentItem.kind == .playlist,
              section.id == "tracks",
              item.kind == .song
        else {
            return nil
        }

        return {
            await playPlaylistTrack(item, trackNumber: index + 1)
        }
    }

    private func playPlaylistTrack(_ item: SonoicSourceItem, trackNumber: Int) async {
        guard let playlistPayload = playlistPlaybackPayload() else {
            return
        }

        let localPayload = localNowPlayingPayload(for: item)
        _ = await model.playManualSonosPayload(
            playlistPayload,
            startingTrackNumber: trackNumber,
            localNowPlayingPayload: localPayload
        )
    }

    private func playlistPlaybackPayload() -> SonosPlayablePayload? {
        if let exactPlaybackCandidate = model.appleMusicExactPlaybackCandidate(for: parentItem) {
            return exactPlaybackCandidate.payload
        }

        guard let generatedPlaybackCandidate = model.appleMusicGeneratedPlaybackCandidate(for: parentItem) else {
            return nil
        }

        return generatedPlaybackCandidate.playbackPayload(for: parentItem)
    }

    private func localNowPlayingPayload(for item: SonoicSourceItem) -> SonosPlayablePayload? {
        if let exactPlaybackCandidate = model.appleMusicExactPlaybackCandidate(for: item) {
            return exactPlaybackCandidate.payload
        }

        return model.appleMusicGeneratedPlaybackCandidate(for: item)?.playbackPayload(for: item)
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
