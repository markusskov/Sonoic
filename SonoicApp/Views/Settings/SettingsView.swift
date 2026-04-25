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
                SettingsStatusSection(
                    model: model,
                    playerRefreshDetail: playerRefreshDetail,
                    playerRefreshTint: playerRefreshTint,
                    identityStatusDetail: identityStatusDetail,
                    topologyStatusDetail: topologyStatusDetail,
                    dataStatusTint: tint(for:)
                )
                SettingsRefreshTimingSection(model: model, refreshTimingText: refreshTimingText(for:))
                SettingsPlaybackDiagnosticsSection(model: model)
                SettingsNowPlayingDiagnosticsSection(model: model, refreshTimingText: refreshTimingText(for:))
            } else {
                SettingsEmptySelectionSection()
            }
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

#Preview {
    @Previewable @State var model = SonoicModel()

    NavigationStack {
        SettingsView()
            .environment(model)
    }
}
