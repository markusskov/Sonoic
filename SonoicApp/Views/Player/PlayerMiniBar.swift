import SwiftUI

struct PlayerMiniBar: View {
    let nowPlaying: SonosNowPlayingSnapshot
    let openPlayer: () -> Void
    let togglePlayback: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openPlayer) {
                HStack(spacing: 12) {
                    PlayerArtworkView(
                        artworkIdentifier: nowPlaying.artworkIdentifier,
                        reloadKey: artworkReloadKey,
                        cornerRadius: 14
                    )
                        .frame(width: 52, height: 52)

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
                }
            }
            .buttonStyle(.plain)

            Button(playbackButtonTitle, systemImage: playbackButtonSystemImage, action: togglePlayback)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.thickMaterial, in: Circle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
    }

    private var playbackButtonTitle: String {
        switch nowPlaying.playbackState {
        case .playing:
            "Pause"
        case .paused, .buffering:
            "Play"
        }
    }

    private var playbackButtonSystemImage: String {
        switch nowPlaying.playbackState {
        case .playing:
            "pause.fill"
        case .paused, .buffering:
            "play.fill"
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
}

#Preview {
    PlayerMiniBar(
        nowPlaying: SonosNowPlayingSnapshot(
            title: "Unwritten",
            artistName: "Natasha Bedingfield",
            albumTitle: "Unwritten",
            sourceName: "Apple Music",
            playbackState: .playing
        ),
        openPlayer: {},
        togglePlayback: {}
    )
    .padding()
}
