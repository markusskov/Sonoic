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

struct SettingsSonosMusicServiceProbeSection: View {
    let model: SonoicModel
    let refreshTimingText: (Date?) -> String

    var body: some View {
        Section("Sonos Services") {
            SettingsStatusRow(
                title: "Service Probe",
                statusTitle: statusTitle,
                detail: statusDetail,
                systemImage: systemImage,
                tint: tint
            )

            if let snapshot = model.sonosMusicServiceProbeState.snapshot {
                LabeledContent("Observed At", value: refreshTimingText(snapshot.observedAt))

                if let serviceListVersion = snapshot.serviceListVersion {
                    LabeledContent("List Version", value: serviceListVersion)
                }

                ForEach(snapshot.knownServiceRows) { row in
                    SettingsSonosMusicServiceProbeRow(row: row)
                }
            }

            Button(action: refreshProbe) {
                if model.sonosMusicServiceProbeState.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Refreshing")
                    }
                } else {
                    Label("Refresh Services", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.sonosMusicServiceProbeState.isLoading)
        }
    }

    private var statusTitle: String {
        switch model.sonosMusicServiceProbeState.status {
        case .idle:
            "Not Refreshed"
        case .loading:
            "Refreshing"
        case .loaded:
            "Loaded"
        case .failed:
            "Failed"
        }
    }

    private var statusDetail: String? {
        switch model.sonosMusicServiceProbeState.status {
        case .idle:
            "Reads Sonos music services and accounts."
        case .loading:
            "Reading local Sonos service setup."
        case .loaded:
            nil
        case .failed(let detail):
            detail
        }
    }

    private var systemImage: String {
        switch model.sonosMusicServiceProbeState.status {
        case .idle:
            "network"
        case .loading:
            "arrow.clockwise"
        case .loaded:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch model.sonosMusicServiceProbeState.status {
        case .idle:
            .secondary
        case .loading:
            .orange
        case .loaded:
            .green
        case .failed:
            .red
        }
    }

    private func refreshProbe() {
        Task {
            await model.refreshSonosMusicServiceProbe()
        }
    }
}

private struct SettingsSonosMusicServiceProbeRow: View {
    let row: SonosMusicServiceProbeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(row.service.name, systemImage: row.service.systemImage)
                Spacer()
                Text(row.statusTitle)
                    .foregroundStyle(statusTint)
            }

            Text(row.detailText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let sonosService = row.sonosService {
                if let authPolicy = sonosService.authPolicy {
                    Text("Auth \(authPolicy)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let secureURI = sonosService.secureURI {
                    Text(secureURI)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            ForEach(row.accounts) { account in
                Text(account.redactedDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusTint: Color {
        guard row.sonosService != nil else {
            return .secondary
        }

        return row.accounts.isEmpty ? .orange : .green
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
