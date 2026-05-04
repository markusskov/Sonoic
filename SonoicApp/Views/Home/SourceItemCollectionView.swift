import SwiftUI

struct SourceItemCollectionView: View {
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

                    SonoicListCard {
                        SonoicListRows(items) { item, index in
                            SourceItemNavigationRow(
                                item: item,
                                playOverride: playlistTrackPlayAction(for: item, at: index)
                            )
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
            await playPlaylistTrack(at: index)
        }
    }

    private func playPlaylistTrack(at index: Int) async {
        guard let parentItem else {
            return
        }

        await model.playSourcePlaylistQueue(
            parentItem: parentItem,
            trackItems: items,
            startingAtIndex: index
        )
    }
}

#Preview {
    NavigationStack {
        SourceItemCollectionView(
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
