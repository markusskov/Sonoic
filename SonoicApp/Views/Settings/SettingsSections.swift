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
    let model: SonoicModel

    var body: some View {
        Section {
            ForEach(SonosServiceCatalog.browsableServices) { service in
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
                                Text("Authorizing Apple Music")
                            }
                        } else {
                            Label("Authorize Apple Music", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }
                    .disabled(!model.appleMusicAuthorizationState.canRequestAuthorization)

                    if model.appleMusicAuthorizationState.allowsCatalogSearch {
                        SettingsAppleMusicServiceDetailsRows(details: model.appleMusicServiceDetails)

                        Button(action: refreshAppleMusicDetails) {
                            if model.appleMusicServiceDetails.isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Refreshing Apple Music Details")
                                }
                            } else {
                                Label("Refresh Apple Music Details", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(model.appleMusicServiceDetails.isLoading)
                    }

                    SettingsMusicKitDiagnosticsRows(diagnostics: model.musicKitDiagnostics)
                }
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
            model.appleMusicAuthorizationState.title
        case .spotify:
            "Coming Later"
        case .sonosRadio, .genericStreaming:
            "Visible Through Sonos"
        }
    }

    private func detailText(for service: SonosServiceDescriptor) -> String {
        switch service.kind {
        case .appleMusic:
            model.appleMusicAuthorizationState.detail
        case .spotify:
            "Spotify account and catalog access are planned after Apple Music."
        case .sonosRadio, .genericStreaming:
            "This source appears when Sonos reports matching favorites or playback."
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

    private func refreshAppleMusicDetails() {
        Task {
            await model.refreshAppleMusicServiceDetails()
        }
    }
}

private struct SettingsAppleMusicServiceDetailsRows: View {
    let details: SonoicAppleMusicServiceDetails

    var body: some View {
        if details.status == .idle {
            SettingsStatusRow(
                title: "Apple Music Details",
                statusTitle: "Not Refreshed",
                detail: "Refresh Apple Music details to read storefront, subscription, and cloud library status.",
                systemImage: "music.note",
                tint: .secondary
            )
        } else if details.isLoading {
            SettingsStatusRow(
                title: "Apple Music Details",
                statusTitle: "Refreshing",
                detail: "Reading Apple Music account metadata.",
                systemImage: "arrow.clockwise",
                tint: .orange
            )
        } else if let failureDetail = details.failureDetail {
            SettingsStatusRow(
                title: "Apple Music Details",
                statusTitle: "Unavailable",
                detail: failureDetail,
                systemImage: "exclamationmark.triangle.fill",
                tint: .red
            )
        } else {
            LabeledContent("Storefront", value: details.storefrontCountryCode ?? "Unknown")
            LabeledContent("Catalog Playback", value: label(for: details.canPlayCatalogContent))
            LabeledContent("Subscription Offer", value: label(for: details.canBecomeSubscriber))
            LabeledContent("Cloud Library", value: label(for: details.hasCloudLibraryEnabled))
        }
    }

    private func label(for value: Bool?) -> String {
        guard let value else {
            return "Unknown"
        }

        return value ? "Available" : "Unavailable"
    }
}

private struct SettingsMusicKitDiagnosticsRows: View {
    let diagnostics: SonoicMusicKitDiagnostics

    var body: some View {
        LabeledContent("Bundle ID", value: diagnostics.bundleIdentifier)
        LabeledContent("MusicKit App Service", value: "Developer Portal")
        LabeledContent("Developer Token", value: diagnostics.usesAutomaticDeveloperTokenGeneration ? "Automatic" : "Manual")
        LabeledContent("Usage Description", value: diagnostics.hasUsageDescription ? "Present" : "Missing")
    }
}
