import Foundation

extension SonoicModel {
    private static let sonosControlAPITokenRefreshLeeway: TimeInterval = 120

    func refreshSonosControlAPIAuthorizationState() {
        guard sonosOAuthConfiguration.isConfigured else {
            sonosControlAPIAuthorizationState = .notConfigured
            markSonosControlAPIAuthorizationUnavailable()
            return
        }

        do {
            guard let tokenSet = try keychainStore.loadSonosTokenSet() else {
                sonosControlAPIAuthorizationState = .disconnected
                sonosControlAPICloudState = .idle
                markSonosControlAPIAuthorizationUnavailable()
                return
            }

            sonosControlAPIAuthorizationState = tokenSet.isExpired(leeway: 0)
                ? SonosControlAPIAuthorizationState(status: .expired)
                : SonosControlAPIAuthorizationState(status: .connected(expiresAt: tokenSet.expiresAt))
            if !sonosControlAPIAuthorizationState.isConnected {
                sonosControlAPICloudState = .idle
                sonosControlAPIState.authorizationStatus = .expired
            } else {
                markSonosControlAPIAuthorizationReady()
            }
        } catch {
            sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .failed(error.localizedDescription))
            sonosControlAPICloudState = .idle
            markSonosControlAPIAuthorizationUnavailable(error.localizedDescription)
        }
    }

    func validSonosControlAPITokenSetForCommands(
        logPrefix: String? = nil
    ) async -> SonosOAuthTokenSet? {
        guard sonosOAuthConfiguration.isConfigured else {
            sonosControlAPIAuthorizationState = .notConfigured
            markSonosControlAPIAuthorizationUnavailable()
            return nil
        }

        do {
            guard let tokenSet = try keychainStore.loadSonosTokenSet() else {
                sonosControlAPIAuthorizationState = .disconnected
                sonosControlAPICloudState = .idle
                markSonosControlAPIAuthorizationUnavailable()
                return nil
            }

            guard tokenSet.isExpired(leeway: Self.sonosControlAPITokenRefreshLeeway) else {
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(
                    status: .connected(expiresAt: tokenSet.expiresAt)
                )
                markSonosControlAPIAuthorizationReady()
                return tokenSet
            }

            guard let refreshToken = tokenSet.refreshToken?.sonoicNonEmptyTrimmed else {
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
                sonosControlAPIState.authorizationStatus = .expired
                sonosControlAPICloudState = .idle
                clearSonosControlAPICloudQueueContext()
                return nil
            }

            if let refreshTask = sonosControlAPITokenRefreshTask {
                if let logPrefix {
                    sonoicPlaybackDebugLog("\(logPrefix) refreshToken join")
                }
                return await refreshTask.value
            }

            if let logPrefix {
                sonoicPlaybackDebugLog("\(logPrefix) refreshToken start")
            }

            let refreshTask = Task { @MainActor in
                await refreshSonosControlAPITokenSet(
                    refreshToken: refreshToken,
                    logPrefix: logPrefix
                )
            }
            sonosControlAPITokenRefreshTask = refreshTask
            defer { sonosControlAPITokenRefreshTask = nil }

            let refreshedTokenSet = await refreshTask.value
            return refreshedTokenSet
        } catch {
            sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
            sonosControlAPIState.authorizationStatus = .expired
            sonosControlAPICloudState = .idle
            clearSonosControlAPICloudQueueContext()
            recordSonosControlAPIError(error)
            if let logPrefix {
                sonoicPlaybackDebugLog("\(logPrefix) refreshToken result=false error='\(error.localizedDescription)'")
            }
            return nil
        }
    }

    private func refreshSonosControlAPITokenSet(
        refreshToken: String,
        logPrefix: String?
    ) async -> SonosOAuthTokenSet? {
        do {
            var refreshedTokenSet = try await sonosTokenBrokerClient.refreshToken(
                refreshToken,
                configuration: sonosOAuthConfiguration
            )
            if refreshedTokenSet.refreshToken?.sonoicNonEmptyTrimmed == nil {
                refreshedTokenSet.refreshToken = refreshToken
            }

            guard !Task.isCancelled else {
                if let logPrefix {
                    sonoicPlaybackDebugLog("\(logPrefix) refreshToken result=false cancelled=true")
                }
                return nil
            }

            try keychainStore.saveSonosTokenSet(refreshedTokenSet)
            sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(
                status: .connected(expiresAt: refreshedTokenSet.expiresAt)
            )
            markSonosControlAPIAuthorizationReady()

            if let logPrefix {
                sonoicPlaybackDebugLog("\(logPrefix) refreshToken result=true")
            }

            return refreshedTokenSet
        } catch {
            if Task.isCancelled {
                if let logPrefix {
                    sonoicPlaybackDebugLog("\(logPrefix) refreshToken result=false cancelled=true")
                }
                return nil
            }

            sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
            sonosControlAPIState.authorizationStatus = .expired
            sonosControlAPICloudState = .idle
            clearSonosControlAPICloudQueueContext()
            recordSonosControlAPIError(error)
            if let logPrefix {
                sonoicPlaybackDebugLog("\(logPrefix) refreshToken result=false error='\(error.localizedDescription)'")
            }
            return nil
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
            markSonosControlAPIAuthorizationReady()
            if sonosControlAPIState.settings.mode == .off {
                var settings = sonosControlAPIState.settings
                settings.mode = .fallback
                updateSonosControlAPISettings(settings)
            }
            await refreshSonosControlAPICloudSnapshot()
        } catch {
            refreshSonosControlAPIAuthorizationState()
            if !sonosControlAPIAuthorizationState.isConnected {
                sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .failed(error.localizedDescription))
            }
        }
    }

    func disconnectSonosAccount() {
        do {
            sonosControlAPITokenRefreshTask?.cancel()
            sonosControlAPITokenRefreshTask = nil
            try keychainStore.deleteSonosTokenSet()
            sonosControlAPIAuthorizationState = sonosOAuthConfiguration.isConfigured ? .disconnected : .notConfigured
            sonosControlAPICloudState = .idle
            markSonosControlAPIAuthorizationUnavailable()
        } catch {
            sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .failed(error.localizedDescription))
            markSonosControlAPIAuthorizationUnavailable(error.localizedDescription)
        }
    }

    func refreshSonosControlAPICloudSnapshotIfConnected() {
        guard sonosOAuthConfiguration.isConfigured else {
            sonosControlAPICloudState = .idle
            return
        }

        Task {
            await refreshSonosControlAPICloudSnapshot()
        }
    }

    func refreshSonosControlAPICloudSnapshot() async {
        guard sonosOAuthConfiguration.isConfigured else {
            sonosControlAPICloudState = .idle
            return
        }

        sonosControlAPICloudState = SonosControlAPICloudState(status: .loading)

        do {
            guard let tokenSet = await validSonosControlAPITokenSetForCommands(
                logPrefix: "cloudSnapshot"
            ) else {
                sonosControlAPICloudState = .idle
                return
            }

            let snapshot = try await sonosControlAPIClient.fetchCloudSnapshot(tokenSet: tokenSet)
            sonosControlAPICloudState = SonosControlAPICloudState(status: .verified(snapshot))
            applyVerifiedSonosControlAPICloudSnapshot(snapshot)
        } catch let error as SonosControlAPITransport.TransportError where error.isAuthorizationFailure {
            sonosControlAPIAuthorizationState = SonosControlAPIAuthorizationState(status: .expired)
            sonosControlAPIState.authorizationStatus = .expired
            sonosControlAPICloudState = SonosControlAPICloudState(status: .failed(error.localizedDescription))
            clearSonosControlAPICloudQueueContext()
        } catch {
            sonosControlAPICloudState = SonosControlAPICloudState(status: .failed(error.localizedDescription))
        }
    }

    func markOnboardingComplete() {
        hasCompletedOnboarding = true
        settingsStore.saveHasCompletedOnboarding(true)
    }
}
