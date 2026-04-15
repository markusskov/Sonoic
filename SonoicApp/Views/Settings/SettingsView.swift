import SwiftUI

struct SettingsView: View {
    @Environment(SonoicModel.self) private var model
    @State private var manualSonosHostDraft = ""

    var body: some View {
        Form {
            Section("Connection") {
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

                statusContent
            }

            if model.hasManualSonosHost {
                Section("Player Snapshot") {
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
        .navigationTitle("Settings")
        .onAppear {
            manualSonosHostDraft = model.manualSonosHost
        }
        .onDisappear(perform: commitManualSonosHostIfNeeded)
    }

    @ViewBuilder
    private var statusContent: some View {
        if model.hasManualSonosHost {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.manualHostRefreshStatus.systemImage)
                    .foregroundStyle(statusTint)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.manualHostRefreshStatus.title)
                        .font(.subheadline.weight(.medium))

                    if let updatedAt = model.manualHostRefreshStatus.updatedAt {
                        Text("Last updated \(updatedAt, format: .dateTime.hour().minute())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let detail = model.manualHostRefreshStatus.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Label("Enter a player host to replace the sample volume with a real reading.", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusTint: Color {
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

    private var hasManualSonosHostDraft: Bool {
        !trimmedManualSonosHostDraft.isEmpty
    }

    private var trimmedManualSonosHostDraft: String {
        manualSonosHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
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

#Preview {
    @Previewable @State var model = SonoicModel()

    NavigationStack {
        SettingsView()
            .environment(model)
    }
}
