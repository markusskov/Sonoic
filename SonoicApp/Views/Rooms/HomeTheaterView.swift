import SwiftUI

struct HomeTheaterView: View {
    @Environment(SonoicModel.self) private var model
    @State private var bassLevel = 0.0
    @State private var trebleLevel = 0.0
    @State private var subLevel = 0.0
    @State private var isAdjustingBass = false
    @State private var isAdjustingTreble = false
    @State private var isAdjustingSub = false

    var body: some View {
        content
            .miniPlayerContentInset()
            .scrollIndicators(.hidden)
            .navigationTitle("Home Theater")
            .toolbar {
                if model.hasManualSonosHost {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await refreshHomeTheater(showLoading: false)
                            }
                        } label: {
                            if model.isHomeTheaterRefreshing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(model.isHomeTheaterRefreshing || model.isHomeTheaterMutating)
                        .accessibilityLabel("Refresh Home Theater")
                    }
                }
            }
            .alert(
                "Couldn't Update Home Theater",
                isPresented: Binding(
                    get: {
                        model.homeTheaterOperationErrorDetail != nil
                    },
                    set: { isPresented in
                        if !isPresented {
                            model.homeTheaterOperationErrorDetail = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.homeTheaterOperationErrorDetail ?? "")
            }
            .task(id: model.homeTheaterRefreshContext) {
                await loadHomeTheaterIfNeeded()
            }
            .onChange(of: model.homeTheaterState.settings, initial: true) { _, settings in
                syncLocalLevels(from: settings)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasManualSonosHost {
            ContentUnavailableView {
                Label("No Room Selected", systemImage: "speaker.slash.fill")
            } description: {
                Text("Choose a discovered Sonos room before tuning home theater controls.")
            } actions: {
                Button("Open Rooms") {
                    model.selectedTab = .rooms
                }
            }
        } else {
            ScrollView {
                GlassEffectContainer(spacing: 18) {
                    VStack(alignment: .leading, spacing: 28) {
                        switch model.homeTheaterState {
                        case .idle, .loading:
                            HomeTheaterLoadingCard(isRefreshing: model.isHomeTheaterRefreshing)
                        case let .failed(detail):
                            HomeTheaterFailureCard(detail: detail) {
                                await refreshHomeTheater(showLoading: true)
                            }
                        case let .loaded(settings):
                            loadedContent(settings)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    @ViewBuilder
    private func loadedContent(_ settings: SonosHomeTheaterSettings) -> some View {
        RoomsSectionHeader(
            title: "EQ",
            subtitle: "\(model.activeTarget.name) tone and loudness."
        )

        HomeTheaterEQCard(
            settings: settings,
            bassLevel: $bassLevel,
            trebleLevel: $trebleLevel,
            isEnabled: isControlEnabled,
            bassEditingChanged: handleBassEditingChanged,
            trebleEditingChanged: handleTrebleEditingChanged,
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
            subEditingChanged: handleSubEditingChanged,
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
            nowPlaying: model.nowPlaying,
            nowPlayingDiagnostics: model.nowPlayingDiagnostics,
            tvDiagnostics: model.homeTheaterTVDiagnostics
        )
    }

    private var isControlEnabled: Bool {
        !model.isHomeTheaterRefreshing && !model.isHomeTheaterMutating
    }

    private var tvDiagnosticsSubtitle: String {
        isTVAudioActive ? "Sonoic sees active TV audio on this room." : "Current transport and TV-control state."
    }

    private var isTVAudioActive: Bool {
        if model.nowPlaying.sourceName == "TV Audio" {
            return true
        }

        return isTVAudioURI(model.nowPlayingDiagnostics.currentURI)
            || isTVAudioURI(model.nowPlayingDiagnostics.trackURI)
    }

    private func isTVAudioURI(_ uri: String?) -> Bool {
        uri.sonoicNonEmptyTrimmed?.lowercased().hasPrefix("x-sonos-htastream:") == true
    }

    private func loadHomeTheaterIfNeeded() async {
        guard model.hasManualSonosHost else {
            return
        }

        guard model.homeTheaterState.settings == nil else {
            await model.refreshHomeTheaterDiagnostics()
            return
        }

        await model.refreshHomeTheater(showLoading: true)
    }

    private func refreshHomeTheater(showLoading: Bool) async {
        await model.refreshHomeTheater(showLoading: showLoading)
        await model.refreshManualSonosPlayerState(forceRoomRefresh: false)
    }

    private func syncLocalLevels(from settings: SonosHomeTheaterSettings?) {
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

    private func handleBassEditingChanged(_ isEditing: Bool) {
        isAdjustingBass = isEditing
        guard !isEditing else {
            return
        }

        let level = Int(bassLevel.rounded())
        Task {
            _ = await model.setHomeTheaterBass(to: level)
        }
    }

    private func handleTrebleEditingChanged(_ isEditing: Bool) {
        isAdjustingTreble = isEditing
        guard !isEditing else {
            return
        }

        let level = Int(trebleLevel.rounded())
        Task {
            _ = await model.setHomeTheaterTreble(to: level)
        }
    }

    private func handleSubEditingChanged(_ isEditing: Bool) {
        isAdjustingSub = isEditing
        guard !isEditing else {
            return
        }

        let level = Int(subLevel.rounded())
        Task {
            _ = await model.setHomeTheaterSubLevel(to: level)
        }
    }

    private func setLoudness(_ isEnabled: Bool) {
        Task {
            _ = await model.setHomeTheaterLoudness(isEnabled)
        }
    }

    private func setSpeechEnhancement(_ isEnabled: Bool) {
        Task {
            _ = await model.setHomeTheaterSpeechEnhancement(isEnabled)
        }
    }

    private func setDialogLevel(_ level: Int) {
        Task {
            _ = await model.setHomeTheaterDialogLevel(to: level)
        }
    }

    private func setNightSound(_ isEnabled: Bool) {
        Task {
            _ = await model.setHomeTheaterNightSound(isEnabled)
        }
    }
}

private struct HomeTheaterLoadingCard: View {
    let isRefreshing: Bool

    var body: some View {
        RoomSurfaceCard {
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 6) {
                    Text(isRefreshing ? "Loading Home Theater" : "Home Theater")
                        .font(.headline)

                    Text("Reading EQ, cinema controls, and TV-control state from the selected room.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct HomeTheaterFailureCard: View {
    let detail: String
    let retry: () async -> Void

    var body: some View {
        RoomSurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn't Load Home Theater")
                        .font(.headline)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Try Again", systemImage: "arrow.clockwise") {
                Task {
                    await retry()
                }
            }
            .buttonStyle(.glass)
        }
    }
}

private struct HomeTheaterEQCard: View {
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
                valueText: signedValueText(Int(bassLevel.rounded())),
                isEnabled: isEnabled,
                editingChanged: bassEditingChanged
            )

            Divider()

            HomeTheaterSliderRow(
                title: "Treble",
                systemImage: "waveform",
                value: $trebleLevel,
                range: SonosHomeTheaterSettings.toneRange,
                valueText: signedValueText(Int(trebleLevel.rounded())),
                isEnabled: isEnabled,
                editingChanged: trebleEditingChanged
            )

            Divider()

            Toggle(
                isOn: Binding(
                    get: {
                        settings.loudness
                    },
                    set: setLoudness
                )
            ) {
                Label("Loudness", systemImage: "speaker.wave.3.fill")
            }
            .font(.subheadline.weight(.medium))
            .disabled(!isEnabled)
        }
    }
}

private struct HomeTheaterCinemaCard: View {
    let settings: SonosHomeTheaterSettings
    @Binding var subLevel: Double
    let isEnabled: Bool
    let subEditingChanged: (Bool) -> Void
    let setSpeechEnhancement: (Bool) -> Void
    let setDialogLevel: (Int) -> Void
    let setNightSound: (Bool) -> Void

    var body: some View {
        RoomSurfaceCard {
            if settings.supportsSubLevel {
                HomeTheaterSliderRow(
                    title: "Sub Level",
                    systemImage: "speaker.fill",
                    value: $subLevel,
                    range: SonosHomeTheaterSettings.subLevelRange,
                    valueText: signedValueText(Int(subLevel.rounded())),
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

            Divider()

            if settings.supportsSpeechEnhancement {
                Toggle(
                    isOn: Binding(
                        get: {
                            settings.speechEnhancementEnabled == true
                        },
                        set: setSpeechEnhancement
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
                            set: setDialogLevel
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

            Divider()

            if settings.supportsNightSound {
                Toggle(
                    isOn: Binding(
                        get: {
                            settings.nightSoundEnabled == true
                        },
                        set: setNightSound
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
}

private struct HomeTheaterSliderRow: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Int>
    let valueText: String
    let isEnabled: Bool
    let editingChanged: (Bool) -> Void

    private var doubleRange: ClosedRange<Double> {
        Double(range.lowerBound) ... Double(range.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.medium))

                Spacer(minLength: 12)

                Text(valueText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("\(range.lowerBound)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .leading)

                Slider(
                    value: $value,
                    in: doubleRange,
                    step: 1,
                    onEditingChanged: editingChanged
                )
                .disabled(!isEnabled)

                Text("+\(range.upperBound)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }
}

private struct HomeTheaterDialogLevelPicker: View {
    @Binding var level: Int
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Speech Level", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Speech Level", selection: $level) {
                Text("Low").tag(1)
                Text("Med").tag(2)
                Text("High").tag(3)
                Text("Max").tag(4)
            }
            .pickerStyle(.segmented)
            .disabled(!isEnabled)
        }
        .padding(.top, 4)
    }
}

private struct HomeTheaterUnavailableRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 12)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct HomeTheaterTVDiagnosticsCard: View {
    let isTVAudioActive: Bool
    let nowPlaying: SonosNowPlayingSnapshot
    let nowPlayingDiagnostics: SonosNowPlayingDiagnostics
    let tvDiagnostics: SonosHomeTheaterTVDiagnostics

    var body: some View {
        RoomSurfaceCard {
            HomeTheaterDiagnosticRow(
                title: "TV Audio",
                value: isTVAudioActive ? "Active" : "Inactive",
                systemImage: isTVAudioActive ? "tv.fill" : "tv"
            )

            Divider()

            HomeTheaterDiagnosticRow(
                title: "Source",
                value: nowPlaying.sourceName,
                systemImage: "music.note.list"
            )

            HomeTheaterDiagnosticRow(
                title: "Playback",
                value: nowPlaying.playbackState.title,
                systemImage: nowPlaying.playbackState.systemImage
            )

            if let currentURI = nowPlayingDiagnostics.currentURI {
                Divider()

                HomeTheaterDiagnosticRow(
                    title: "Current URI",
                    value: currentURI,
                    systemImage: "link",
                    isMonospaced: true
                )
            }

            if let trackURI = nowPlayingDiagnostics.trackURI,
               trackURI != nowPlayingDiagnostics.currentURI
            {
                HomeTheaterDiagnosticRow(
                    title: "Track URI",
                    value: trackURI,
                    systemImage: "link.badge.plus",
                    isMonospaced: true
                )
            }

            Divider()

            HomeTheaterDiagnosticRow(
                title: "Remote",
                value: boolText(tvDiagnostics.remoteConfigured),
                systemImage: "button.programmable"
            )

            HomeTheaterDiagnosticRow(
                title: "IR Repeater",
                value: tvDiagnostics.irRepeaterState ?? "Unavailable",
                systemImage: "dot.radiowaves.left.and.right"
            )

            HomeTheaterDiagnosticRow(
                title: "LED Feedback",
                value: tvDiagnostics.ledFeedbackState ?? "Unavailable",
                systemImage: "lightbulb"
            )
        }
    }
}

private struct HomeTheaterDiagnosticRow: View {
    let title: String
    let value: String
    let systemImage: String
    var isMonospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(isMonospaced ? .caption.monospaced() : .subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(isMonospaced ? 3 : 2)
                .minimumScaleFactor(0.82)
                .textSelection(.enabled)
        }
    }
}

private func signedValueText(_ value: Int) -> String {
    value > 0 ? "+\(value)" : "\(value)"
}

private func boolText(_ value: Bool?) -> String {
    guard let value else {
        return "Unavailable"
    }

    return value ? "Yes" : "No"
}

#Preview {
    NavigationStack {
        HomeTheaterView()
            .environment(SonoicModel())
    }
}
