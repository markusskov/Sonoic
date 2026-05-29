import SwiftUI

private enum PlayerTransportCommand {
    case previous
    case playPause
    case next
}

struct PlayerTransportControls: View {
    let nowPlaying: SonosNowPlayingSnapshot
    let isPlaybackControlEnabled: Bool
    let skipPrevious: () async -> Void
    let togglePlayback: () async -> Void
    let skipNext: () async -> Void
    @State private var pendingCommand: PlayerTransportCommand?

    var body: some View {
        HStack(spacing: 28) {
            Button {
                run(.previous, action: skipPrevious)
            } label: {
                Label("Previous", systemImage: "backward.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2.weight(.semibold))
                    .frame(width: 58, height: 58)
                    .sonoicCommandPulse(isActive: pendingCommand == .previous, cornerRadius: 29)
            }
            .disabled(!canSkipPrevious)
            .buttonStyle(.plain)

            Button {
                run(.playPause, action: togglePlayback)
            } label: {
                Label(
                    nowPlaying.playbackState.controlTitle,
                    systemImage: nowPlaying.playbackState.controlSystemImage
                )
                .labelStyle(.iconOnly)
                .font(.title2.weight(.semibold))
                .frame(width: 74, height: 74)
                .sonoicCommandPulse(isActive: pendingCommand == .playPause, cornerRadius: 37)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!canTogglePlayback)

            Button {
                run(.next, action: skipNext)
            } label: {
                Label("Next", systemImage: "forward.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2.weight(.semibold))
                    .frame(width: 58, height: 58)
                    .sonoicCommandPulse(isActive: pendingCommand == .next, cornerRadius: 29)
            }
            .disabled(!canSkipNext)
            .buttonStyle(.plain)
        }
        .onChange(of: isPlaybackControlEnabled) { _, isEnabled in
            if !isEnabled {
                pendingCommand = nil
            }
        }
    }

    private var canSkipPrevious: Bool {
        isPlaybackControlEnabled && nowPlaying.canSkipPrevious
    }

    private var canTogglePlayback: Bool {
        isPlaybackControlEnabled && nowPlaying.canTogglePlayback
    }

    private var canSkipNext: Bool {
        isPlaybackControlEnabled && nowPlaying.canSkipNext
    }

    private func run(_ command: PlayerTransportCommand, action: @escaping () async -> Void) {
        guard isCommandEnabled(command) else {
            pendingCommand = nil
            return
        }

        pendingCommand = command

        Task {
            await action()
            try? await Task.sleep(for: .milliseconds(160))

            await MainActor.run {
                if pendingCommand == command {
                    pendingCommand = nil
                }
            }
        }
    }

    private func isCommandEnabled(_ command: PlayerTransportCommand) -> Bool {
        switch command {
        case .previous:
            canSkipPrevious
        case .playPause:
            canTogglePlayback
        case .next:
            canSkipNext
        }
    }
}

#Preview("Player Transport Controls") {
    VStack(spacing: 24) {
        PlayerTransportControls(
            nowPlaying: SonosNowPlayingSnapshot(
                title: "Unwritten",
                artistName: "Natasha Bedingfield",
                albumTitle: "Unwritten",
                sourceName: "Apple Music",
                playbackState: .playing
            ),
            isPlaybackControlEnabled: true,
            skipPrevious: {},
            togglePlayback: {},
            skipNext: {}
        )

        PlayerTransportControls(
            nowPlaying: SonosNowPlayingSnapshot(
                title: "Unwritten",
                artistName: "Natasha Bedingfield",
                albumTitle: "Unwritten",
                sourceName: "Apple Music",
                playbackState: .playing
            ),
            isPlaybackControlEnabled: false,
            skipPrevious: {},
            togglePlayback: {},
            skipNext: {}
        )
    }
    .padding()
}
