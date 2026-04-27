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
            if let sourceItem {
                NavigationLink {
                    AppleMusicItemDetailView(item: sourceItem)
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
        VStack(alignment: .leading, spacing: 10) {
            HomeFavoriteArtworkView(
                artworkURL: item.artworkURL,
                artworkIdentifier: item.artworkIdentifier,
                maximumDisplayDimension: 156,
                placeholderSystemImage: placeholderSystemImage
            )
            .frame(width: 156, height: 156)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.subtitle ?? item.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Label(item.sourceName, systemImage: item.service?.systemImage ?? "music.note")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var placeholderSystemImage: String {
        switch sourceItem?.kind {
        case .album:
            "rectangle.stack"
        case .artist:
            "music.mic"
        case .playlist:
            "music.note.list"
        case .station:
            "dot.radiowaves.left.and.right"
        case .song, .unknown, .none:
            "music.note"
        }
    }
}
