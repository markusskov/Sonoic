import SwiftUI
import RevenueCatUI

struct SettingsPlusSection: View {
    let model: SonoicModel

    var body: some View {
        Section {
            NavigationLink {
                SettingsPlusView(model: model)
            } label: {
                SettingsStatusRow(
                    title: "Sonoic Plus",
                    statusTitle: model.plusState.settingsStatusTitle,
                    detail: model.plusState.settingsDetail,
                    systemImage: model.plusState.systemImage,
                    tint: statusTint
                )
            }
        }
    }

    private var statusTint: Color {
        switch model.plusState.status {
        case .notConfigured:
            .secondary
        case .refreshing:
            .orange
        case .available:
            SonoicTheme.Colors.tabAccent
        case .unlocked:
            .green
        case .failed:
            .red
        }
    }
}

struct SettingsPlusView: View {
    let model: SonoicModel

    @State private var isShowingPaywall = false
    @State private var isRestoring = false

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
            }

            Section("Included") {
                ForEach(SonoicPlusFeature.allCases) { feature in
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(feature.title)
                                .font(.body.weight(.medium))

                            Text(feature.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: feature.systemImage)
                            .foregroundStyle(SonoicTheme.Colors.tabAccent)
                    }
                }
            }

            Section {
                if canOpenPaywall {
                    Button(action: openPaywall) {
                        Label(primaryActionTitle, systemImage: primaryActionImage)
                    }
                } else {
                    SettingsStatusRow(
                        title: "RevenueCat",
                        statusTitle: "Not Configured",
                        detail: "Add RevenueCatAPIKey to the app bundle when the product is ready.",
                        systemImage: "sparkles",
                        tint: .secondary
                    )
                }

                Button(action: restorePurchases) {
                    if isRestoring {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Restoring")
                        }
                    } else {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRestoring || !canOpenPaywall)
            }
        }
        .navigationTitle("Sonoic Plus")
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(displayCloseButton: true)
                .onDisappear {
                    Task {
                        await model.refreshPlusState()
                    }
                }
        }
        .task {
            await model.refreshPlusState()
        }
    }

    private var canOpenPaywall: Bool {
        switch model.plusState.status {
        case .notConfigured:
            false
        case .refreshing, .available, .unlocked, .failed:
            true
        }
    }

    private var primaryActionTitle: String {
        model.hasPlus ? "Open Plus" : "Get Sonoic Plus"
    }

    private var primaryActionImage: String {
        model.hasPlus ? "checkmark.seal.fill" : "sparkles"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image("SonoicLogoMark")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Sonoic Plus")
                    .font(.largeTitle.bold())

                Text("Support development and make Sonoic feel more yours.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
    }

    private func openPaywall() {
        isShowingPaywall = true
    }

    private func restorePurchases() {
        Task {
            isRestoring = true
            await model.restorePlusPurchases()
            isRestoring = false
        }
    }
}
