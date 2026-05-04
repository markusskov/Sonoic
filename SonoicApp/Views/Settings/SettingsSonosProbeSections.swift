import SwiftUI

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

struct SettingsSonosContentDirectoryProbeSection: View {
    let model: SonoicModel
    let refreshTimingText: (Date?) -> String

    var body: some View {
        Section("Sonos Content") {
            SettingsStatusRow(
                title: "Content Probe",
                statusTitle: statusTitle,
                detail: statusDetail,
                systemImage: systemImage,
                tint: tint
            )

            if let snapshot = model.sonosContentDirectoryProbeState.snapshot {
                LabeledContent("Observed At", value: refreshTimingText(snapshot.observedAt))

                if !snapshot.discoveredRecentCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent Candidates")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(snapshot.discoveredRecentCandidates) { entry in
                            Text("\(entry.title) · \(entry.id)")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(snapshot.browses) { browse in
                    SettingsSonosContentDirectoryBrowseRow(browse: browse)
                }
            }

            Button(action: refreshProbe) {
                if model.sonosContentDirectoryProbeState.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Refreshing")
                    }
                } else {
                    Label("Refresh Content", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.sonosContentDirectoryProbeState.isLoading)
        }
    }

    private var statusTitle: String {
        switch model.sonosContentDirectoryProbeState.status {
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
        switch model.sonosContentDirectoryProbeState.status {
        case .idle:
            "Browses Sonos content containers."
        case .loading:
            "Reading local Sonos content."
        case .loaded:
            nil
        case .failed(let detail):
            detail
        }
    }

    private var systemImage: String {
        switch model.sonosContentDirectoryProbeState.status {
        case .idle:
            "folder"
        case .loading:
            "arrow.clockwise"
        case .loaded:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch model.sonosContentDirectoryProbeState.status {
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
            await model.refreshSonosContentDirectoryProbe()
        }
    }
}

private struct SettingsSonosContentDirectoryBrowseRow: View {
    let browse: SonosContentDirectoryProbeBrowse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(browse.title)
                        .font(.body.weight(.medium))

                    Text(browse.objectID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(browse.countText)
                    .foregroundStyle(statusTint)
            }

            if case .failed(let detail) = browse.status {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(browse.entries.prefix(8)) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)

                    Text(entry.detailText)
                        .font(.caption)
                        .foregroundStyle(entry.looksLikeRecentlyPlayedContainer ? .orange : .secondary)
                        .lineLimit(2)
                }
                .padding(.leading, 8)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusTint: Color {
        switch browse.status {
        case .loaded:
            .green
        case .empty:
            .secondary
        case .failed:
            .orange
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
                    .foregroundStyle(accountTint(account))
            }

            if let playbackHint = row.playbackHint {
                SettingsSonosMusicServicePlaybackHintView(playbackHint: playbackHint)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusTint: Color {
        guard row.sonosService != nil else {
            return .secondary
        }

        if row.accounts.isEmpty {
            return .orange
        }

        return row.accounts.contains(where: \.hasStatusAccount) ? .green : .orange
    }

    private func accountTint(_ account: SonosMusicServiceAccountSummary) -> Color {
        account.hasStatusAccount ? .secondary : .orange
    }
}

private struct SettingsSonosMusicServicePlaybackHintView: View {
    let playbackHint: SonosMusicServicePlaybackHint

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let launchText = playbackHint.launchText {
                Text(launchText)
            }

            if let trackText = playbackHint.trackText {
                Text(trackText)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }
}
