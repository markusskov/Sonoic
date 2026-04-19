import SwiftUI

struct SettingsView: View {
    @Environment(SonoicModel.self) private var model
    @State private var manualSonosHostDraft = ""

    var body: some View {
        Form {
            Section {
                TextField("192.168.1.42 or sonos.local", text: $manualSonosHostDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit(commitManualSonosHostIfNeeded)

                Text("Sonoic uses this player to read real now-playing, volume, mute, and playback over your local network. While the app stays open, it refreshes automatically, and iOS may refresh it again in the background when allowed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    commitManualSonosHostIfNeeded()

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
                .disabled(!hasManualSonosHostDraft || model.manualHostRefreshStatus.isRefreshing)
            } header: {
                Text("Manual Player")
            } footer: {
                Text("Rooms handles the active room and setup. Settings is reserved for manual player configuration, refresh control, and diagnostics.")
            }

            if model.hasManualSonosHost {
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
                    LabeledContent("Configured Host", value: model.manualSonosHost)
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
            } else {
                Section("Manual Mode") {
                    Label("Enter a player host to start manual setup and diagnostics.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .miniPlayerContentInset()
        .navigationTitle("Settings")
        .onAppear {
            manualSonosHostDraft = model.manualSonosHost
        }
        .onDisappear(perform: commitManualSonosHostIfNeeded)
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
            "Waiting for a manual refresh to resolve the current room."
        case .loading:
            "Reading the active room name from the configured player."
        case .resolved:
            "The current room is available in the Rooms tab."
        case .failed(let detail):
            detail
        }
    }

    private var topologyStatusDetail: String? {
        switch model.manualHostTopologyStatus {
        case .idle:
            "Waiting for a manual refresh to load bonded setup details."
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

    private var hasManualSonosHostDraft: Bool {
        !trimmedManualSonosHostDraft.isEmpty
    }

    private var trimmedManualSonosHostDraft: String {
        manualSonosHostDraft.sonoicTrimmed
    }

    private func commitManualSonosHostIfNeeded() {
        let committedHost = trimmedManualSonosHostDraft

        if manualSonosHostDraft != committedHost {
            manualSonosHostDraft = committedHost
        }

        guard model.manualSonosHost != committedHost else {
            return
        }

        model.manualSonosHost = committedHost
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

#Preview {
    @Previewable @State var model = SonoicModel()

    NavigationStack {
        SettingsView()
            .environment(model)
    }
}
