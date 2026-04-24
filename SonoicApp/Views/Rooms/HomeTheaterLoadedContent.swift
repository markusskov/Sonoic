import SwiftUI

struct HomeTheaterLoadedContent: View {
    let settings: SonosHomeTheaterSettings
    let activeTargetName: String
    let isControlEnabled: Bool
    let isTVAudioActive: Bool
    let tvDiagnosticsSubtitle: String
    let nowPlaying: SonosNowPlayingSnapshot
    let nowPlayingDiagnostics: SonosNowPlayingDiagnostics
    let tvDiagnostics: SonosHomeTheaterTVDiagnostics
    @Binding var bassLevel: Double
    @Binding var trebleLevel: Double
    @Binding var subLevel: Double
    let bassEditingChanged: (Bool) -> Void
    let trebleEditingChanged: (Bool) -> Void
    let subEditingChanged: (Bool) -> Void
    let setLoudness: (Bool) -> Void
    let setSpeechEnhancement: (Bool) -> Void
    let setDialogLevel: (Int) -> Void
    let setNightSound: (Bool) -> Void

    var body: some View {
        RoomsSectionHeader(
            title: "EQ",
            subtitle: "\(activeTargetName) tone and loudness."
        )

        HomeTheaterEQCard(
            settings: settings,
            bassLevel: $bassLevel,
            trebleLevel: $trebleLevel,
            isEnabled: isControlEnabled,
            bassEditingChanged: bassEditingChanged,
            trebleEditingChanged: trebleEditingChanged,
            setLoudness: setLoudness
        )

        RoomsSectionHeader(
            title: "Cinema",
            subtitle: "Sub, speech, and night listening controls."
        )

        HomeTheaterCinemaCard(
            settings: settings,
            subLevel: $subLevel,
            isEnabled: isControlEnabled,
            subEditingChanged: subEditingChanged,
            setSpeechEnhancement: setSpeechEnhancement,
            setDialogLevel: setDialogLevel,
            setNightSound: setNightSound
        )

        RoomsSectionHeader(
            title: "TV Diagnostics",
            subtitle: tvDiagnosticsSubtitle
        )

        HomeTheaterTVDiagnosticsCard(
            isTVAudioActive: isTVAudioActive,
            nowPlaying: nowPlaying,
            nowPlayingDiagnostics: nowPlayingDiagnostics,
            tvDiagnostics: tvDiagnostics
        )
    }
}
