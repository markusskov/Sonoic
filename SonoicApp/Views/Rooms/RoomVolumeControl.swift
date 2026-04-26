import SwiftUI

struct RoomVolumeControl: View {
    let item: SonosRoomVolumeItem
    let isMutating: Bool
    let setRoomVolume: (SonosRoomVolumeItem, Int) async -> Bool
    let toggleRoomMute: (SonosRoomVolumeItem) async -> Void

    @State private var level: Double
    @State private var isEditing = false
    @State private var volumeCommitTask: Task<Void, Never>?

    init(
        item: SonosRoomVolumeItem,
        isMutating: Bool,
        setRoomVolume: @escaping (SonosRoomVolumeItem, Int) async -> Bool,
        toggleRoomMute: @escaping (SonosRoomVolumeItem) async -> Void
    ) {
        self.item = item
        self.isMutating = isMutating
        self.setRoomVolume = setRoomVolume
        self.toggleRoomMute = toggleRoomMute
        _level = State(initialValue: Double(item.volume.level))
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await toggleRoomMute(item)
                }
            } label: {
                Image(systemName: item.volume.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .disabled(isMutating)
            .accessibilityLabel(item.volume.isMuted ? "Unmute \(item.name)" : "Mute \(item.name)")

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
                accessibilityLabel: "\(item.name) volume",
                onEditingChanged: updateEditing
            )

            Text("\(Int(level.rounded()))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .onChange(of: item.volume.level) { _, newValue in
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

            _ = await setRoomVolume(item, targetLevel)
        }
    }

    private func commitVolumeImmediately() {
        volumeCommitTask?.cancel()
        volumeCommitTask = nil

        Task {
            _ = await setRoomVolume(item, Int(level.rounded()))
        }
    }
}
