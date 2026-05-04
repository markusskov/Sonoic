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
