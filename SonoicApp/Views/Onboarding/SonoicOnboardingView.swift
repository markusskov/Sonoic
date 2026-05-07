import SwiftUI

struct SonoicOnboardingView: View {
    @Environment(SonoicModel.self) private var model
    @State private var step = Step.splash
    @State private var hasAllowedDiscoveryContinue = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 24)

                content

                Spacer(minLength: 24)

                controls
            }
        }
        .task {
            model.refreshSonosControlAPIAuthorizationState()
            model.startSonosDiscoveryIfPossible()

            do {
                try await Task.sleep(for: .seconds(1))
                hasAllowedDiscoveryContinue = true
            } catch {}
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 14) {
            Button(action: advance) {
                HStack(spacing: 10) {
                    if isWorking {
                        ProgressView()
                            .tint(.black)
                    }

                    Text(buttonTitle)
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(SonoicTheme.Colors.tabAccent)
            .foregroundStyle(.black)
            .disabled(isButtonDisabled)

            if canSkipSonosAccount {
                Button("Skip for Now") {
                    step = .locatingSpeakers
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .disabled(isWorking)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .splash:
            VStack(spacing: 24) {
                Image("Sonoic-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

                Text("Sonoic")
                    .font(.system(size: 54, weight: .bold))
            }
            .foregroundStyle(.white)

        case .sonosAccount:
            VStack(spacing: 18) {
                Image(systemName: model.sonosControlAPIAuthorizationState.systemImage)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(accountTint)

                Text("Connect Sonos")
                    .font(.largeTitle.bold())

                Text("Sign in once for Sonos cloud controls.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .foregroundStyle(.white)

        case .locatingSpeakers:
            VStack(spacing: 18) {
                if model.hasDiscoveredPlayers {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(SonoicTheme.Colors.tabAccent)
                }

                Text(model.hasDiscoveredPlayers ? "Speakers Found" : "Locating Speakers")
                    .font(.largeTitle.bold())

                Text(discoveryText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .foregroundStyle(.white)
        }
    }

    private var accountTint: Color {
        model.sonosControlAPIAuthorizationState.isConnected ? .green : SonoicTheme.Colors.tabAccent
    }

    private var discoveryText: String {
        if let player = model.selectedDiscoveredPlayer {
            return player.name
        }

        if model.hasDiscoveredPlayers {
            return "Rooms found"
        }

        return "Make sure your iPhone is on the same Wi-Fi as your Sonos system."
    }

    private var buttonTitle: String {
        switch step {
        case .splash:
            return "Continue"
        case .sonosAccount:
            if model.sonosControlAPIAuthorizationState.isConnected {
                return "Continue"
            }

            return model.sonosOAuthConfiguration.isConfigured ? "Connect Sonos" : "Continue"
        case .locatingSpeakers:
            return "Start Listening"
        }
    }

    private var isWorking: Bool {
        switch step {
        case .sonosAccount:
            model.sonosControlAPIAuthorizationState.isConnecting
        case .locatingSpeakers:
            !hasAllowedDiscoveryContinue && !model.hasDiscoveredPlayers
        case .splash:
            false
        }
    }

    private var isButtonDisabled: Bool {
        switch step {
        case .sonosAccount:
            model.sonosControlAPIAuthorizationState.isConnecting
        case .locatingSpeakers:
            !hasAllowedDiscoveryContinue && !model.hasDiscoveredPlayers
        case .splash:
            false
        }
    }

    private func advance() {
        switch step {
        case .splash:
            step = shouldShowSonosAccount ? .sonosAccount : .locatingSpeakers
        case .sonosAccount:
            guard model.sonosOAuthConfiguration.isConfigured,
                  !model.sonosControlAPIAuthorizationState.isConnected
            else {
                step = .locatingSpeakers
                return
            }

            Task {
                await model.connectSonosAccount()
                if model.sonosControlAPIAuthorizationState.isConnected {
                    step = .locatingSpeakers
                }
            }
        case .locatingSpeakers:
            model.markOnboardingComplete()
        }
    }

    private var shouldShowSonosAccount: Bool {
        model.sonosOAuthConfiguration.isConfigured
            && !model.sonosControlAPIAuthorizationState.isConnected
    }

    private var canSkipSonosAccount: Bool {
        step == .sonosAccount
            && model.sonosOAuthConfiguration.isConfigured
            && !model.sonosControlAPIAuthorizationState.isConnected
    }
}

private enum Step {
    case splash
    case sonosAccount
    case locatingSpeakers
}

#Preview {
    @Previewable @State var model = SonoicModel()

    SonoicOnboardingView()
        .environment(model)
}
