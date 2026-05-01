import SwiftUI

struct AppleMusicItemDetailView: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem
    @State private var actionFailure: AppleMusicItemDetailActionFailure?
    @State private var localPlaylistFavoriteObjectID: String?

    private var state: SonoicAppleMusicItemDetailState {
        model.appleMusicItemDetailState(for: item)
    }

    private var generatedPlaybackCandidates: [SonoicAppleMusicGeneratedPayloadCandidate] {
        guard model.appleMusicExactPlaybackCandidate(for: item) == nil else {
            return []
        }

        return model.appleMusicGeneratedPayloadCandidates(for: item)
    }

    private var isPlaylistFavorited: Bool {
        playlistFavoriteObjectID != nil
    }

    private var playlistFavoriteObjectID: String? {
        model.appleMusicFavoriteObjectID(for: item, localObjectID: localPlaylistFavoriteObjectID)
    }

    private var canPlayPlaylistFallback: Bool {
        playlistPlaybackPayload() != nil
    }

    private var canPlayItem: Bool {
        (try? model.appleMusicPlayablePayload(for: item, purpose: .directPlay)) != nil
    }

    var body: some View {
        ZStack {
            AppleMusicItemDetailBackground(item: item)

            ScrollView {
                GlassEffectContainer(spacing: 18) {
                    VStack(alignment: .leading, spacing: 24) {
                        AppleMusicItemDetailHeader(item: item)

                        if item.kind == .playlist {
                            if canPlayPlaylistQueue || canPlayPlaylistFallback {
                                AppleMusicPlaylistActionRow(
                                    isFavorite: isPlaylistFavorited,
                                    canShuffle: canPlayPlaylistQueue,
                                    shuffle: {
                                        await playPlaylistQueue(shuffled: true)
                                    },
                                    play: {
                                        await playPlaylist()
                                    },
                                    favorite: {
                                        await togglePlaylistFavorite()
                                    }
                                )
                            } else {
                                AppleMusicPlaylistActionSkeletonRow()
                            }
                        } else if canPlayItem {
                            AppleMusicItemActionCard(
                                play: {
                                    await playItem()
                                }
                            )
                        }

                        content
                    }
                    .padding(20)
                }
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle(item.kind == .playlist ? "" : item.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.appleMusicDetailCacheKey) {
            model.loadAppleMusicItemDetail(for: item)
            await refreshGeneratedPlaybackHintsIfNeeded()
        }
        .alert(item: $actionFailure) { failure in
            Alert(
                title: Text(failure.title),
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

    private func playItem() async {
        do {
            guard let payload = try model.appleMusicPlayablePayload(for: item, purpose: .directPlay) else {
                actionFailure = AppleMusicItemDetailActionFailure(
                    title: "Could Not Start",
                    detail: "This Apple Music item does not have a Sonos playback payload yet."
                )
                return
            }

            let didStart = await model.playManualSonosPayload(payload)

            if !didStart {
                actionFailure = AppleMusicItemDetailActionFailure(
                    title: "Could Not Start",
                    detail: "Sonos could not start this Apple Music song."
                )
            }
        } catch {
            actionFailure = AppleMusicItemDetailActionFailure(
                title: "Could Not Start",
                detail: error.localizedDescription
            )
        }
    }

    private var playlistTrackItems: [SonoicSourceItem] {
        guard item.kind == .playlist else {
            return []
        }

        return state.sections.flatMap(\.items).filter { $0.kind == .song }
    }

    private var playlistPlaybackPlan: SonoicAppleMusicPlaylistPlaybackPlan? {
        model.appleMusicPlaylistPlaybackPlan(parentItem: item, trackItems: playlistTrackItems)
    }

    private var canPlayPlaylistQueue: Bool {
        playlistPlaybackPlan != nil
    }

    private func playPlaylistQueue(shuffled: Bool) async {
        guard let plan = model.appleMusicPlaylistPlaybackPlan(
            parentItem: item,
            trackItems: playlistTrackItems,
            shuffled: shuffled
        )
        else {
            return
        }

        let didStart = await model.playManualSonosQueuePayloads(
            plan.payloads,
            startingTrackNumber: plan.startingTrackNumber,
            localNowPlayingPayload: plan.localNowPlayingPayload,
            recentPlaybackPayload: plan.recentPlaybackPayload
        )

        if didStart {
            model.recordRecentSourceItem(item, replayPayload: plan.recentPlaybackPayload)
        }
    }

    private func playPlaylist() async {
        guard canPlayPlaylistQueue else {
            await playPlaylistFallback()
            return
        }

        await playPlaylistQueue(shuffled: false)
    }

    private func playPlaylistFallback() async {
        guard let payload = playlistPlaybackPayload() else {
            return
        }

        let didStart = await model.playManualSonosPayload(
            payload,
            localNowPlayingPayload: payload,
            recentPlaybackPayload: payload
        )

        if didStart {
            model.recordRecentSourceItem(item, replayPayload: payload)
        }
    }

    private func togglePlaylistFavorite() async {
        let wasFavorited = playlistFavoriteObjectID != nil

        do {
            switch try await model.toggleAppleMusicSonosFavorite(
                for: item,
                currentObjectID: playlistFavoriteObjectID
            ) {
            case .added(let objectID):
                localPlaylistFavoriteObjectID = objectID
            case .removed:
                localPlaylistFavoriteObjectID = nil
            }
        } catch {
            actionFailure = AppleMusicItemDetailActionFailure(
                title: wasFavorited ? "Could Not Remove Favorite" : "Could Not Save Favorite",
                detail: error.localizedDescription
            )
        }
    }

    private func playlistPlaybackPayload() -> SonosPlayablePayload? {
        try? model.appleMusicPlayablePayload(for: item, purpose: .metadata)
    }

    private func refreshGeneratedPlaybackHintsIfNeeded() async {
        guard item.service.kind == .appleMusic,
              item.kind == .song || item.kind == .playlist,
              model.appleMusicExactPlaybackCandidate(for: item) == nil,
              generatedPlaybackCandidates.isEmpty
        else {
            return
        }

        await model.refreshSonosMusicServiceProbeIfNeeded()
    }
}

private struct AppleMusicItemDetailActionFailure: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
}

private struct AppleMusicItemDetailBackground: View {
    let item: SonoicSourceItem

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                HomeFavoriteArtworkView(
                    artworkURL: item.artworkURL,
                    artworkIdentifier: item.artworkIdentifier,
                    maximumDisplayDimension: 900
                )
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .scaleEffect(1.16)
                .blur(radius: 54)
                .saturation(1.28)
                .opacity(0.54)
                .clipped()

                LinearGradient(
                    colors: [
                        .black.opacity(0.22),
                        .black.opacity(0.42),
                        .black.opacity(0.9)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct AppleMusicItemDetailHeader: View {
    let item: SonoicSourceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeFavoriteArtworkView(
                artworkURL: item.artworkURL,
                artworkIdentifier: item.artworkIdentifier,
                maximumDisplayDimension: 260
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 260)
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: item.kind == .playlist ? .center : .leading, spacing: 6) {
                if item.kind != .playlist {
                    Label(item.kind.title, systemImage: item.kind.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(item.title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(item.kind == .playlist ? .center : .leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)

                if item.kind != .playlist, let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if item.kind != .playlist {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            AppleMusicItemDetailChip(title: item.service.name, systemImage: item.service.systemImage)
                        }
                        .padding(.vertical, 1)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: item.kind == .playlist ? .center : .leading
            )
        }
    }

}

private struct AppleMusicPlaylistActionRow: View {
    let isFavorite: Bool
    var canShuffle = true
    let shuffle: () async -> Void
    let play: () async -> Void
    let favorite: () async -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Task {
                    await shuffle()
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3.weight(.semibold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .disabled(!canShuffle)
            .opacity(canShuffle ? 1 : 0.42)
            .accessibilityLabel("Shuffle")

            Button {
                Task {
                    await play()
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel("Play")

            Button {
                Task {
                    await favorite()
                }
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.title3.weight(.semibold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .accessibilityLabel(isFavorite ? "Saved to Sonos Favorites" : "Save to Sonos Favorites")
        }
    }
}

private struct AppleMusicPlaylistActionSkeletonRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 54, height: 54)

            Capsule()
                .fill(.white.opacity(0.16))
                .frame(maxWidth: .infinity)
                .frame(height: 54)

            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 54, height: 54)
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AppleMusicItemActionCard: View {
    let play: () async -> Void

    var body: some View {
        Button {
            Task {
                await play()
            }
        } label: {
            Label("Play", systemImage: "play.fill")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Play")
    }
}

private struct AppleMusicItemDetailSectionView: View {
    @Environment(SonoicModel.self) private var model

    let parentItem: SonoicSourceItem
    let section: SonoicAppleMusicItemDetailSection
    @State private var visibleItemCount = 10
    private let visibleItemIncrement = 10

    private var previewItems: [SonoicSourceItem] {
        if usesPlainTrackList {
            return section.items
        }

        return Array(section.items.prefix(visibleItemCount))
    }

    private var usesPlainTrackList: Bool {
        parentItem.kind == .playlist || parentItem.kind == .album
    }

    private var showsMoreButton: Bool {
        !usesPlainTrackList && section.items.count > previewItems.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: section.title,
                subtitle: section.subtitle
            )

            if usesPlainTrackList {
                SonoicListRows(previewItems) { item, index in
                    SourceItemNavigationRow(
                        item: item,
                        playOverride: playlistTrackPlayAction(for: item, at: index),
                        isCompact: true
                    )
                }
            } else {
                SonoicListCard {
                    SonoicListRows(previewItems) { item, index in
                        SourceItemNavigationRow(
                            item: item,
                            playOverride: playlistTrackPlayAction(for: item, at: index)
                        )
                    }

                    if showsMoreButton {
                        SonoicListMoreButton(action: showMoreItems)
                    }
                }
            }
        }
        .onChange(of: section.items) { _, _ in
            visibleItemCount = 10
        }
    }

    private func showMoreItems() {
        visibleItemCount = min(section.items.count, visibleItemCount + visibleItemIncrement)
    }

    private func playlistTrackPlayAction(
        for item: SonoicSourceItem,
        at index: Int
    ) -> (() async -> Void)? {
        guard parentItem.kind == .playlist,
              item.kind == .song
        else {
            return nil
        }

        return {
            await playPlaylistTrack(item)
        }
    }

    private func playPlaylistTrack(_ item: SonoicSourceItem) async {
        guard let plan = model.appleMusicPlaylistPlaybackPlan(
            parentItem: parentItem,
            trackItems: section.items,
            startingAt: item
        ) else {
            return
        }

        let didStartPlayback = await model.playManualSonosQueuePayloads(
            plan.payloads,
            startingTrackNumber: plan.startingTrackNumber,
            localNowPlayingPayload: plan.localNowPlayingPayload,
            recentPlaybackPayload: plan.recentPlaybackPayload
        )

        if didStartPlayback {
            model.recordRecentSourceItem(parentItem, replayPayload: plan.recentPlaybackPayload)
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
