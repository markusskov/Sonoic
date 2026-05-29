import Foundation

nonisolated struct SonosPlaybackCommandRoute: Equatable {
    var mode: SonosControlAPIMode
    var authorizationStatus: SonosControlAPIState.AuthorizationStatus
    var selectedGroupID: String?
    var hasManualHost: Bool
    var hasConfiguredActiveTarget: Bool

    init(
        sonosControlAPIState: SonosControlAPIState,
        hasManualHost: Bool,
        hasConfiguredActiveTarget: Bool
    ) {
        mode = sonosControlAPIState.settings.mode
        authorizationStatus = sonosControlAPIState.authorizationStatus
        selectedGroupID = sonosControlAPIState.settings.selectedGroupID?.sonoicNonEmptyTrimmed
        self.hasManualHost = hasManualHost
        self.hasConfiguredActiveTarget = hasConfiguredActiveTarget
    }

    var routesCommandsToSonosControlAPI: Bool {
        mode.canSendCommands
    }

    var allowsLocalManualTransportCommands: Bool {
        !routesCommandsToSonosControlAPI
    }

    var hasReadySonosControlAPICommandAuthorization: Bool {
        routesCommandsToSonosControlAPI
            && authorizationStatus == .ready
    }

    var hasSonosControlAPICommandTarget: Bool {
        hasReadySonosControlAPICommandAuthorization
            && selectedGroupID != nil
    }

    var hasActiveSonosControlTarget: Bool {
        if routesCommandsToSonosControlAPI {
            return hasSonosControlAPICommandTarget
        }

        return hasManualHost
    }

    var hasResolvedSonosPlaybackTarget: Bool {
        if routesCommandsToSonosControlAPI {
            return selectedGroupID != nil || hasConfiguredActiveTarget
        }

        return hasManualHost
    }

    var canControlManualPlayback: Bool {
        hasActiveSonosControlTarget
    }

    var canSendPrimarySourcePlaybackCommands: Bool {
        hasActiveSonosControlTarget
    }
}
