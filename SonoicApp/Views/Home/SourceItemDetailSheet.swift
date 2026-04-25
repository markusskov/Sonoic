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
                actionGrid
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var capabilityCard: some View {
        RoomSurfaceCard {
            Label(item.playbackCapability.displayTitle, systemImage: capabilitySystemImage)
                .font(.headline)

            Text(capabilityDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var actionGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                SourceItemDetailActionButton(
                    title: "Play on Sonos",
                    systemImage: "play.fill",
                    isEnabled: item.playbackCapability.canPlay,
                    action: playTapped
                )

                SourceItemDetailActionButton(
                    title: "Play Next",
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    isEnabled: false
                ) {}
            }

            GridRow {
                SourceItemDetailActionButton(
                    title: "Add to Queue",
                    systemImage: "text.badge.plus",
                    isEnabled: false
                ) {}

                SourceItemDetailActionButton(
                    title: "Save",
                    systemImage: "plus.circle",
                    isEnabled: false
                ) {}
            }
        }
    }

    private var capabilitySystemImage: String {
        item.playbackCapability.canPlay ? "checkmark.circle.fill" : "lock.circle"
    }

    private var capabilityDetail: String {
        item.playbackCapability.disabledReason ?? "This item includes a Sonos-native payload and can start playback."
    }

    private func playTapped() {
        Task {
            await playAction()
            dismiss()
        }
    }
}

private struct SourceItemDetailActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .glassEffect(isEnabled ? .regular.interactive() : .regular, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
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
