import Foundation

extension SonoicModel {
    func refreshSonosControlAPIAuthorizationState() {
        guard sonosOAuthConfiguration.isConfigured else {
            sonosControlAPIAuthorizationState = .notConfigured
            return
        }

        do {
            guard let tokenSet = try keychainStore.loadSonosTokenSet() else {
                sonosControlAPIAuthorizationState = .disconnected
                return
            }

            sonosControlAPIAuthorizationState = tokenSet.isExpired(leeway: 0)
                ? SonosControlAPIAuthorizationState(status: .expired)
                : SonosControlAPIAuthorizationState(status: .connected(expiresAt: tokenSet.expiresAt))
        } catch {
            sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .failed(error.localizedDescription))
        }
    }

    func connectSonosAccount() async {
        guard !sonosControlAPIAuthorizationState.isConnecting else {
            return
        }

        let configuration = sonosOAuthConfiguration
        guard configuration.isConfigured else {
            sonosControlAPIAuthorizationState = .notConfigured
            return
        }

        sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .connecting)

        do {
            let state = sonosOAuthClient.makeState()
            let authorizationURL = try sonosOAuthClient.authorizationURL(configuration: configuration, state: state)
            let callbackURL = try await sonosOAuthWebAuthenticator.authenticate(
                url: authorizationURL,
                callbackScheme: configuration.callbackScheme
            )
            let callback = try sonosOAuthClient.parseCallbackURL(callbackURL, expectedState: state)
            let tokenSet = try await sonosTokenBrokerClient.exchangeCode(
                callback.exchangeCode,
                configuration: configuration,
                state: callback.state
            )

            try keychainStore.saveSonosTokenSet(tokenSet)
            sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .connected(expiresAt: tokenSet.expiresAt))
        } catch {
            refreshSonosControlAPIAuthorizationState()
            if !sonosControlAPIAuthorizationState.isConnected {
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .failed(error.localizedDescription))
            }
        }
    }

    func disconnectSonosAccount() {
        do {
            try keychainStore.deleteSonosTokenSet()
            sonosControlAPIAuthorizationState = sonosOAuthConfiguration.isConfigured ? .disconnected : .notConfigured
        } catch {
            sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .failed(error.localizedDescription))
        }
    }

    func markOnboardingComplete() {
        hasCompletedOnboarding = true
        settingsStore.saveHasCompletedOnboarding(true)
    }
}
