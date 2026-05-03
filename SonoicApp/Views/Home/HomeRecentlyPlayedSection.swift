import SwiftUI

struct HomeRecentlyPlayedSection: View {
    let items: [SonoicRecentPlayItem]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(items) { item in
                    HomeRecentPlayCard(item: item)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

private struct HomeRecentPlayCard: View {
    let item: SonoicRecentPlayItem

    private var sourceItem: SonoicSourceItem? {
        guard item.service != nil else {
            return nil
        }

        return SonoicSourceItem(recentPlay: item)
    }

    var body: some View {
        Group {
            if let sourceItem, sourceItem.kind != .song {
                NavigationLink {
                    SourceItemDetailView(item: sourceItem)
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .frame(width: 156, alignment: .leading)
    }

    private var cardContent: some View {
        SourceArtworkCaptionTile(
            title: item.title,
            subtitle: item.subtitle ?? item.sourceName,
            badgeTitle: item.sourceName,
            badgeSystemImage: item.service?.systemImage ?? "music.note",
            artworkURL: item.artworkURL,
            artworkIdentifier: item.artworkIdentifier,
            artworkDimension: 156,
            width: 156,
            titleFont: .subheadline.weight(.semibold),
            subtitleFont: .caption,
            badgeFont: .caption2.weight(.medium)
        )
    }
}
