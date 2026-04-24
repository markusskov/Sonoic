import SwiftUI

struct HomeRecentlyPlayedSection: View {
    let items: [SonoicRecentPlayItem]
    let playRecentItem: (SonoicRecentPlayItem) async -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(items) { item in
                    HomeRecentPlayCard(item: item) {
                        await playRecentItem(item)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

private struct HomeRecentPlayCard: View {
    let item: SonoicRecentPlayItem
    let playAction: () async -> Void

    var body: some View {
        Group {
            if item.canReplay {
                Button(action: playTapped) {
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
            ZStack(alignment: .bottomTrailing) {
                HomeFavoriteArtworkView(
                    artworkURL: item.artworkURL,
                    artworkIdentifier: item.artworkIdentifier,
                    maximumDisplayDimension: 156
                )
                .frame(width: 156, height: 156)

                playBadge
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(item.subtitle ?? item.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Label(item.sourceName, systemImage: item.service?.systemImage ?? "music.note")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var playBadge: some View {
        if item.canReplay {
            Image(systemName: "play.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .glassEffect(.regular, in: Circle())
                .padding(8)
        }
    }

    private func playTapped() {
        Task {
            await playAction()
        }
    }
}
