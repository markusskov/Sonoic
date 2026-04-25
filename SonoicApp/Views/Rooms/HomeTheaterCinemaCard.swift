import SwiftUI

struct HomeTheaterCinemaCard: View {
    let settings: SonosHomeTheaterSettings
    @Binding var subLevel: Double
    let isEnabled: Bool
    let subEditingChanged: (Bool) -> Void
    let setSpeechEnhancement: (Bool) -> Void
    let setDialogLevel: (Int) -> Void
    let setNightSound: (Bool) -> Void

    var body: some View {
        RoomSurfaceCard {
            subLevelControl
            Divider()
            speechEnhancementControl
            Divider()
            nightSoundControl
        }
    }

    @ViewBuilder
    private var subLevelControl: some View {
        if settings.supportsSubLevel {
            HomeTheaterSliderRow(
                title: "Sub Level",
                systemImage: "speaker.fill",
                value: $subLevel,
                range: SonosHomeTheaterSettings.subLevelRange,
                valueText: homeTheaterSignedValueText(Int(subLevel.rounded())),
                isEnabled: isEnabled,
                editingChanged: subEditingChanged
            )
        } else {
            HomeTheaterUnavailableRow(
                title: "Sub Level",
                detail: "Unavailable",
                systemImage: "speaker.slash.fill"
            )
        }
    }

    @ViewBuilder
    private var speechEnhancementControl: some View {
        if settings.supportsSpeechEnhancement {
            Toggle(
                isOn: Binding(
                    get: {
                        settings.speechEnhancementEnabled == true
                    },
                    set: { isEnabled in
                        setSpeechEnhancement(isEnabled)
                    }
                )
            ) {
                Label("Speech Enhancement", systemImage: "quote.bubble.fill")
            }
            .font(.subheadline.weight(.medium))
            .disabled(!isEnabled)

            if settings.supportsDialogLevel {
                HomeTheaterDialogLevelPicker(
                    level: Binding(
                        get: {
                            settings.dialogLevel ?? 2
                        },
                        set: { level in
                            setDialogLevel(level)
                        }
                    ),
                    isEnabled: isEnabled && settings.speechEnhancementEnabled == true
                )
            }
        } else {
            HomeTheaterUnavailableRow(
                title: "Speech Enhancement",
                detail: "Unavailable",
                systemImage: "quote.bubble"
            )
        }
    }

    @ViewBuilder
    private var nightSoundControl: some View {
        if settings.supportsNightSound {
            Toggle(
                isOn: Binding(
                    get: {
                        settings.nightSoundEnabled == true
                    },
                    set: { isEnabled in
                        setNightSound(isEnabled)
                    }
                )
            ) {
                Label("Night Sound", systemImage: "moon.fill")
            }
            .font(.subheadline.weight(.medium))
            .disabled(!isEnabled)
        } else {
            HomeTheaterUnavailableRow(
                title: "Night Sound",
                detail: "Unavailable",
                systemImage: "moon"
            )
        }
    }
}
