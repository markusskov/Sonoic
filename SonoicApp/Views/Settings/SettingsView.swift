import SwiftUI

struct SettingsView: View {
    @Environment(SonoicModel.self) private var model

    var body: some View {
        Form {
            Section {
                SettingsStatusRow(
                    title: "Discovery",
                    statusTitle: model.roomDiscoveryStatus.title,
                    detail: discoveryStatusDetail,
                    systemImage: model.roomDiscoveryStatus.systemImage,
                    tint: discoveryStatusTint
                )

                Button {
                    model.refreshSonosDiscovery()
                } label: {
                    if model.isSonosDiscoveryRefreshing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Refreshing Discovery")
                        }
                    } else {
                        Label("Refresh Discovery", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isSonosDiscoveryRefreshing)

                if model.hasManualSonosHost {
                    Button(role: .destructive) {
                        model.clearSelectedPlayer()
                    } label: {
                        Label("Clear Selected Player", systemImage: "xmark.circle")
                    }
                }
            } header: {
                Text("Sonos Household")
            } footer: {
                Text("Sonoic discovers nearby Sonos speakers automatically and uses your selected room for queue, favorites, now-playing, and lock-screen controls.")
            }

            if model.hasDiscoveredPlayers {
                Section("Choose Player") {
                    ForEach(model.discoveredPlayers) { player in
                        SettingsDiscoveredPlayerRow(
                            player: player,
                            isSelected: model.isDiscoveredPlayerSelected(player),
                            isSelecting: model.selectingDiscoveredPlayerID == player.id,
                            selectPlayer: {
                                await model.selectDiscoveredPlayer(player)
                            }
                        )
                    }
                }
            }

            if model.hasManualSonosHost {
                Section {
                    LabeledContent("Selected Room", value: model.activeTarget.name)

                    if let selectedDiscoveredPlayer = model.selectedDiscoveredPlayer {
                        LabeledContent("Model", value: selectedDiscoveredPlayer.detailText)
                        LabeledContent("Host", value: selectedDiscoveredPlayer.host)
                    } else {
                        LabeledContent("Host", value: model.manualSonosHost)
                    }

                    Button {
                        Task {
                            await model.refreshManualSonosPlayerState()
                        }
                    } label: {
                        if model.manualHostRefreshStatus.isRefreshing {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Refreshing From Player")
                            }
                        } else {
                            Label("Refresh From Player", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(model.manualHostRefreshStatus.isRefreshing)
                } header: {
                    Text("Selected Player")
                } footer: {
                    Text("Use this to force a fresh read of now playing, volume, queue context, and room details from the selected Sonos player.")
                }

                Section("Status") {
                    SettingsStatusRow(
                        title: "Player Refresh",
                        statusTitle: model.manualHostRefreshStatus.title,
                        detail: playerRefreshDetail,
                        systemImage: model.manualHostRefreshStatus.systemImage,
                        tint: playerRefreshTint
                    )

                    SettingsStatusRow(
                        title: "Room Name",
                        statusTitle: model.manualHostIdentityStatus.title,
                        detail: identityStatusDetail,
                        systemImage: model.manualHostIdentityStatus.systemImage,
                        tint: tint(for: model.manualHostIdentityStatus)
                    )

                    SettingsStatusRow(
                        title: "Bonded Setup",
                        statusTitle: model.manualHostTopologyStatus.title,
                        detail: topologyStatusDetail,
                        systemImage: model.manualHostTopologyStatus.systemImage,
                        tint: tint(for: model.manualHostTopologyStatus)
                    )
                }

                Section {
                    LabeledContent("Player State", value: refreshTimingText(for: model.manualHostLastSuccessfulRefreshAt))
                    LabeledContent("Room Name", value: refreshTimingText(for: model.manualHostIdentityLastRefreshAt))
                    LabeledContent("Bonded Setup", value: refreshTimingText(for: model.manualHostTopologyLastRefreshAt))
                } header: {
                    Text("Refresh Timing")
                } footer: {
                    Text("Tiny timing surface for manual verification of refresh, failure, and retry behavior.")
                }

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

                Section("Now Playing Diagnostics") {
                    LabeledContent("Observed At", value: refreshTimingText(for: model.nowPlayingObservedAt))
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
            } else {
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
        .miniPlayerContentInset()
        .navigationTitle("Settings")
    }

    private var discoveryStatusDetail: String? {
        if let lastSonosDiscoveryRefreshAt = model.lastSonosDiscoveryRefreshAt,
           !model.isSonosDiscoveryRefreshing
        {
            return "\(model.roomDiscoveryStatus.detail) Last updated \(lastSonosDiscoveryRefreshAt.formatted(.dateTime.hour().minute()))."
        }

        return model.roomDiscoveryStatus.detail
    }

    private var discoveryStatusTint: Color {
        switch model.roomDiscoveryStatus {
        case .scanning, .resolving:
            .secondary
        case .ready:
            .green
        case .failed:
            .orange
        }
    }

    private var playerRefreshDetail: String? {
        if let updatedAt = model.manualHostRefreshStatus.updatedAt {
            return "Last updated \(updatedAt.formatted(.dateTime.hour().minute()))"
        }

        return model.manualHostRefreshStatus.detail
    }

    private var playerRefreshTint: Color {
        switch model.manualHostRefreshStatus {
        case .idle:
            .secondary
        case .refreshing:
            .orange
        case .updated:
            .green
        case .failed:
            .red
        }
    }

    private var identityStatusDetail: String? {
        switch model.manualHostIdentityStatus {
        case .idle:
            "Waiting for a player refresh to resolve the current room."
        case .loading:
            "Reading the active room name from the selected player."
        case .resolved:
            "The current room is available in the Rooms tab."
        case .failed(let detail):
            detail
        }
    }

    private var topologyStatusDetail: String? {
        switch model.manualHostTopologyStatus {
        case .idle:
            "Waiting for a player refresh to load bonded setup details."
        case .loading:
            "Reading Sonos topology to resolve bonded products."
        case .resolved:
            "Bonded setup details are available in the Rooms tab."
        case .failed(let detail):
            detail
        }
    }

    private func tint(for status: SonosRoomDataStatus) -> Color {
        switch status {
        case .idle:
            .secondary
        case .loading:
            .orange
        case .resolved:
            .green
        case .failed:
            .red
        }
    }

    private func refreshTimingText(for date: Date?) -> String {
        guard let date else {
            return "Never"
        }

        return date.formatted(.dateTime.hour().minute().second())
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let statusTitle: String
    let detail: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(statusTitle)
                    .font(.subheadline.weight(.medium))

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SettingsDiscoveredPlayerRow: View {
    let player: SonosDiscoveredPlayer
    let isSelected: Bool
    let isSelecting: Bool
    let selectPlayer: () async -> Void

    var body: some View {
        Button {
            Task {
                await selectPlayer()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(player.detailText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isSelecting {
                    ProgressView()
                        .controlSize(.small)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle")
                        .font(.headline)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSelecting)
    }
}

private struct SettingsDiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    @Previewable @State var model = SonoicModel()

    NavigationStack {
        SettingsView()
            .environment(model)
    }
}
