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
        let currentURIOwnership = model.nowPlayingDiagnostics.currentURIOwnership

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
            LabeledContent(
                "Current URI Kind",
                value: currentURIOwnership.title
            )
            LabeledContent(
                "Queue Editable",
                value: currentURIOwnership.supportsLocalQueueMutation ? "Yes" : "No"
            )
            LabeledContent(
                "Transport Actions",
                value: model.nowPlaying.transportActions?.diagnosticText ?? "Unavailable"
            )
            SettingsDiagnosticRow(
                title: "Current URI Detail",
                value: currentURIOwnership.diagnosticDetail
            )
            SettingsDiagnosticRow(
                title: "Track URI",
                value: model.nowPlayingDiagnostics.trackURI ?? "Unavailable"
            )
            LabeledContent(
                "Track URI Kind",
                value: model.nowPlayingDiagnostics.trackURIOwnership.title
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

        Section("Seek Diagnostics") {
            LabeledContent("Status", value: model.seekDiagnostics.status.title)
            LabeledContent("Requested At", value: refreshTimingText(model.seekDiagnostics.requestedAt))
            LabeledContent("Host", value: model.seekDiagnostics.host ?? "Unavailable")
            LabeledContent("Target", value: seekTimeText(model.seekDiagnostics.target))
            LabeledContent("Observed", value: seekTimeText(model.seekDiagnostics.observed))

            if let errorDetail = model.seekDiagnostics.errorDetail {
                SettingsDiagnosticRow(title: "Error", value: errorDetail)
            }
        }
    }

    private func seekTimeText(_ timeInterval: TimeInterval?) -> String {
        guard let timeInterval else {
            return "Unavailable"
        }

        let totalSeconds = max(0, Int(timeInterval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SettingsQueueDiagnosticsSection: View {
    let model: SonoicModel
    let refreshTimingText: (Date?) -> String

    var body: some View {
        let ownership = model.queueDiagnostics.currentURIOwnership

        Section("Queue Diagnostics") {
            LabeledContent("Observed At", value: refreshTimingText(model.queueDiagnostics.observedAt))
            LabeledContent("Current URI Kind", value: ownership.title)
            LabeledContent("Queue Editable", value: ownership.supportsLocalQueueMutation ? "Yes" : "No")

            if let itemCount = model.queueDiagnostics.itemCount {
                LabeledContent("Items", value: itemCount.formatted())
            }

            SettingsDiagnosticRow(
                title: "Current URI",
                value: model.queueDiagnostics.currentURI ?? "Unavailable"
            )

            if let refreshError = model.queueDiagnostics.lastRefreshErrorDetail {
                SettingsDiagnosticRow(title: "Last Refresh Error", value: refreshError)
            }

            if let mutationError = model.queueDiagnostics.lastMutationErrorDetail {
                SettingsDiagnosticRow(title: "Last Mutation Error", value: mutationError)
            }
        }
    }
}

struct SettingsEmptySelectionSection: View {
    var body: some View {
        Section("Selection") {
            Label(
                "Choose a room to start.",
                systemImage: "info.circle"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
