import SwiftUI

struct HomeFavoriteCard: View {
    let favorite: SonosFavoriteItem
    let playAction: () async -> Void

    var body: some View {
        Button(action: playTapped) {
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

    private func playTapped() {
        Task {
            await playAction()
        }
    }
}

struct HomeFavoriteArtworkView: View {
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
                    placeholder
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

    private var placeholder: some View {
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
    }
}

struct HomeFavoriteLoadingCard: View {
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
