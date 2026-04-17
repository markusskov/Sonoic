import SwiftUI

struct PlayerSheetView: View {
    @Environment(SonoicModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                PlayerArtworkView(
                    artworkIdentifier: model.nowPlaying.artworkIdentifier,
                    reloadKey: artworkReloadKey,
                    cornerRadius: 28
                )
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Text(model.nowPlaying.title)
                        .font(.title.weight(.bold))
                        .lineLimit(2)

                    Text(model.nowPlaying.subtitle ?? model.nowPlaying.sourceName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PlayerProgressSection(
                    nowPlaying: model.nowPlaying,
                    observedAt: model.nowPlayingObservedAt,
                    isEnabled: model.hasManualSonosHost,
                    seek: { timeInterval in
                        Task {
                            _ = await model.seekManualSonosPlayback(to: timeInterval)
                        }
                    }
                )

                HStack(spacing: 28) {
                    Button("Previous", systemImage: "backward.fill") {
                        Task {
                            await model.skipToPreviousManualSonosTrack()
                        }
                    }
                    .disabled(!supportsTrackNavigation)
                    .buttonStyle(PlayerTransportButtonStyle())

                    Button(model.nowPlaying.playbackState.controlTitle, systemImage: model.nowPlaying.playbackState.controlSystemImage) {
                        Task {
                            await model.toggleManualSonosPlayback()
                        }
                    }
                    .buttonStyle(PlayerPrimaryTransportButtonStyle())

                    Button("Next", systemImage: "forward.fill") {
                        Task {
                            await model.skipToNextManualSonosTrack()
                        }
                    }
                    .disabled(!supportsTrackNavigation)
                    .buttonStyle(PlayerTransportButtonStyle())
                }
                .labelStyle(.iconOnly)

                VStack(spacing: 14) {
                    HStack {
                        Label(model.activeTarget.name, systemImage: model.activeTarget.kind.systemImage)
                        Spacer()
                        Label(model.nowPlaying.sourceName, systemImage: "music.note.list")
                    }

                    HStack {
                        Label(model.externalVolume.labelText, systemImage: model.externalVolume.systemImage)
                        Spacer()

                        Button(muteButtonTitle, systemImage: muteButtonSystemImage) {
                            Task {
                                await model.toggleManualSonosMute()
                            }
                        }
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(18)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var supportsTrackNavigation: Bool {
        model.nowPlaying.supportsTrackNavigation
    }

    private var muteButtonTitle: String {
        model.externalVolume.isMuted ? "Unmute" : "Mute"
    }

    private var muteButtonSystemImage: String {
        model.externalVolume.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
    }

    private var artworkReloadKey: String {
        [
            model.nowPlaying.artworkIdentifier,
            model.nowPlaying.title,
            model.nowPlaying.artistName,
            model.nowPlaying.albumTitle,
            model.nowPlaying.sourceName,
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }
}

private struct PlayerTransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(.semibold))
            .frame(width: 58, height: 58)
            .background(.thinMaterial, in: Circle())
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

private struct PlayerPrimaryTransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2.weight(.semibold))
            .frame(width: 74, height: 74)
            .background(.black.opacity(0.82), in: Circle())
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

#Preview {
    @Previewable @State var model = SonoicModel()

    PlayerSheetView()
        .environment(model)
}
