import SwiftUI

struct SettingsHouseholdSection: View {
    let model: SonoicModel
    let discoveryStatusDetail: String?
    let discoveryStatusTint: Color

    var body: some View {
        Section {
            SettingsStatusRow(
                title: "Rooms",
                statusTitle: model.roomDiscoveryStatus.title,
                detail: discoveryStatusDetail,
                systemImage: model.roomDiscoveryStatus.systemImage,
                tint: discoveryStatusTint
            )

            Button(action: refreshDiscovery) {
                if model.isSonosDiscoveryRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Refreshing")
                    }
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.isSonosDiscoveryRefreshing)

            if model.hasManualSonosHost {
                Button(role: .destructive, action: model.clearSelectedPlayer) {
                    Label("Forget Room", systemImage: "xmark.circle")
                }
            }
        } header: {
            Text("System")
        }
    }

    private func refreshDiscovery() {
        model.refreshSonosDiscovery()
    }
}

struct SettingsPlayerPickerSection: View {
    let model: SonoicModel

    var body: some View {
        Section("Rooms") {
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
}

struct SettingsSelectedPlayerSection: View {
    let model: SonoicModel

    var body: some View {
        Section {
            LabeledContent("Room", value: model.activeTarget.name)

            if let selectedDiscoveredPlayer = model.selectedDiscoveredPlayer {
                LabeledContent("Model", value: selectedDiscoveredPlayer.detailText)
            }

            Button(action: refreshPlayer) {
                if model.manualHostRefreshStatus.isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Refreshing")
                    }
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.manualHostRefreshStatus.isRefreshing)
        } header: {
            Text("Room")
        }
    }

    private func refreshPlayer() {
        Task {
            await model.refreshManualSonosPlayerState()
        }
    }
}

struct SettingsStatusSection: View {
    let model: SonoicModel
    let playerRefreshDetail: String?
    let playerRefreshTint: Color
    let identityStatusDetail: String?
    let topologyStatusDetail: String?
    let dataStatusTint: (SonosRoomDataStatus) -> Color

    var body: some View {
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
                tint: dataStatusTint(model.manualHostIdentityStatus)
            )

            SettingsStatusRow(
                title: "Bonded Setup",
                statusTitle: model.manualHostTopologyStatus.title,
                detail: topologyStatusDetail,
                systemImage: model.manualHostTopologyStatus.systemImage,
                tint: dataStatusTint(model.manualHostTopologyStatus)
            )
        }
    }
}

struct SettingsMusicServicesSection: View {
    let model: SonoicModel

    var body: some View {
        Section {
            ForEach(liveServices) { service in
                SettingsStatusRow(
                    title: service.name,
                    statusTitle: statusTitle(for: service),
                    detail: detailText(for: service),
                    systemImage: systemImage(for: service),
                    tint: tint(for: service)
                )

                if service.kind == .appleMusic {
                    Button(action: requestAppleMusicAuthorization) {
                        if model.appleMusicAuthorizationState.isRequestingAuthorization {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Connecting")
                            }
                        } else {
                            Label("Connect Apple Music", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }
                    .disabled(!model.appleMusicAuthorizationState.canRequestAuthorization)
                }
            }
        } header: {
            Text("Music")
        }
    }

    private var liveServices: [SonosServiceDescriptor] {
        [.appleMusic]
    }

    private func statusTitle(for service: SonosServiceDescriptor) -> String {
        switch service.kind {
        case .appleMusic:
            switch model.appleMusicAuthorizationState.status {
            case .authorized:
                "Connected"
            case .requesting:
                "Connecting"
            default:
                model.appleMusicAuthorizationState.title
            }
        case .spotify:
            "Unavailable"
        case .sonosRadio, .genericStreaming:
            "Available"
        }
    }

    private func detailText(for service: SonosServiceDescriptor) -> String? {
        switch service.kind {
        case .appleMusic:
            switch model.appleMusicAuthorizationState.status {
            case .authorized:
                nil
            case .requesting:
                "Connecting..."
            case .notDetermined:
                nil
            case .denied, .restricted, .unavailable:
                model.appleMusicAuthorizationState.detail
            }
        case .spotify:
            nil
        case .sonosRadio, .genericStreaming:
            nil
        }
    }

    private func tint(for service: SonosServiceDescriptor) -> Color {
        switch service.kind {
        case .appleMusic:
            tint(for: model.appleMusicAuthorizationState.status)
        case .spotify, .sonosRadio, .genericStreaming:
            .secondary
        }
    }

    private func systemImage(for service: SonosServiceDescriptor) -> String {
        switch service.kind {
        case .appleMusic:
            model.appleMusicAuthorizationState.systemImage
        case .spotify, .sonosRadio, .genericStreaming:
            service.systemImage
        }
    }

    private func tint(for status: SonoicAppleMusicAuthorizationState.Status) -> Color {
        switch status {
        case .authorized:
            .green
        case .requesting:
            .orange
        case .denied, .restricted, .unavailable:
            .red
        case .notDetermined:
            .orange
        }
    }

    private func requestAppleMusicAuthorization() {
        Task {
            await model.requestAppleMusicAuthorization()
        }
    }

}

struct SettingsSonosAccountSection: View {
    let model: SonoicModel

    var body: some View {
        Section {
            SettingsStatusRow(
                title: "Sonos Account",
                statusTitle: model.sonosControlAPIAuthorizationState.title,
                detail: detail,
                systemImage: model.sonosControlAPIAuthorizationState.systemImage,
                tint: tint
            )

            if model.sonosControlAPIAuthorizationState.isConnected {
                Button(role: .destructive, action: disconnect) {
                    Label("Disconnect", systemImage: "person.crop.circle.badge.xmark")
                }
            } else {
                Button(action: connect) {
                    if model.sonosControlAPIAuthorizationState.isConnecting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Connecting")
                        }
                    } else {
                        Label("Connect Sonos", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                .disabled(!model.sonosControlAPIAuthorizationState.canConnect)
            }
        } header: {
            Text("Sonos")
        }
    }

    private var tint: Color {
        switch model.sonosControlAPIAuthorizationState.status {
        case .connected:
            .green
        case .connecting, .disconnected, .notConfigured, .expired:
            .orange
        case .failed:
            .red
        }
    }

    private var detail: String? {
        model.sonosControlAPICloudState.detail
            ?? model.sonosControlAPIAuthorizationState.detail
    }

    private func connect() {
        Task {
            await model.connectSonosAccount()
        }
    }

    private func disconnect() {
        model.disconnectSonosAccount()
    }
}

struct SettingsAdvancedNavigationSection: View {
    let model: SonoicModel
    let playerRefreshDetail: String?
    let playerRefreshTint: Color
    let identityStatusDetail: String?
    let topologyStatusDetail: String?
    let dataStatusTint: (SonosRoomDataStatus) -> Color
    let refreshTimingText: (Date?) -> String

    var body: some View {
        Section {
            NavigationLink {
                SettingsAdvancedView(
                    model: model,
                    playerRefreshDetail: playerRefreshDetail,
                    playerRefreshTint: playerRefreshTint,
                    identityStatusDetail: identityStatusDetail,
                    topologyStatusDetail: topologyStatusDetail,
                    dataStatusTint: dataStatusTint,
                    refreshTimingText: refreshTimingText
                )
            } label: {
                Label("Advanced", systemImage: "wrench.and.screwdriver")
            }
        }
    }
}
