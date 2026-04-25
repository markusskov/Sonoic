import SwiftUI

struct SettingsHouseholdSection: View {
    let model: SonoicModel
    let discoveryStatusDetail: String?
    let discoveryStatusTint: Color

    var body: some View {
        Section {
            SettingsStatusRow(
                title: "Discovery",
                statusTitle: model.roomDiscoveryStatus.title,
                detail: discoveryStatusDetail,
                systemImage: model.roomDiscoveryStatus.systemImage,
                tint: discoveryStatusTint
            )

            Button(action: refreshDiscovery) {
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
                Button(role: .destructive, action: model.clearSelectedPlayer) {
                    Label("Clear Selected Player", systemImage: "xmark.circle")
                }
            }
        } header: {
            Text("Sonos Household")
        } footer: {
            Text("Sonoic discovers nearby Sonos speakers automatically and uses your selected room for queue, favorites, now-playing, and lock-screen controls.")
        }
    }

    private func refreshDiscovery() {
        model.refreshSonosDiscovery()
    }
}

struct SettingsPlayerPickerSection: View {
    let model: SonoicModel

    var body: some View {
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
}

struct SettingsSelectedPlayerSection: View {
    let model: SonoicModel

    var body: some View {
        Section {
            LabeledContent("Selected Room", value: model.activeTarget.name)

            if let selectedDiscoveredPlayer = model.selectedDiscoveredPlayer {
                LabeledContent("Model", value: selectedDiscoveredPlayer.detailText)
                LabeledContent("Host", value: selectedDiscoveredPlayer.host)
            } else {
                LabeledContent("Host", value: model.manualSonosHost)
            }

            Button(action: refreshPlayer) {
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
    var body: some View {
        Section {
            ForEach(SonosServiceCatalog.browsableServices) { service in
                SettingsStatusRow(
                    title: service.name,
                    statusTitle: statusTitle(for: service),
                    detail: detailText(for: service),
                    systemImage: service.systemImage,
                    tint: tint(for: service)
                )
            }
        } header: {
            Text("Music Services")
        } footer: {
            Text("Sonoic will keep Sonos as the playback owner. Service accounts will only unlock catalog metadata and Sonos-native playback payloads when those integrations are ready.")
        }
    }

    private func statusTitle(for service: SonosServiceDescriptor) -> String {
        switch service.kind {
        case .appleMusic:
            "Search Shell Ready"
        case .spotify:
            "Coming Later"
        case .sonosRadio, .genericStreaming:
            "Visible Through Sonos"
        }
    }

    private func detailText(for service: SonosServiceDescriptor) -> String {
        switch service.kind {
        case .appleMusic:
            "Catalog search UI is in place. Authorization is not connected yet."
        case .spotify:
            "Spotify account and catalog access are planned after Apple Music."
        case .sonosRadio, .genericStreaming:
            "This source appears when Sonos reports matching favorites or playback."
        }
    }

    private func tint(for service: SonosServiceDescriptor) -> Color {
        switch service.kind {
        case .appleMusic:
            .orange
        case .spotify, .sonosRadio, .genericStreaming:
            .secondary
        }
    }
}
