import SwiftUI

struct PlayerTransportControls: View {
    let nowPlaying: SonosNowPlayingSnapshot
    let skipPrevious: () async -> Void
    let togglePlayback: () async -> Void
    let skipNext: () async -> Void

    private var supportsTrackNavigation: Bool {
        nowPlaying.supportsTrackNavigation
    }

    var body: some View {
        HStack(spacing: 28) {
            Button(action: skipPreviousTapped) {
                Label("Previous", systemImage: "backward.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2.weight(.semibold))
                    .frame(width: 58, height: 58)
            }
            .disabled(!supportsTrackNavigation)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)

            Button(action: playPauseTapped) {
                Label(
                    nowPlaying.playbackState.controlTitle,
                    systemImage: nowPlaying.playbackState.controlSystemImage
                )
                .labelStyle(.iconOnly)
                .font(.title2.weight(.semibold))
                .frame(width: 74, height: 74)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)

            Button(action: skipNextTapped) {
                Label("Next", systemImage: "forward.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2.weight(.semibold))
                    .frame(width: 58, height: 58)
            }
            .disabled(!supportsTrackNavigation)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
    }

    private func skipPreviousTapped() {
        Task {
            await skipPrevious()
        }
    }

    private func playPauseTapped() {
        Task {
            await togglePlayback()
        }
    }

    private func skipNextTapped() {
        Task {
            await skipNext()
        }
    }
}
