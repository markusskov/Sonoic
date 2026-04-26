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

struct SettingsAdvancedMusicServicesSection: View {
    let model: SonoicModel

    var body: some View {
        Section("Apple Music") {
            SettingsAppleMusicServiceDetailsRows(details: model.appleMusicServiceDetails)
            SettingsAppleMusicRequestReadinessRows(readiness: model.appleMusicRequestReadiness)

            Button(action: refreshAppleMusicDetails) {
                if model.appleMusicServiceDetails.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Refreshing")
                    }
                } else {
                    Label("Refresh Details", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.appleMusicServiceDetails.isLoading)

            SettingsMusicKitDiagnosticsRows(diagnostics: model.musicKitDiagnostics)
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

private struct SettingsAppleMusicRequestReadinessRows: View {
    let readiness: SonoicAppleMusicRequestReadiness

    var body: some View {
        SettingsStatusRow(
            title: "MusicKit Requests",
            statusTitle: readiness.title,
            detail: readiness.detail,
            systemImage: systemImage,
            tint: tint
        )

        if let lastFailure = readiness.lastFailure {
            LabeledContent("Last Failed Area", value: lastFailure.endpointFamily.title)
            LabeledContent("Last Failed At", value: lastFailure.occurredAt.formatted(.dateTime.hour().minute().second()))
        }
    }

    private var systemImage: String {
        switch readiness.status {
        case .idle:
            "clock"
        case .ready:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch readiness.status {
        case .idle:
            .secondary
        case .ready:
            .green
        case .failed:
            .red
        }
    }
}

private struct SettingsMusicKitDiagnosticsRows: View {
    let diagnostics: SonoicMusicKitDiagnostics

    var body: some View {
        LabeledContent("Bundle ID", value: diagnostics.bundleIdentifier)
        LabeledContent("MusicKit App Service", value: "Automatic token service")
        LabeledContent("Developer Token", value: diagnostics.usesAutomaticDeveloperTokenGeneration ? "Automatic" : "Manual")
        LabeledContent("Usage Description", value: diagnostics.hasUsageDescription ? "Present" : "Missing")
    }
}
