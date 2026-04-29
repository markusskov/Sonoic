import SwiftUI

struct AppleMusicItemDetailView: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem
    @State private var actionFailure: AppleMusicItemDetailActionFailure?
    @State private var localPlaylistFavoriteObjectID: String?

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

    private var isPlaylistFavorited: Bool {
        playlistFavoriteObjectID != nil
    }

    private var playlistFavoriteObjectID: String? {
        localPlaylistFavoriteObjectID ?? exactPlaybackCandidate?.verifiedFavoriteObjectID
    }

    private var canPlayPlaylistFallback: Bool {
        playlistPlaybackPayload() != nil
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
                        } else {
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

    private func playCandidate(_ candidate: SonoicSonosPlaybackCandidate) async {
        _ = await model.playManualSonosPayload(candidate.payload)
    }

    private func playGeneratedCandidate(_ candidate: SonoicAppleMusicGeneratedPayloadCandidate) async {
        do {
            let payload = try candidate.preparedPlaybackPayload(for: item)
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

    private var playlistQueuePairs: [(item: SonoicSourceItem, payload: SonosPlayablePayload)] {
        playlistTrackItems.compactMap { track in
            if let generatedQueueCandidate = model.appleMusicGeneratedQueueCandidate(for: track) {
                return (track, generatedQueueCandidate.playbackPayload(for: track))
            }

            if let exactPlaybackCandidate = model.appleMusicExactPlaybackCandidate(for: track) {
                return (track, exactPlaybackCandidate.payload)
            }

            return nil
        }
    }

    private var canPlayPlaylistQueue: Bool {
        !playlistQueuePairs.isEmpty
    }

    private func playPlaylistQueue(shuffled: Bool) async {
        let playbackPairs = shuffled ? playlistQueuePairs.shuffled() : playlistQueuePairs
        let payloads = playbackPairs.map(\.payload)

        guard let firstItem = playbackPairs.first?.item,
              !payloads.isEmpty
        else {
            return
        }

        let localPayload = localNowPlayingPayload(for: firstItem)
        let didStart = await model.playManualSonosQueuePayloads(
            payloads,
            startingTrackNumber: 1,
            localNowPlayingPayload: localPayload,
            recentPlaybackPayload: playlistPlaybackPayload()
        )

        if didStart {
            model.recordRecentSourceItem(item, replayPayload: playlistPlaybackPayload())
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
        if let playlistFavoriteObjectID {
            do {
                try await model.removeSonosFavorite(objectID: playlistFavoriteObjectID)
                localPlaylistFavoriteObjectID = nil
            } catch {
                actionFailure = AppleMusicItemDetailActionFailure(
                    title: "Could Not Remove Favorite",
                    detail: error.localizedDescription
                )
            }

            return
        }

        guard let payload = playlistGeneratedPlaybackPayload() else {
            actionFailure = AppleMusicItemDetailActionFailure(
                title: "Could Not Save Favorite",
                detail: "This playlist does not have a Sonos favorite payload yet."
            )
            return
        }

        do {
            localPlaylistFavoriteObjectID = try await model.addSonosFavorite(payload)
        } catch {
            actionFailure = AppleMusicItemDetailActionFailure(
                title: "Could Not Save Favorite",
                detail: error.localizedDescription
            )
        }
    }

    private func playlistPlaybackPayload() -> SonosPlayablePayload? {
        if let exactPlaybackCandidate = model.appleMusicExactPlaybackCandidate(for: item) {
            return exactPlaybackCandidate.payload
        }

        return playlistGeneratedPlaybackPayload()
    }

    private func playlistGeneratedPlaybackPayload() -> SonosPlayablePayload? {
        return model.appleMusicGeneratedPlaybackCandidate(for: item)?.playbackPayload(for: item)
    }

    private func localNowPlayingPayload(for item: SonoicSourceItem) -> SonosPlayablePayload? {
        if let exactPlaybackCandidate = model.appleMusicExactPlaybackCandidate(for: item) {
            return exactPlaybackCandidate.payload
        }

        return model.appleMusicGeneratedPlaybackCandidate(for: item)?.playbackPayload(for: item)
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
                    maximumDisplayDimension: 900,
                    placeholderSystemImage: item.kind.systemImage
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
    private let previewLimit = 8

    private var previewItems: [SonoicSourceItem] {
        if usesPlainTrackList {
            return section.items
        }

        return Array(section.items.prefix(previewLimit))
    }

    private var usesPlainTrackList: Bool {
        parentItem.kind == .playlist || parentItem.kind == .album
    }

    private var showsViewAll: Bool {
        !usesPlainTrackList && section.items.count > previewItems.count
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
                            items: section.items,
                            parentItem: parentItem,
                            sectionID: section.id
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
                }
            }
        }
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
            await playPlaylistTrack(item, trackNumber: index + 1)
        }
    }

    private func playPlaylistTrack(_ item: SonoicSourceItem, trackNumber: Int) async {
        let queuePayloads = playlistQueuePayloads()
        guard !queuePayloads.isEmpty else {
            return
        }

        let localPayload = localNowPlayingPayload(for: item)
        let recentPayload = playlistPlaybackPayload()
        let didStartPlayback = await model.playManualSonosQueuePayloads(
            queuePayloads,
            startingTrackNumber: trackNumber,
            localNowPlayingPayload: localPayload,
            recentPlaybackPayload: recentPayload
        )

        if didStartPlayback {
            model.recordRecentSourceItem(parentItem, replayPayload: recentPayload)
        }
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

    private func playlistQueuePayloads() -> [SonosPlayablePayload] {
        section.items.compactMap { item in
            if let generatedQueueCandidate = model.appleMusicGeneratedQueueCandidate(for: item) {
                return generatedQueueCandidate.playbackPayload(for: item)
            }

            return model.appleMusicExactPlaybackCandidate(for: item)?.payload
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
