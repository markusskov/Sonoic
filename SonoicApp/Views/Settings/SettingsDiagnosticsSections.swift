import SwiftUI

struct SettingsRefreshTimingSection: View {
    let model: SonoicModel
    let refreshTimingText: (Date?) -> String

    var body: some View {
        Section {
            LabeledContent("Player State", value: refreshTimingText(model.manualHostLastSuccessfulRefreshAt))
            LabeledContent("Room Name", value: refreshTimingText(model.manualHostIdentityLastRefreshAt))
            LabeledContent("Bonded Setup", value: refreshTimingText(model.manualHostTopologyLastRefreshAt))
        } header: {
            Text("Refresh Timing")
        } footer: {
            Text("Tiny timing surface for manual verification of refresh, failure, and retry behavior.")
        }
    }
}

struct SettingsPlaybackDiagnosticsSection: View {
    let model: SonoicModel

    var body: some View {
        Section("Diagnostics") {
            LabeledContent("Selected Host", value: model.manualSonosHost)
            LabeledContent("Current Room", value: model.activeTarget.name)
            LabeledContent("Title", value: model.nowPlaying.title)

            if let artistName = model.nowPlaying.artistName {
                LabeledContent("Artist", value: artistName)
            }

            LabeledContent("Source", value: model.nowPlaying.sourceName)
            LabeledContent("Playback", value: model.nowPlaying.playbackState.title)
            LabeledContent("Current Volume", value: model.externalVolume.labelText)
            LabeledContent("Mute", value: model.externalVolume.isMuted ? "On" : "Off")
        }
    }
}

struct SettingsNowPlayingDiagnosticsSection: View {
    let model: SonoicModel
    let refreshTimingText: (Date?) -> String

    var body: some View {
        Section("Now Playing Diagnostics") {
            LabeledContent("Observed At", value: refreshTimingText(model.nowPlayingObservedAt))
            LabeledContent(
                "Awaiting Confirmation",
                value: model.isManualPlayTransitionAwaitingConfirmation ? "Yes" : "No"
            )
            LabeledContent(
                "Used Fallback Snapshot",
                value: model.nowPlayingDiagnostics.usedFallbackSnapshot ? "Yes" : "No"
            )
            LabeledContent(
                "Track Metadata",
                value: model.nowPlayingDiagnostics.hasTrackMetadata ? "Present" : "Missing"
            )
            LabeledContent(
                "Source Metadata",
                value: model.nowPlayingDiagnostics.hasSourceMetadata ? "Present" : "Missing"
            )
            SettingsDiagnosticRow(
                title: "Current URI",
                value: model.nowPlayingDiagnostics.currentURI ?? "Unavailable"
            )
            SettingsDiagnosticRow(
                title: "Track URI",
                value: model.nowPlayingDiagnostics.trackURI ?? "Unavailable"
            )
            LabeledContent(
                "Raw Elapsed",
                value: model.nowPlayingDiagnostics.rawElapsedTime ?? "Unavailable"
            )
            LabeledContent(
                "Raw Duration",
                value: model.nowPlayingDiagnostics.rawDuration ?? "Unavailable"
            )
        }
    }
}

struct SettingsEmptySelectionSection: View {
    var body: some View {
        Section("Selection") {
            Label(
                "Choose one of your discovered Sonos rooms to start diagnostics and direct playback control.",
                systemImage: "info.circle"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
