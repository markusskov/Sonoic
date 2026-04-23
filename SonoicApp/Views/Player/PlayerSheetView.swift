import SwiftUI

struct PlayerSheetView: View {
    @Environment(SonoicModel.self) private var model
    @State private var isAdjustingVolume = false
    @State private var volumeCommitTask: Task<Void, Never>?
    @State private var volumeLevel = 0.0

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
                            Task {
                                _ = await model.seekManualSonosPlayback(to: timeInterval)
                            }
                        }
                    )

                    HStack(spacing: 28) {
                        Button {
                            Task {
                                await model.skipToPreviousManualSonosTrack()
                            }
                        } label: {
                            Label("Previous", systemImage: "backward.fill")
                                .labelStyle(.iconOnly)
                                .font(.title2.weight(.semibold))
                                .frame(width: 58, height: 58)
                        }
                        .disabled(!supportsTrackNavigation)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)

                        Button {
                            Task {
                                await model.toggleManualSonosPlayback()
                            }
                        } label: {
                            Label(
                                model.nowPlaying.playbackState.controlTitle,
                                systemImage: model.nowPlaying.playbackState.controlSystemImage
                            )
                            .labelStyle(.iconOnly)
                            .font(.title2.weight(.semibold))
                            .frame(width: 74, height: 74)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)

                        Button {
                            Task {
                                await model.skipToNextManualSonosTrack()
                            }
                        } label: {
                            Label("Next", systemImage: "forward.fill")
                                .labelStyle(.iconOnly)
                                .font(.title2.weight(.semibold))
                                .frame(width: 58, height: 58)
                        }
                        .disabled(!supportsTrackNavigation)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                    }

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

    private var supportsTrackNavigation: Bool {
        model.nowPlaying.supportsTrackNavigation
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: {
                volumeLevel
            },
            set: { newValue in
                volumeLevel = min(max(newValue.rounded(), 0), 100)
                scheduleVolumeCommit()
            }
        )
    }

    private var volumeLabelText: String {
        model.externalVolume.isMuted ? "Muted" : "\(Int(volumeLevel.rounded()))%"
    }

    private var volumeSystemImage: String {
        if model.externalVolume.isMuted || volumeLevel == 0 {
            return "speaker.slash.fill"
        }

        if volumeLevel < 34 {
            return "speaker.wave.1.fill"
        }

        if volumeLevel < 67 {
            return "speaker.wave.2.fill"
        }

        return "speaker.wave.3.fill"
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

    private func handleVolumeEditingChanged(_ isEditing: Bool) {
        isAdjustingVolume = isEditing

        if !isEditing {
            commitVolumeImmediately()
        }
    }

    private func scheduleVolumeCommit() {
        volumeCommitTask?.cancel()

        let targetLevel = Int(volumeLevel.rounded())
        volumeCommitTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            Task { @MainActor in
                _ = await model.setManualSonosVolume(to: targetLevel)
            }
        }
    }

    private func commitVolumeImmediately() {
        volumeCommitTask?.cancel()
        volumeCommitTask = nil

        let targetLevel = Int(volumeLevel.rounded())
        Task { @MainActor in
            _ = await model.setManualSonosVolume(to: targetLevel)
        }
    }

    private func toggleMute() {
        Task {
            await model.toggleManualSonosMute()
        }
    }
}

private struct PlayerVolumeSection: View {
    let activeTargetName: String
    let activeTargetSystemImage: String
    let sourceName: String
    @Binding var volume: Double
    let volumeLabelText: String
    let volumeSystemImage: String
    let muteButtonTitle: String
    let muteButtonSystemImage: String
    let isEnabled: Bool
    let volumeEditingChanged: (Bool) -> Void
    let toggleMute: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label(activeTargetName, systemImage: activeTargetSystemImage)
                Spacer()
                Label(sourceName, systemImage: "music.note.list")
            }

            Divider()

            VStack(spacing: 10) {
                HStack {
                    Label(volumeLabelText, systemImage: volumeSystemImage)
                    Spacer()

                    Button(muteButtonTitle, systemImage: muteButtonSystemImage, action: toggleMute)
                        .buttonStyle(.glass)
                        .disabled(!isEnabled)
                }

                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.tertiary)

                    Slider(
                        value: $volume,
                        in: 0 ... 100,
                        step: 1,
                        onEditingChanged: volumeEditingChanged
                    )
                    .disabled(!isEnabled)

                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    @Previewable @State var model = SonoicModel()

    PlayerSheetView()
        .environment(model)
}
