import SwiftUI

struct PlayerMiniBar: View {
    let nowPlaying: SonosNowPlayingSnapshot
    let isPlaybackControlEnabled: Bool
    let openPlayer: () -> Void
    let togglePlayback: () -> Void

    @State private var isTogglePending = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    PlayerArtworkView(
                        artworkIdentifier: nowPlaying.artworkIdentifier,
                        reloadKey: artworkReloadKey,
                        cornerRadius: 14,
                        maximumDisplayDimension: 52
                    )
                    .frame(width: 52, height: 52)
                    .sonoicCrossfade(value: artworkReloadKey)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(nowPlaying.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(nowPlaying.subtitle ?? nowPlaying.sourceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sonoicCrossfade(value: artworkReloadKey)
                }

                Button(action: togglePlaybackTapped) {
                    Label(
                        nowPlaying.playbackState.controlTitle,
                        systemImage: nowPlaying.playbackState.controlSystemImage
                    )
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 58, height: 58)
                    .contentShape(Rectangle())
                    .sonoicCommandPulse(isActive: isTogglePending, cornerRadius: 16)
                }
                .foregroundStyle(.primary)
                .buttonStyle(.plain)
                .disabled(!canTogglePlayback)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect(cornerRadius: 24))
            .onTapGesture(perform: openPlayer)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Open Player", openPlayer)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
        .onChange(of: canTogglePlayback) { _, canToggle in
            if !canToggle {
                isTogglePending = false
            }
        }
    }

    private var artworkReloadKey: String {
        [
            nowPlaying.artworkIdentifier,
            nowPlaying.title,
            nowPlaying.artistName,
            nowPlaying.albumTitle,
            nowPlaying.sourceName,
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    private var canTogglePlayback: Bool {
        isPlaybackControlEnabled && nowPlaying.canTogglePlayback
    }

    private func togglePlaybackTapped() {
        guard canTogglePlayback else {
            isTogglePending = false
            return
        }

        isTogglePending = true
        togglePlayback()

        Task {
            try? await Task.sleep(for: .milliseconds(160))
            await MainActor.run {
                isTogglePending = false
            }
        }
    }
}

#Preview("Enabled") {
    VStack(spacing: 16) {
        PlayerMiniBar(
            nowPlaying: SonosNowPlayingSnapshot(
                title: "Unwritten",
                artistName: "Natasha Bedingfield",
                albumTitle: "Unwritten",
                sourceName: "Apple Music",
                playbackState: .playing
            ),
            isPlaybackControlEnabled: true,
            openPlayer: {},
            togglePlayback: {}
        )
    }
    .padding()
}

#Preview("Cloud Target Unavailable") {
    VStack(spacing: 16) {
        PlayerMiniBar(
            nowPlaying: SonosNowPlayingSnapshot(
                title: "Unwritten",
                artistName: "Natasha Bedingfield",
                albumTitle: "Unwritten",
                sourceName: "Apple Music",
                playbackState: .playing
            ),
            isPlaybackControlEnabled: false,
            openPlayer: {},
            togglePlayback: {}
        )
    }
    .padding()
}
