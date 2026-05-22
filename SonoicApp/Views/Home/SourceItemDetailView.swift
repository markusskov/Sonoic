import SwiftUI

struct SourceItemDetailView: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem
    @State private var actionFailure: SourceActionFailure?

    private var state: SonoicSourceItemDetailState {
        model.sourceItemDetailState(for: item)
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
        model.sourceFavoriteObjectID(for: item)
    }

    private var canPlayContainerFallback: Bool {
        model.sourcePlaylistFallbackPayload(for: item) != nil
    }

    private var canPlayItem: Bool {
        model.canPlaySourceItem(item)
    }

    private var canFavoriteItem: Bool {
        model.sourceAdapter(for: item).capabilities.supportsFavorites
    }

    var body: some View {
        ZStack {
            SourceItemDetailBackground(item: item)

            ScrollView {
                GlassEffectContainer(spacing: 18) {
                    VStack(alignment: .leading, spacing: 24) {
                        SourceItemDetailHeader(item: item)

                        if item.kind.isPlayableContainer {
                            if canPlayContainerQueue || canPlayContainerFallback {
                                SourcePlaylistActionRow(
                                    isFavorite: isPlaylistFavorited,
                                    canShuffle: canPlayContainerQueue,
                                    canFavorite: canFavoriteItem,
                                    shuffle: {
                                        await playContainerQueue(shuffled: true)
                                    },
                                    play: {
                                        await playContainer()
                                    },
                                    favorite: {
                                        await togglePlaylistFavorite()
                                    }
                                )
                            } else if canFavoriteItem {
                                SourcePlaylistActionSkeletonRow(canFavorite: canFavoriteItem)
                            }
                        } else if canPlayItem {
                            SourceItemActionCard(
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
        .task(id: item.sourceDetailCacheKey) {
            model.loadSourceItemDetail(for: item)
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
            SourceMessageCard(
                title: "Loading \(item.kind.title)",
                systemImage: "icloud.and.arrow.down"
            )
        } else if let failureDetail = state.failureDetail, state.sections.isEmpty {
            SourceMessageCard(
                title: "Could Not Load Details",
                detail: failureDetail,
                systemImage: "exclamationmark.triangle"
            )
        } else if state.sections.isEmpty {
            SourceMessageCard(
                title: "No Details",
                systemImage: item.kind.systemImage
            )
        } else {
            if state.isLoading {
                SourceMessageCard(
                    title: "Refreshing",
                    systemImage: "arrow.clockwise"
                )
            }

            if let failureDetail = state.failureDetail {
                SourceMessageCard(
                    title: "Showing Cached Details",
                    detail: sourceStaleDetail(failureDetail, lastUpdatedAt: state.lastUpdatedAt),
                    systemImage: "exclamationmark.triangle"
                )
            }

            ForEach(state.sections) { section in
                SourceItemDetailSectionView(parentItem: item, section: section)
            }
        }
    }

    private func refreshTapped() {
        model.loadSourceItemDetail(for: item, force: true)
    }

    private func playItem() async {
        do {
            let didStart = try await model.playSourceItem(item)

            if !didStart {
                actionFailure = SourceActionFailure(
                    title: "Could Not Start",
                    detail: "Sonos could not start this item."
                )
            }
        } catch {
            actionFailure = SourceActionFailure(
                title: "Could Not Start",
                detail: error.localizedDescription
            )
        }
    }

    private var containerTrackItems: [SonoicSourceItem] {
        guard item.kind.isPlayableContainer else {
            return []
        }

        return state.sections.flatMap(\.items).filter { $0.kind == .song }
    }

    private var canPlayContainerQueue: Bool {
        model.canPlaySourcePlaylistQueue(parentItem: item, trackItems: containerTrackItems)
    }

    private func playContainerQueue(shuffled: Bool) async {
        await model.playSourcePlaylistQueue(
            parentItem: item,
            trackItems: containerTrackItems,
            shuffled: shuffled
        )
    }

    private func playContainer() async {
        _ = try? await model.playSourcePlaylist(parentItem: item, trackItems: containerTrackItems)
    }

    private func togglePlaylistFavorite() async {
        let wasFavorited = playlistFavoriteObjectID != nil

        do {
            _ = try await model.toggleSourceFavorite(for: item)
        } catch {
            actionFailure = SourceActionFailure(
                title: wasFavorited ? "Could Not Remove Favorite" : "Could Not Save Favorite",
                detail: error.localizedDescription
            )
        }
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

private extension SonoicSourceItem.Kind {
    var isPlayableContainer: Bool {
        self == .playlist || self == .album
    }
}

#Preview {
    NavigationStack {
        SourceItemDetailView(
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
