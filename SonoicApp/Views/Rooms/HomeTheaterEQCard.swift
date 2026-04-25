import SwiftUI

struct HomeTheaterEQCard: View {
    let settings: SonosHomeTheaterSettings
    @Binding var bassLevel: Double
    @Binding var trebleLevel: Double
    let isEnabled: Bool
    let bassEditingChanged: (Bool) -> Void
    let trebleEditingChanged: (Bool) -> Void
    let setLoudness: (Bool) -> Void

    var body: some View {
        RoomSurfaceCard {
            HomeTheaterSliderRow(
                title: "Bass",
                systemImage: "waveform.path.ecg",
                value: $bassLevel,
                range: SonosHomeTheaterSettings.toneRange,
                valueText: homeTheaterSignedValueText(Int(bassLevel.rounded())),
                isEnabled: isEnabled,
                editingChanged: bassEditingChanged
            )

            Divider()

            HomeTheaterSliderRow(
                title: "Treble",
                systemImage: "waveform",
                value: $trebleLevel,
                range: SonosHomeTheaterSettings.toneRange,
                valueText: homeTheaterSignedValueText(Int(trebleLevel.rounded())),
                isEnabled: isEnabled,
                editingChanged: trebleEditingChanged
            )

            Divider()

            Toggle(
                isOn: Binding(
                    get: {
                        settings.loudness
                    },
                    set: { isEnabled in
                        setLoudness(isEnabled)
                    }
                )
            ) {
                Label("Loudness", systemImage: "speaker.wave.3.fill")
            }
            .font(.subheadline.weight(.medium))
            .disabled(!isEnabled)
        }
    }
}
