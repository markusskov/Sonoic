import SwiftUI

struct AppleMusicItemCollectionView: View {
    @Environment(SonoicModel.self) private var model

    let title: String
    let subtitle: String?
    let items: [SonoicSourceItem]
    var parentItem: SonoicSourceItem?
    var sectionID: String?

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    RoomSurfaceCard {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                SourceItemNavigationRow(
                                    item: item,
                                    playOverride: playlistTrackPlayAction(for: item, at: index)
                                )

                                if index < items.count - 1 {
                                    Divider()
                                        .padding(.leading, 76)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playlistTrackPlayAction(
        for item: SonoicSourceItem,
        at index: Int
    ) -> (() async -> Void)? {
        guard parentItem?.kind == .playlist,
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
        _ = await model.playManualSonosQueuePayloads(
            queuePayloads,
            startingTrackNumber: trackNumber,
            localNowPlayingPayload: localPayload,
            recentPlaybackPayload: parentItem.flatMap(playlistPlaybackPayload)
        )
    }

    private func playlistPlaybackPayload(for parentItem: SonoicSourceItem) -> SonosPlayablePayload? {
        if let exactPlaybackCandidate = model.appleMusicExactPlaybackCandidate(for: parentItem) {
            return exactPlaybackCandidate.payload
        }

        return model.appleMusicGeneratedPlaybackCandidate(for: parentItem)?.playbackPayload(for: parentItem)
    }

    private func localNowPlayingPayload(for item: SonoicSourceItem) -> SonosPlayablePayload? {
        if let exactPlaybackCandidate = model.appleMusicExactPlaybackCandidate(for: item) {
            return exactPlaybackCandidate.payload
        }

        return model.appleMusicGeneratedPlaybackCandidate(for: item)?.playbackPayload(for: item)
    }

    private func playlistQueuePayloads() -> [SonosPlayablePayload] {
        items.compactMap { item in
            if let generatedQueueCandidate = model.appleMusicGeneratedQueueCandidate(for: item) {
                return generatedQueueCandidate.playbackPayload(for: item)
            }

            return model.appleMusicExactPlaybackCandidate(for: item)?.payload
        }
    }
}

#Preview {
    NavigationStack {
        AppleMusicItemCollectionView(
            title: "Tracks",
            subtitle: nil,
            items: [
                SonoicSourceItem.appleMusicMetadata(
                    id: "preview-song",
                    title: "Sweet Jane",
                    subtitle: "Garrett Kato",
                    artworkURL: nil,
                    kind: .song,
                    origin: .catalogSearch
                )
            ]
        )
        .environment(SonoicModel())
    }
}
