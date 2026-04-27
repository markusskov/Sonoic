import SwiftUI

struct SettingsView: View {
    @Environment(SonoicModel.self) private var model

    var body: some View {
        Form {
            SettingsHouseholdSection(
                model: model,
                discoveryStatusDetail: discoveryStatusDetail,
                discoveryStatusTint: discoveryStatusTint
            )

            if model.hasDiscoveredPlayers {
                SettingsPlayerPickerSection(model: model)
            }

            SettingsMusicServicesSection(model: model)

            if model.hasManualSonosHost {
                SettingsSelectedPlayerSection(model: model)
            } else {
                SettingsEmptySelectionSection()
            }

            SettingsAdvancedNavigationSection(
                model: model,
                playerRefreshDetail: playerRefreshDetail,
                playerRefreshTint: playerRefreshTint,
                identityStatusDetail: identityStatusDetail,
                topologyStatusDetail: topologyStatusDetail,
                dataStatusTint: tint(for:),
                refreshTimingText: refreshTimingText(for:)
            )
        }
        .miniPlayerContentInset()
        .navigationTitle("Settings")
        .task {
            model.refreshAppleMusicAuthorizationState()
            if model.appleMusicServiceDetails.isLoading {
                model.appleMusicServiceDetails = .idle
            }
        }
    }

    private var discoveryStatusDetail: String? {
        guard case .failed = model.roomDiscoveryStatus else {
            return nil
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

struct SettingsAdvancedView: View {
    let model: SonoicModel
    let playerRefreshDetail: String?
    let playerRefreshTint: Color
    let identityStatusDetail: String?
    let topologyStatusDetail: String?
    let dataStatusTint: (SonosRoomDataStatus) -> Color
    let refreshTimingText: (Date?) -> String

    var body: some View {
        Form {
            SettingsAdvancedMusicServicesSection(model: model)

            if model.hasManualSonosHost {
                SettingsStatusSection(
                    model: model,
                    playerRefreshDetail: playerRefreshDetail,
                    playerRefreshTint: playerRefreshTint,
                    identityStatusDetail: identityStatusDetail,
                    topologyStatusDetail: topologyStatusDetail,
                    dataStatusTint: dataStatusTint
                )
                SettingsRefreshTimingSection(model: model, refreshTimingText: refreshTimingText)
                SettingsPlaybackDiagnosticsSection(model: model)
                SettingsNowPlayingDiagnosticsSection(model: model, refreshTimingText: refreshTimingText)
                SettingsQueueDiagnosticsSection(model: model, refreshTimingText: refreshTimingText)
            }
        }
        .miniPlayerContentInset()
        .navigationTitle("Advanced")
        .task(id: model.queueRefreshContext) {
            await model.refreshQueue(showLoading: false)
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
