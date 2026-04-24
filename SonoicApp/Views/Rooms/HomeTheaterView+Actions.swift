import SwiftUI

extension HomeTheaterView {
    @ViewBuilder
    func loadedContent(_ settings: SonosHomeTheaterSettings) -> some View {
        HomeTheaterLoadedContent(
            settings: settings,
            activeTargetName: model.activeTarget.name,
            isControlEnabled: isControlEnabled,
            isTVAudioActive: isTVAudioActive,
            tvDiagnosticsSubtitle: tvDiagnosticsSubtitle,
            nowPlaying: model.nowPlaying,
            nowPlayingDiagnostics: model.nowPlayingDiagnostics,
            tvDiagnostics: model.homeTheaterTVDiagnostics,
            bassLevel: $bassLevel,
            trebleLevel: $trebleLevel,
            subLevel: $subLevel,
            bassEditingChanged: handleBassEditingChanged,
            trebleEditingChanged: handleTrebleEditingChanged,
            subEditingChanged: handleSubEditingChanged,
            setLoudness: setLoudness,
            setSpeechEnhancement: setSpeechEnhancement,
            setDialogLevel: setDialogLevel,
            setNightSound: setNightSound
        )
    }

    var isControlEnabled: Bool {
        !model.isHomeTheaterRefreshing && !model.isHomeTheaterMutating
    }

    var tvDiagnosticsSubtitle: String {
        isTVAudioActive ? "Sonoic sees active TV audio on this room." : "Current transport and TV-control state."
    }

    var isTVAudioActive: Bool {
        if model.nowPlaying.sourceName == "TV Audio" {
            return true
        }

        return isTVAudioURI(model.nowPlayingDiagnostics.currentURI)
            || isTVAudioURI(model.nowPlayingDiagnostics.trackURI)
    }

    func isTVAudioURI(_ uri: String?) -> Bool {
        uri.sonoicNonEmptyTrimmed?.lowercased().hasPrefix("x-sonos-htastream:") == true
    }

    func loadHomeTheaterIfNeeded() async {
        guard model.hasManualSonosHost else {
            return
        }

        guard model.homeTheaterState.settings == nil else {
            await model.refreshHomeTheaterDiagnostics()
            return
        }

        await model.refreshHomeTheater(showLoading: true)
    }

    func refreshHomeTheater(showLoading: Bool) async {
        await model.refreshHomeTheater(showLoading: showLoading)
        await model.refreshManualSonosPlayerState(forceRoomRefresh: false)
    }

    func syncLocalLevels(from settings: SonosHomeTheaterSettings?) {
        guard let settings else {
            return
        }

        if !isAdjustingBass {
            bassLevel = Double(settings.bass)
        }

        if !isAdjustingTreble {
            trebleLevel = Double(settings.treble)
        }

        if !isAdjustingSub, let settingsSubLevel = settings.subLevel {
            subLevel = Double(settingsSubLevel)
        }
    }

    func handleBassEditingChanged(_ isEditing: Bool) {
        isAdjustingBass = isEditing
        guard !isEditing else {
            return
        }

        setHomeTheaterLevel(bassLevel) { level in
            await model.setHomeTheaterBass(to: level)
        }
    }

    func handleTrebleEditingChanged(_ isEditing: Bool) {
        isAdjustingTreble = isEditing
        guard !isEditing else {
            return
        }

        setHomeTheaterLevel(trebleLevel) { level in
            await model.setHomeTheaterTreble(to: level)
        }
    }

    func handleSubEditingChanged(_ isEditing: Bool) {
        isAdjustingSub = isEditing
        guard !isEditing else {
            return
        }

        setHomeTheaterLevel(subLevel) { level in
            await model.setHomeTheaterSubLevel(to: level)
        }
    }

    func setLoudness(_ isEnabled: Bool) {
        performHomeTheaterMutation {
            await model.setHomeTheaterLoudness(isEnabled)
        }
    }

    func setSpeechEnhancement(_ isEnabled: Bool) {
        performHomeTheaterMutation {
            await model.setHomeTheaterSpeechEnhancement(isEnabled)
        }
    }

    func setDialogLevel(_ level: Int) {
        performHomeTheaterMutation {
            await model.setHomeTheaterDialogLevel(to: level)
        }
    }

    func setNightSound(_ isEnabled: Bool) {
        performHomeTheaterMutation {
            await model.setHomeTheaterNightSound(isEnabled)
        }
    }

    private func setHomeTheaterLevel(
        _ rawLevel: Double,
        action: @escaping (Int) async -> Bool
    ) {
        let level = Int(rawLevel.rounded())
        performHomeTheaterMutation {
            await action(level)
        }
    }

    private func performHomeTheaterMutation(_ action: @escaping () async -> Bool) {
        Task {
            _ = await action()
        }
    }
}
