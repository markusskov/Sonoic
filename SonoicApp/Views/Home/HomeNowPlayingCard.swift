import SwiftUI

struct HomeNowPlayingCard: View {
    let nowPlaying: SonosNowPlayingSnapshot

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(nowPlaying.title)
                        .font(.title3.weight(.semibold))

                    if let subtitle = nowPlaying.subtitle {
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Label(nowPlaying.playbackState.title, systemImage: nowPlaying.playbackState.systemImage)
                    Label(nowPlaying.sourceName, systemImage: "music.note.list")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Now Playing", systemImage: "music.note")
        }
    }
}

#Preview {
    HomeNowPlayingCard(
        nowPlaying: SonosNowPlayingSnapshot(
            title: "Unwritten",
            artistName: "Natasha Bedingfield",
            albumTitle: "Unwritten",
            sourceName: "Apple Music",
            playbackState: .playing
        )
    )
    .padding()
}
