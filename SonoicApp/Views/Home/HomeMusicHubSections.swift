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

struct HomeServicesSection: View {
    let services: [SonosServiceDescriptor]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(services) { service in
                    HomeServiceChip(service: service)
                }
            }
            .padding(.vertical, 2)
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
                HomeFavoriteArtworkView(artworkURL: favorite.artworkURL)
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

private struct HomeFavoriteArtworkView: View {
    let artworkURL: String?

    var body: some View {
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
    let service: SonosServiceDescriptor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: service.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: Circle())

            Text(service.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
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
