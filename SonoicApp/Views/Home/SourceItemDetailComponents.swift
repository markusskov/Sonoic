import SwiftUI

struct SourceItemDetailBackground: View {
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

struct SourceItemDetailHeader: View {
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
                            SourceItemDetailChip(title: item.service.name, systemImage: item.service.systemImage)
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

struct SourcePlaylistActionRow: View {
    let isFavorite: Bool
    var canShuffle = true
    var canFavorite = true
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

            if canFavorite {
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
}

struct SourcePlaylistActionSkeletonRow: View {
    var canFavorite = true

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 54, height: 54)

            Capsule()
                .fill(.white.opacity(0.16))
                .frame(maxWidth: .infinity)
                .frame(height: 54)

            if canFavorite {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 54, height: 54)
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SourceItemActionCard: View {
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

private struct SourceItemDetailChip: View {
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
