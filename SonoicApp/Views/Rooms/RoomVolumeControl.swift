import SwiftUI

struct RoomVolumeControl: View {
    let player: SonosDiscoveredPlayer
    let volume: SonoicExternalControlState.Volume
    let isMutating: Bool
    let setRoomVolume: (SonosDiscoveredPlayer, Int) async -> Void
    let toggleRoomMute: (SonosDiscoveredPlayer) async -> Void

    @State private var level: Double
    @State private var isEditing = false

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
                    set: { level = $0 }
                ),
                bounds: 0...100,
                step: 1,
                isEnabled: !isMutating,
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
    }

    private func updateEditing(_ editing: Bool) {
        isEditing = editing

        guard !editing else {
            return
        }

        Task {
            await setRoomVolume(player, Int(level.rounded()))
        }
    }
}
