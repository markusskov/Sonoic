import Foundation

extension SonoicModel {
    var homeTheaterRefreshContext: String {
        [
            manualSonosHost,
            activeTarget.id,
            activeTarget.name,
        ]
        .joined(separator: "|")
    }

    func refreshHomeTheater(showLoading: Bool = true) async {
        guard hasManualSonosHost else {
            homeTheaterState = .idle
            homeTheaterTVDiagnostics = .empty
            isHomeTheaterRefreshing = false
            return
        }

        guard !isHomeTheaterRefreshing else {
            return
        }

        isHomeTheaterRefreshing = true
        defer {
            isHomeTheaterRefreshing = false
        }

        if showLoading {
            homeTheaterState = .loading
        }

        do {
            async let settings = renderingControlClient.fetchHomeTheaterSettings(host: manualSonosHost)
            async let diagnostics = htControlClient.fetchTVDiagnostics(host: manualSonosHost)
            let resolvedSettings = try await settings
            homeTheaterState = .loaded(resolvedSettings)
            homeTheaterTVDiagnostics = await diagnostics
        } catch {
            homeTheaterState = .failed(error.localizedDescription)
            homeTheaterTVDiagnostics = await htControlClient.fetchTVDiagnostics(host: manualSonosHost)
        }
    }

    func setHomeTheaterBass(to level: Int) async -> Bool {
        await performHomeTheaterMutation { settings in
            settings.bass = Self.boundedHomeTheaterValue(level, in: SonosHomeTheaterSettings.toneRange)
        } action: { host in
            try await renderingControlClient.setBass(host: host, level: level)
        }
    }

    func setHomeTheaterTreble(to level: Int) async -> Bool {
        await performHomeTheaterMutation { settings in
            settings.treble = Self.boundedHomeTheaterValue(level, in: SonosHomeTheaterSettings.toneRange)
        } action: { host in
            try await renderingControlClient.setTreble(host: host, level: level)
        }
    }

    func setHomeTheaterLoudness(_ isEnabled: Bool) async -> Bool {
        await performHomeTheaterMutation { settings in
            settings.loudness = isEnabled
        } action: { host in
            try await renderingControlClient.setLoudness(host: host, isEnabled: isEnabled)
        }
    }

    func setHomeTheaterSubLevel(to level: Int) async -> Bool {
        await performHomeTheaterMutation { settings in
            settings.subLevel = Self.boundedHomeTheaterValue(level, in: SonosHomeTheaterSettings.subLevelRange)
        } action: { host in
            try await renderingControlClient.setSubLevel(host: host, level: level)
        }
    }

    func setHomeTheaterSpeechEnhancement(_ isEnabled: Bool) async -> Bool {
        await performHomeTheaterMutation { settings in
            settings.speechEnhancementEnabled = isEnabled
        } action: { host in
            try await renderingControlClient.setSpeechEnhancement(host: host, isEnabled: isEnabled)
        }
    }

    func setHomeTheaterDialogLevel(to level: Int) async -> Bool {
        await performHomeTheaterMutation { settings in
            settings.dialogLevel = Self.boundedHomeTheaterValue(level, in: SonosHomeTheaterSettings.dialogLevelRange)
        } action: { host in
            try await renderingControlClient.setDialogLevel(host: host, level: level)
        }
    }

    func setHomeTheaterNightSound(_ isEnabled: Bool) async -> Bool {
        await performHomeTheaterMutation { settings in
            settings.nightSoundEnabled = isEnabled
        } action: { host in
            try await renderingControlClient.setNightSound(host: host, isEnabled: isEnabled)
        }
    }

    func refreshHomeTheaterDiagnostics() async {
        guard hasManualSonosHost else {
            homeTheaterTVDiagnostics = .empty
            return
        }

        homeTheaterTVDiagnostics = await htControlClient.fetchTVDiagnostics(host: manualSonosHost)
    }

    private func performHomeTheaterMutation(
        optimisticUpdate: (inout SonosHomeTheaterSettings) -> Void,
        action: (String) async throws -> Void
    ) async -> Bool {
        guard hasManualSonosHost,
              !isHomeTheaterRefreshing,
              !isHomeTheaterMutating,
              var settings = homeTheaterState.settings
        else {
            return false
        }

        let previousState = homeTheaterState
        homeTheaterOperationErrorDetail = nil
        optimisticUpdate(&settings)
        homeTheaterState = .loaded(settings)
        isHomeTheaterMutating = true
        defer {
            isHomeTheaterMutating = false
        }

        do {
            try await action(manualSonosHost)
            return true
        } catch {
            homeTheaterState = previousState
            homeTheaterOperationErrorDetail = error.localizedDescription
            return false
        }
    }

    private static func boundedHomeTheaterValue(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
