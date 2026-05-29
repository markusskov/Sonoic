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

            VStack(alignment: headerAlignment, spacing: 6) {
                if showsKindLabel {
                    Label(item.kind.title, systemImage: item.kind.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(item.title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(headerTextAlignment)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)

                if let subtitle = displayedSubtitle {
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
                alignment: headerFrameAlignment
            )
        }
    }

    private var showsKindLabel: Bool {
        item.kind != .playlist && item.kind != .artist
    }

    private var displayedSubtitle: String? {
        guard item.kind != .playlist,
              let subtitle = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !subtitle.isEmpty
        else {
            return nil
        }

        return subtitle.caseInsensitiveCompare(item.kind.title) == .orderedSame ? nil : subtitle
    }

    private var headerAlignment: HorizontalAlignment {
        item.kind == .playlist ? .center : .leading
    }

    private var headerTextAlignment: TextAlignment {
        item.kind == .playlist ? .center : .leading
    }

    private var headerFrameAlignment: Alignment {
        item.kind == .playlist ? .center : .leading
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
