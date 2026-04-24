import SwiftUI

struct PlayerSheetView: View {
    @Environment(SonoicModel.self) var model
    @State var isAdjustingVolume = false
    @State var volumeCommitTask: Task<Void, Never>?
    @State var volumeLevel = 0.0

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 24) {
                VStack(spacing: 28) {
                    PlayerArtworkView(
                        artworkIdentifier: model.nowPlaying.artworkIdentifier,
                        reloadKey: artworkReloadKey,
                        cornerRadius: 28,
                        maximumDisplayDimension: 360
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
                            seek(to: timeInterval)
                        }
                    )

                    PlayerTransportControls(
                        nowPlaying: model.nowPlaying,
                        skipPrevious: skipToPreviousTrack,
                        togglePlayback: togglePlayback,
                        skipNext: skipToNextTrack
                    )

                    PlayerVolumeSection(
                        activeTargetName: model.activeTarget.name,
                        activeTargetSystemImage: model.activeTarget.kind.systemImage,
                        sourceName: model.nowPlaying.sourceName,
                        volume: volumeBinding,
                        volumeLabelText: volumeLabelText,
                        volumeSystemImage: volumeSystemImage,
                        muteButtonTitle: muteButtonTitle,
                        muteButtonSystemImage: muteButtonSystemImage,
                        isEnabled: model.hasManualSonosHost,
                        volumeEditingChanged: handleVolumeEditingChanged,
                        toggleMute: toggleMute
                    )
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollIndicators(.hidden)
        .onChange(of: model.externalVolume.level, initial: true) { _, newValue in
            guard !isAdjustingVolume else {
                return
            }

            volumeLevel = Double(newValue)
        }
        .onDisappear {
            volumeCommitTask?.cancel()
            volumeCommitTask = nil
        }
    }
}

#Preview {
    @Previewable @State var model = SonoicModel()

    PlayerSheetView()
        .environment(model)
}
