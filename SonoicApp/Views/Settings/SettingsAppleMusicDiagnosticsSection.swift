import SwiftUI

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
