import SwiftUI

struct PlayerFullscreenTitleBlock: View {
    let title: String
    let subtitle: String
    let artistName: String?
    let openArtist: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)

            if let artistName = artistName?.sonoicNonEmptyTrimmed {
                Button {
                    openArtist(artistName)
                } label: {
                    subtitleText
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(artistName)")
            } else {
                subtitleText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.title2)
            .foregroundStyle(.white.opacity(0.62))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
    }
}

struct PlayerFullscreenVolumeBar: View {
    @Binding var volume: Double
    let isEnabled: Bool
    let volumeEditingChanged: (Bool) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "speaker.fill")
                .font(.title3.weight(.semibold))

            PlayerScrubber(
                value: $volume,
                bounds: 0 ... 100,
                step: 1,
                isEnabled: isEnabled,
                showsThumb: false,
                accessibilityLabel: "Volume",
                onEditingChanged: volumeEditingChanged
            )

            Image(systemName: "speaker.wave.3.fill")
                .font(.title3.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(isEnabled ? 0.78 : 0.34))
    }
}

struct PlayerFullscreenSonosActions: View {
    let activeTargetSystemImage: String
    let muteButtonSystemImage: String
    let isEnabled: Bool
    let openRooms: () -> Void
    let toggleMute: () -> Void
    let openQueue: () -> Void

    var body: some View {
        HStack {
            PlayerFullscreenIconButton(
                title: "Rooms",
                systemImage: activeTargetSystemImage,
                isEnabled: isEnabled,
                action: openRooms
            )

            Spacer()

            PlayerFullscreenIconButton(
                title: "Mute",
                systemImage: muteButtonSystemImage,
                isEnabled: isEnabled,
                action: toggleMute
            )

            Spacer()

            PlayerFullscreenIconButton(
                title: "Queue",
                systemImage: "list.bullet",
                isEnabled: true,
                action: openQueue
            )
        }
        .padding(.horizontal, 36)
    }
}

private struct PlayerFullscreenIconButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 28, weight: .semibold))
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(isEnabled ? 0.68 : 0.28))
        .disabled(!isEnabled)
    }
}
