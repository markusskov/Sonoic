import SwiftUI

struct HomeSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct HomeNowPlayingCard: View {
    let activeTarget: SonosActiveTarget
    let nowPlaying: SonosNowPlayingSnapshot
    let queueState: SonosQueueState
    let togglePlayback: () async -> Void
    let openRooms: () -> Void
    let openQueue: () -> Void

    private var queueSummary: String {
        switch queueState {
        case .idle, .loading:
            return "Queue loading"
        case .unavailable:
            return "No active queue"
        case .failed:
            return "Queue needs refresh"
        case let .loaded(snapshot):
            return snapshot.currentPositionText ?? snapshot.itemCountText
        }
    }

    var body: some View {
        RoomSurfaceCard {
            HStack(alignment: .top, spacing: 16) {
                PlayerArtworkView(
                    artworkIdentifier: nowPlaying.artworkIdentifier,
                    reloadKey: nowPlaying.artworkIdentifier ?? nowPlaying.artworkURL ?? nowPlaying.title,
                    cornerRadius: 22,
                    maximumDisplayDimension: 92
                )
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label(activeTarget.name, systemImage: activeTarget.kind.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }

                    Text(nowPlaying.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(nowPlaying.subtitle ?? nowPlaying.sourceName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(queueSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    nowPlayingControls
                }

                VStack(alignment: .leading, spacing: 10) {
                    nowPlayingControls
                }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var nowPlayingControls: some View {
        Button {
            Task {
                await togglePlayback()
            }
        } label: {
            Label(nowPlaying.playbackState.controlTitle, systemImage: nowPlaying.playbackState.controlSystemImage)
        }
        .buttonStyle(.borderedProminent)

        Button(action: openQueue) {
            Label("Queue", systemImage: "list.triangle")
        }
        .buttonStyle(.bordered)

        Button(action: openRooms) {
            Label(activeTarget.kind.title, systemImage: activeTarget.kind.systemImage)
        }
        .buttonStyle(.bordered)
    }
}

struct HomeFavoritesSection: View {
    let state: SonosFavoritesState
    let playFavorite: (SonosFavoriteItem) async -> Void
    let retryAction: () async -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        HomeFavoriteLoadingCard()
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        case .empty:
            HomeMessageCard(
                title: "No Favorites Yet",
                detail: "Save a few Sonos favorites in the Sonos app and they’ll appear here for quick playback."
            )
        case let .failed(detail):
            HomeActionCard(
                title: "Couldn't Load Favorites",
                detail: detail,
                buttonTitle: "Try Again",
                buttonSystemImage: "arrow.clockwise",
                action: retryAction
            )
        case let .loaded(snapshot):
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(snapshot.items) { favorite in
                        HomeFavoriteCard(favorite: favorite) {
                            await playFavorite(favorite)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }
}

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

struct HomeCollectionsSection: View {
    let collections: [SonosFavoriteItem]
    let playFavorite: (SonosFavoriteItem) async -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(collections) { collection in
                    HomeFavoriteCard(favorite: collection) {
                        await playFavorite(collection)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

struct HomeServicesSection: View {
    let summaries: [SonoicHomeSourceSummary]

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(summaries) { summary in
                        HomeServiceChip(summary: summary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct HomeFavoriteCard: View {
    let favorite: SonosFavoriteItem
    let playAction: () async -> Void

    var body: some View {
        Button {
            Task {
                await playAction()
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HomeFavoriteArtworkView(
                    artworkURL: favorite.artworkURL,
                    artworkIdentifier: nil,
                    maximumDisplayDimension: 178
                )
                    .frame(width: 178, height: 178)

                VStack(alignment: .leading, spacing: 6) {
                    Text(favorite.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(favorite.subtitle ?? favorite.service?.name ?? "Sonos Favorite")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let service = favorite.service {
                        Label(service.name, systemImage: service.systemImage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 178, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct HomeRecentPlayCard: View {
    let item: SonoicRecentPlayItem
    let playAction: () async -> Void

    var body: some View {
        Group {
            if item.canReplay {
                Button {
                    Task {
                        await playAction()
                    }
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
            ZStack(alignment: .bottomTrailing) {
                HomeFavoriteArtworkView(
                    artworkURL: item.artworkURL,
                    artworkIdentifier: item.artworkIdentifier,
                    maximumDisplayDimension: 156
                )
                    .frame(width: 156, height: 156)

                if item.canReplay {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular, in: Circle())
                        .padding(8)
                }
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
}

private struct HomeFavoriteArtworkView: View {
    let artworkURL: String?
    let artworkIdentifier: String?
    let maximumDisplayDimension: CGFloat

    var body: some View {
        if let artworkIdentifier {
            PlayerArtworkView(
                artworkIdentifier: artworkIdentifier,
                reloadKey: artworkIdentifier,
                cornerRadius: 26,
                maximumDisplayDimension: maximumDisplayDimension
            )
        } else {
            AsyncImage(url: artworkURL.flatMap(URL.init(string:))) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.orange.opacity(0.85), .pink.opacity(0.7), .indigo.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                @unknown default:
                    Color.secondary.opacity(0.12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            }
        }
    }
}

private struct HomeFavoriteLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.quaternary.opacity(0.35))
                .frame(width: 178, height: 178)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.35))
                .frame(width: 140, height: 18)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.25))
                .frame(width: 96, height: 14)
        }
        .frame(width: 178, alignment: .leading)
        .redacted(reason: .placeholder)
    }
}

private struct HomeServiceChip: View {
    let summary: SonoicHomeSourceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: summary.service.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(summary.service.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if summary.isCurrent {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(summary.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 220, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

private struct HomeMessageCard: View {
    let title: String
    let detail: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HomeActionCard: View {
    let title: String
    let detail: String
    let buttonTitle: String
    let buttonSystemImage: String
    let action: () async -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button(buttonTitle, systemImage: buttonSystemImage) {
                    Task {
                        await action()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
