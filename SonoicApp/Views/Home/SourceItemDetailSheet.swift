import SwiftUI

struct SourceItemDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: SonoicSourceItem
    let playAction: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                capabilityCard

                if item.playbackCapability.canPlay {
                    primaryActionButton
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .presentationBackground(.regularMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HomeFavoriteArtworkView(
                artworkURL: item.artworkURL,
                artworkIdentifier: item.artworkIdentifier,
                maximumDisplayDimension: 240
            )
            .frame(width: 240, height: 240)
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                Label(item.kind.title, systemImage: item.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(item.title)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Label(item.service.name, systemImage: item.service.systemImage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                itemChips
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var capabilityCard: some View {
        RoomSurfaceCard {
            Label(item.playbackCapability.displayTitle, systemImage: capabilitySystemImage)
                .font(.headline)
        }
    }

    private var itemChips: some View {
        HStack(spacing: 8) {
            SourceItemDetailChip(title: originTitle, systemImage: originSystemImage)
            SourceItemDetailChip(title: item.kind.title, systemImage: item.kind.systemImage)
        }
    }

    private var primaryActionButton: some View {
        SourceItemDetailActionButton(
            title: "Play",
            systemImage: "play.fill",
            action: playTapped
        )
    }

    private var capabilitySystemImage: String {
        item.playbackCapability.canPlay ? "checkmark.circle.fill" : "lock.circle"
    }

    private var originTitle: String {
        switch item.origin {
        case .catalogSearch:
            "Catalog"
        case .favorite:
            "Favorite"
        case .library:
            "Library"
        case .recentPlay:
            "Recent"
        }
    }

    private var originSystemImage: String {
        switch item.origin {
        case .catalogSearch:
            "magnifyingglass"
        case .favorite:
            "star"
        case .library:
            "rectangle.stack"
        case .recentPlay:
            "clock"
        }
    }

    private func playTapped() {
        Task {
            await playAction()
            dismiss()
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

private struct SourceItemDetailActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

#Preview {
    SourceItemDetailSheet(
        item: SonoicSourceItem.catalogMetadata(
            id: "preview-song",
            title: "Suspicious Minds",
            subtitle: "Elvis Presley",
            artworkURL: nil,
            kind: .song,
            service: .appleMusic
        )
    ) {}
}
