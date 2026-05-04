import SwiftUI

struct HomeFavoriteCard: View {
    let favorite: SonosFavoriteItem
    let playAction: () async -> Void

    var body: some View {
        if let detailItem {
            NavigationLink {
                SourceItemDetailView(item: detailItem)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            Button(action: playTapped) {
                content
            }
            .buttonStyle(.plain)
        }
    }

    private var content: some View {
        SourceArtworkCaptionTile(
            title: favorite.title,
            subtitle: favorite.subtitle ?? favorite.service?.name ?? "Sonos Favorite",
            badgeTitle: favorite.service?.name,
            badgeSystemImage: favorite.service?.systemImage,
            artworkURL: favorite.artworkURL,
            artworkIdentifier: nil,
            artworkDimension: 178,
            width: 178,
            spacing: 12,
            textSpacing: 6
        )
    }

    private var detailItem: SonoicSourceItem? {
        let item = SonoicSourceItem(favorite: favorite)
        guard item.service.kind == .appleMusic,
              item.kind != .song,
              item.kind != .unknown
        else {
            return nil
        }

        return item
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
    var cornerRadius: CGFloat = 26

    var body: some View {
        if let artworkIdentifier {
            PlayerArtworkView(
                artworkIdentifier: artworkIdentifier,
                reloadKey: artworkIdentifier,
                cornerRadius: cornerRadius,
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
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            }
        }
    }

    private var placeholder: some View {
        SonoicArtworkPlaceholderView(cornerRadius: cornerRadius)
    }
}

struct SourceArtworkCaptionTile: View {
    let title: String
    let subtitle: String?
    var badgeTitle: String?
    var badgeSystemImage: String?
    let artworkURL: String?
    let artworkIdentifier: String?
    var artworkDimension: CGFloat
    var width: CGFloat?
    var artworkCornerRadius: CGFloat = 26
    var titleFont: Font = .headline
    var subtitleFont: Font = .subheadline
    var badgeFont: Font = .caption.weight(.medium)
    var spacing: CGFloat = 10
    var textSpacing: CGFloat = 5

    private var tileWidth: CGFloat {
        width ?? artworkDimension
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HomeFavoriteArtworkView(
                artworkURL: artworkURL,
                artworkIdentifier: artworkIdentifier,
                maximumDisplayDimension: artworkDimension,
                cornerRadius: artworkCornerRadius
            )
            .frame(width: artworkDimension, height: artworkDimension)

            VStack(alignment: .leading, spacing: textSpacing) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(SonoicTheme.Colors.primary)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(subtitleFont)
                        .foregroundStyle(SonoicTheme.Colors.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let badgeTitle, let badgeSystemImage {
                    Label(badgeTitle, systemImage: badgeSystemImage)
                        .font(badgeFont)
                        .foregroundStyle(SonoicTheme.Colors.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: tileWidth, alignment: .leading)
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
