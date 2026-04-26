import SwiftUI

struct RoomVolumeSliderRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let volume: SonoicExternalControlState.Volume
    let isEnabled: Bool
    let setVolume: (Int) async -> Bool
    let toggleMute: () async -> Void

    @State private var draftVolume = 0.0
    @State private var isEditing = false
    @State private var volumeCommitTask: Task<Void, Never>?

    private var volumeLabel: String {
        volume.isMuted ? "Muted" : "\(Int(draftVolume.rounded()))%"
    }

    private var muteSystemImage: String {
        volume.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            slider
        }
        .padding(.vertical, 12)
        .onChange(of: volume.level, initial: true) { _, newValue in
            guard !isEditing else {
                return
            }

            draftVolume = Double(newValue)
        }
        .onDisappear {
            volumeCommitTask?.cancel()
            volumeCommitTask = nil
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoomSurfaceIconView(
                systemImage: systemImage,
                size: 44,
                cornerRadius: 14,
                font: .body.weight(.semibold),
                style: .glass
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(volume.isMuted ? "Unmute" : "Mute", systemImage: muteSystemImage, action: muteTapped)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .disabled(!isEnabled)

            Text(volumeLabel)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(volume.isMuted ? .secondary : .primary)
                .frame(minWidth: 54, alignment: .trailing)
        }
    }

    private var slider: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.tertiary)

            Slider(
                value: Binding(
                    get: { draftVolume },
                    set: { newValue in
                        updateDraftVolume(newValue)
                    }
                ),
                in: 0 ... 100,
                step: 1,
                onEditingChanged: handleEditingChanged
            )
            .disabled(!isEnabled && !isEditing)

            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.tertiary)
        }
    }

    private func handleEditingChanged(_ editing: Bool) {
        isEditing = editing

        if !editing {
            commitVolumeImmediately()
        }
    }

    private func updateDraftVolume(_ newValue: Double) {
        draftVolume = min(max(newValue.rounded(), 0), 100)
        scheduleVolumeCommit()
    }

    private func scheduleVolumeCommit() {
        volumeCommitTask?.cancel()

        let level = Int(draftVolume.rounded())
        volumeCommitTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            _ = await setVolume(level)
        }
    }

    private func commitVolumeImmediately() {
        volumeCommitTask?.cancel()
        volumeCommitTask = nil

        let level = Int(draftVolume.rounded())
        Task {
            _ = await setVolume(level)
        }
    }

    private func muteTapped() {
        Task {
            await toggleMute()
        }
    }
}

struct RoomVolumeMessageRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let isLoading: Bool
    let actionTitle: String?
    let action: (() async -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            icon
            message
            Spacer(minLength: 0)
            actionButton
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var icon: some View {
        if isLoading {
            ProgressView()
                .frame(width: 44, height: 44)
        } else {
            RoomSurfaceIconView(
                systemImage: systemImage,
                size: 44,
                cornerRadius: 14,
                font: .body.weight(.semibold),
                tint: .secondary,
                style: .glass
            )
        }
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle, let action {
            Button(actionTitle) {
                Task {
                    await action()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
