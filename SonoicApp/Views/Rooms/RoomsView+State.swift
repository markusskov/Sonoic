import SwiftUI

extension RoomsView {
    func refreshRoomState() async {
        await model.refreshManualSonosPlayerState()
    }

    func refreshDiscovery() async {
        model.refreshSonosDiscovery()
    }

    func refreshAllRoomState() async {
        model.refreshSonosDiscovery()

        guard model.hasManualSonosHost else {
            return
        }

        await refreshRoomState()
    }

    func loadRoomStateIfNeeded() async {
        guard model.hasManualSonosHost else {
            return
        }

        guard !model.manualHostRefreshStatus.isRefreshing else {
            return
        }

        guard !model.manualHostIdentityStatus.isResolved || !model.manualHostTopologyStatus.isResolved else {
            return
        }

        await refreshRoomState()
    }

    func selectRoom(_ item: SonosRoomListItem) async {
        await model.selectRoomListItem(item)
    }

    func selectGroup(_ group: SonosDiscoveredGroup) async {
        await model.selectDiscoveredGroup(group)
    }

    var currentRoomSubtitle: String {
        if activeTargetIsGroup {
            return "Your selected Sonos group and grouped rooms."
        }

        if model.hasManualSonosHost {
            return "Your selected room and bonded setup."
        }

        if model.hasDiscoveredPlayers {
            return "Choose one room below to start controlling it."
        }

        return "Sonoic is scanning your local network for Sonos speakers."
    }

    var roomListSubtitle: String {
        if activeTargetIsGroup {
            return "Individual rooms stay visible here with their current group membership."
        }

        return "Tap a room to make it the active player throughout Sonoic."
    }

    var currentRoomDiscoveryDetail: String {
        if model.hasDiscoveredPlayers {
            return "Pick a discovered room below to load its queue, favorites, and now-playing state."
        }

        return model.roomDiscoveryStatus.detail
    }

    var discoveryTint: Color {
        switch model.roomDiscoveryStatus {
        case .scanning, .resolving:
            .secondary
        case .ready:
            .green
        case .failed:
            .orange
        }
    }

    var discoveryActionTitle: String? {
        (model.roomDiscoveryStatus.isLoading || model.isSonosDiscoveryRefreshing) ? nil : "Refresh Discovery"
    }

    var discoveryAction: (() async -> Void)? {
        guard discoveryActionTitle != nil else {
            return nil
        }

        return {
            await refreshDiscovery()
        }
    }

    var activeTargetIsGroup: Bool {
        model.activeTarget.kind == .group
    }

    var activeTargetHasSubwoofer: Bool {
        model.activeTarget.setupProducts.contains { product in
            product.role == .subwoofer || product.name.localizedCaseInsensitiveContains("sub")
        }
    }

    var activeTargetHasSurrounds: Bool {
        model.activeTarget.setupProducts.contains { product in
            product.role == .surroundSpeaker
        }
    }

    var isTVAudioActive: Bool {
        if model.nowPlaying.sourceName == "TV Audio" {
            return true
        }

        return isTVAudioURI(model.nowPlayingDiagnostics.currentURI)
            || isTVAudioURI(model.nowPlayingDiagnostics.trackURI)
    }

    func isTVAudioURI(_ uri: String?) -> Bool {
        uri.sonoicNonEmptyTrimmed?.lowercased().hasPrefix("x-sonos-htastream:") == true
    }
}
