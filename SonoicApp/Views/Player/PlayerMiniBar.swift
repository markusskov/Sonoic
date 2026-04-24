import SwiftUI

struct PlayerMiniBar: View {
    let nowPlaying: SonosNowPlayingSnapshot
    let openPlayer: () -> Void
    let togglePlayback: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: openPlayer) {
                    HStack(spacing: 12) {
                        PlayerArtworkView(
                            artworkIdentifier: nowPlaying.artworkIdentifier,
                            reloadKey: artworkReloadKey,
                            cornerRadius: 14,
                            maximumDisplayDimension: 52
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

                Button(action: togglePlayback) {
                    Label(
                        nowPlaying.playbackState.controlTitle,
                        systemImage: nowPlaying.playbackState.controlSystemImage
                    )
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                }
                .foregroundStyle(.primary)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
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
