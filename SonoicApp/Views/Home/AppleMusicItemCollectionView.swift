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
                .lineLimit(2)

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
              sectionID == "tracks",
              item.kind == .song
        else {
            return nil
        }

        return {
            await playPlaylistTrack(item, trackNumber: index + 1)
        }
    }

    private func playPlaylistTrack(_ item: SonoicSourceItem, trackNumber: Int) async {
        guard let parentItem,
              let playlistPayload = playlistPlaybackPayload(for: parentItem)
        else {
            return
        }

        let localPayload = localNowPlayingPayload(for: item)
        _ = await model.playManualSonosPayload(
            playlistPayload,
            startingTrackNumber: trackNumber,
            localNowPlayingPayload: localPayload
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
