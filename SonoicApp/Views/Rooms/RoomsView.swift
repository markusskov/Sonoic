import SwiftUI

struct RoomsView: View {
    @Environment(SonoicModel.self) private var model

    private var isRefreshingRoomState: Bool {
        model.manualHostRefreshStatus.isRefreshing
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 28) {
                    RoomsSectionHeader(
                        title: "Current Room",
                        subtitle: currentRoomSubtitle
                    )

                    if model.hasManualSonosHost {
                        if model.manualHostIdentityStatus.isResolved {
                            NavigationLink {
                                RoomDetailView(activeTarget: model.activeTarget)
                            } label: {
                                RoomsCurrentRoomCard(
                                    roomName: model.activeTarget.name,
                                    roomSummary: model.activeTarget.summary,
                                    setupProducts: model.activeTarget.setupProducts,
                                    topologyStatus: model.manualHostTopologyStatus,
                                    isRefreshing: isRefreshingRoomState,
                                    lastUpdatedAt: model.manualHostRefreshStatus.updatedAt,
                                    refreshAction: refreshRoomState
                                )
                            }
                            .buttonStyle(.plain)
                        } else if let failureDetail = model.manualHostIdentityStatus.failureDetail {
                            RoomResolutionStateCard(
                                title: "Couldn't Load Room",
                                detail: failureDetail,
                                systemImage: "exclamationmark.triangle.fill",
                                tint: .orange,
                                isLoading: false,
                                actionTitle: "Try Again",
                                action: refreshRoomState
                            )
                        } else {
                            RoomResolutionStateCard(
                                title: "Resolving Room",
                                detail: "Sonoic is loading the current room name and bonded setup from the configured player.",
                                systemImage: "arrow.clockwise",
                                tint: .secondary,
                                isLoading: true,
                                actionTitle: nil,
                                action: nil
                            )
                        }
                    } else {
                        RoomResolutionStateCard(
                            title: model.roomDiscoveryStatus.title,
                            detail: currentRoomDiscoveryDetail,
                            systemImage: model.roomDiscoveryStatus.systemImage,
                            tint: discoveryTint,
                            isLoading: model.roomDiscoveryStatus.isLoading || model.isSonosDiscoveryRefreshing,
                            actionTitle: discoveryActionTitle,
                            action: discoveryAction
                        )
                    }

                    if model.hasManualSonosHost {
                        RoomsSectionHeader(
                            title: "Home Theater",
                            subtitle: "Room tuning, cinema controls, and TV audio state."
                        )

                        NavigationLink {
                            HomeTheaterView()
                        } label: {
                            RoomsHomeTheaterCard(
                                roomName: model.activeTarget.name,
                                sourceName: model.nowPlaying.sourceName,
                                isTVAudioActive: isTVAudioActive,
                                hasSubwoofer: activeTargetHasSubwoofer,
                                hasSurrounds: activeTargetHasSurrounds,
                                settings: model.homeTheaterState.settings,
                                isRefreshing: model.isHomeTheaterRefreshing
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if model.hasDiscoveredGroups {
                        RoomsSectionHeader(
                            title: "Groups",
                            subtitle: "Current Sonos room groups across your household."
                        )

                        RoomsGroupListCard(
                            groups: model.discoveredGroups,
                            selectingTargetID: model.selectingDiscoveredPlayerID,
                            activeGroupID: model.selectedDiscoveredGroup?.id,
                            selectGroup: selectGroup
                        )
                    }

                    RoomsSectionHeader(
                        title: "Room List",
                        subtitle: model.roomListItems.isEmpty
                            ? "Nearby Sonos rooms appear here as discovery resolves."
                            : roomListSubtitle
                    )

                    if model.roomListItems.isEmpty {
                        RoomResolutionStateCard(
                            title: "No Rooms Yet",
                            detail: "Sonoic will populate this list as your Sonos speakers answer discovery.",
                            systemImage: "speaker.wave.2.circle",
                            tint: .secondary,
                            isLoading: model.isSonosDiscoveryRefreshing,
                            actionTitle: "Refresh Discovery",
                            action: refreshDiscovery
                        )
                    } else {
                        RoomsListCard(
                            items: model.roomListItems,
                            selectingItemID: model.selectingDiscoveredPlayerID,
                            selectItem: selectRoom
                        )
                    }

                    RoomsSectionHeader(
                        title: "Discovery",
                        subtitle: "Real-time Sonos household discovery over your local network."
                    )

                    RoomsDiscoveryStatusCard(
                        status: model.roomDiscoveryStatus,
                        roomCount: model.roomListItems.count,
                        lastUpdatedAt: model.lastSonosDiscoveryRefreshAt,
                        isRefreshing: model.isSonosDiscoveryRefreshing,
                        refreshAction: refreshDiscovery
                    )
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .refreshable {
            await refreshAllRoomState()
        }
        .task(id: model.manualSonosHost) {
            await loadRoomStateIfNeeded()
        }
        .navigationTitle("Rooms")
    }

    private func refreshRoomState() async {
        await model.refreshManualSonosPlayerState()
    }

    private func refreshDiscovery() async {
        model.refreshSonosDiscovery()
    }

    private func refreshAllRoomState() async {
        model.refreshSonosDiscovery()

        guard model.hasManualSonosHost else {
            return
        }

        await refreshRoomState()
    }

    private func loadRoomStateIfNeeded() async {
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

    private func selectRoom(_ item: SonosRoomListItem) async {
        await model.selectRoomListItem(item)
    }

    private func selectGroup(_ group: SonosDiscoveredGroup) async {
        await model.selectDiscoveredGroup(group)
    }

    private var currentRoomSubtitle: String {
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

    private var roomListSubtitle: String {
        if activeTargetIsGroup {
            return "Individual rooms stay visible here with their current group membership."
        }

        return "Tap a room to make it the active player throughout Sonoic."
    }

    private var currentRoomDiscoveryDetail: String {
        if model.hasDiscoveredPlayers {
            return "Pick a discovered room below to load its queue, favorites, and now-playing state."
        }

        return model.roomDiscoveryStatus.detail
    }

    private var discoveryTint: Color {
        switch model.roomDiscoveryStatus {
        case .scanning, .resolving:
            .secondary
        case .ready:
            .green
        case .failed:
            .orange
        }
    }

    private var discoveryActionTitle: String? {
        (model.roomDiscoveryStatus.isLoading || model.isSonosDiscoveryRefreshing) ? nil : "Refresh Discovery"
    }

    private var discoveryAction: (() async -> Void)? {
        guard discoveryActionTitle != nil else {
            return nil
        }

        return {
            await refreshDiscovery()
        }
    }

    private var activeTargetIsGroup: Bool {
        model.activeTarget.kind == .group
    }

    private var activeTargetHasSubwoofer: Bool {
        model.activeTarget.setupProducts.contains { product in
            product.role == .subwoofer || product.name.localizedCaseInsensitiveContains("sub")
        }
    }

    private var activeTargetHasSurrounds: Bool {
        model.activeTarget.setupProducts.contains { product in
            product.role == .surroundSpeaker
        }
    }

    private var isTVAudioActive: Bool {
        if model.nowPlaying.sourceName == "TV Audio" {
            return true
        }

        return isTVAudioURI(model.nowPlayingDiagnostics.currentURI)
            || isTVAudioURI(model.nowPlayingDiagnostics.trackURI)
    }

    private func isTVAudioURI(_ uri: String?) -> Bool {
        uri.sonoicNonEmptyTrimmed?.lowercased().hasPrefix("x-sonos-htastream:") == true
    }
}

#Preview {
    NavigationStack {
        RoomsView()
            .environment(SonoicModel())
    }
}
