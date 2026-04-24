import SwiftUI

struct HomeNowPlayingCard: View {
    let activeTarget: SonosActiveTarget
    let nowPlaying: SonosNowPlayingSnapshot
    let queueState: SonosQueueState
    let togglePlayback: () async -> Void
    let openRooms: () -> Void
    let openQueue: () -> Void

    private var queueSummary: String {
        switch queueState {
        case .idle, .loading:
            return "Queue loading"
        case .unavailable:
            return "No active queue"
        case .failed:
            return "Queue needs refresh"
        case let .loaded(snapshot):
            return snapshot.currentPositionText ?? snapshot.itemCountText
        }
    }

    var body: some View {
        RoomSurfaceCard {
            HStack(alignment: .top, spacing: 16) {
                PlayerArtworkView(
                    artworkIdentifier: nowPlaying.artworkIdentifier,
                    reloadKey: nowPlaying.artworkIdentifier ?? nowPlaying.artworkURL ?? nowPlaying.title,
                    cornerRadius: 22,
                    maximumDisplayDimension: 92
                )
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 8) {
                    Label(activeTarget.name, systemImage: activeTarget.kind.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(nowPlaying.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(nowPlaying.subtitle ?? nowPlaying.sourceName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(queueSummary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    nowPlayingControls
                }

                VStack(alignment: .leading, spacing: 10) {
                    nowPlayingControls
                }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var nowPlayingControls: some View {
        Button(action: playPauseTapped) {
            Label(nowPlaying.playbackState.controlTitle, systemImage: nowPlaying.playbackState.controlSystemImage)
        }
        .buttonStyle(.borderedProminent)

        Button(action: openQueue) {
            Label("Queue", systemImage: "list.triangle")
        }
        .buttonStyle(.bordered)

        Button(action: openRooms) {
            Label(activeTarget.kind.title, systemImage: activeTarget.kind.systemImage)
        }
        .buttonStyle(.bordered)
    }

    private func playPauseTapped() {
        Task {
            await togglePlayback()
        }
    }
}
