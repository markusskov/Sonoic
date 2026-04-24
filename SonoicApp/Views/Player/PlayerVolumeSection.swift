import SwiftUI

struct PlayerVolumeSection: View {
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
