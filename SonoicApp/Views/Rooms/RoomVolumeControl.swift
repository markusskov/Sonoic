import SwiftUI

struct RoomVolumeControl: View {
    let player: SonosDiscoveredPlayer
    let volume: SonoicExternalControlState.Volume
    let isMutating: Bool
    let setRoomVolume: (SonosDiscoveredPlayer, Int) async -> Void
    let toggleRoomMute: (SonosDiscoveredPlayer) async -> Void

    @State private var level: Double
    @State private var isEditing = false
    @State private var volumeCommitTask: Task<Void, Never>?

    init(
        player: SonosDiscoveredPlayer,
        volume: SonoicExternalControlState.Volume,
        isMutating: Bool,
        setRoomVolume: @escaping (SonosDiscoveredPlayer, Int) async -> Void,
        toggleRoomMute: @escaping (SonosDiscoveredPlayer) async -> Void
    ) {
        self.player = player
        self.volume = volume
        self.isMutating = isMutating
        self.setRoomVolume = setRoomVolume
        self.toggleRoomMute = toggleRoomMute
        _level = State(initialValue: Double(volume.level))
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await toggleRoomMute(player)
                }
            } label: {
                Image(systemName: volume.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .disabled(isMutating)
            .accessibilityLabel(volume.isMuted ? "Unmute \(player.name)" : "Mute \(player.name)")

            PlayerScrubber(
                value: Binding(
                    get: { level },
                    set: { newValue in
                        updateLevel(newValue)
                    }
                ),
                bounds: 0...100,
                step: 1,
                isEnabled: !isMutating || isEditing,
                showsThumb: true,
                accessibilityLabel: "\(player.name) volume",
                onEditingChanged: updateEditing
            )

            Text("\(Int(level.rounded()))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .onChange(of: volume.level) { _, newValue in
            if !isEditing {
                level = Double(newValue)
            }
        }
        .onDisappear {
            volumeCommitTask?.cancel()
            volumeCommitTask = nil
        }
    }

    private func updateEditing(_ editing: Bool) {
        isEditing = editing

        if !editing {
            commitVolumeImmediately()
        }
    }

    private func updateLevel(_ newValue: Double) {
        level = min(max(newValue.rounded(), 0), 100)
        scheduleVolumeCommit()
    }

    private func scheduleVolumeCommit() {
        volumeCommitTask?.cancel()

        let targetLevel = Int(level.rounded())
        volumeCommitTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await setRoomVolume(player, targetLevel)
        }
    }

    private func commitVolumeImmediately() {
        volumeCommitTask?.cancel()
        volumeCommitTask = nil

        Task {
            await setRoomVolume(player, Int(level.rounded()))
        }
    }
}
