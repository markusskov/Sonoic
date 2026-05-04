import SwiftUI

struct SourceItemDetailSectionView: View {
    @Environment(SonoicModel.self) private var model

    let parentItem: SonoicSourceItem
    let section: SonoicSourceItemDetailSection
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
                SonoicLazyListRows(previewItems) { item, index in
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
            await playPlaylistTrack(at: index)
        }
    }

    private func playPlaylistTrack(at index: Int) async {
        await model.playSourcePlaylistQueue(
            parentItem: parentItem,
            trackItems: section.items,
            startingAtIndex: index
        )
    }
}
