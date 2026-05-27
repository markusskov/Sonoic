import SwiftUI

struct RoomsViewContent: View {
    let model: SonoicModel
    let currentRoomSubtitle: String
    let currentRoomDiscoveryDetail: String
    let discoveryTint: Color
    let discoveryActionTitle: String?
    let discoveryAction: (() async -> Void)?
    let roomListSubtitle: String
    let isTVAudioActive: Bool
    let activeTargetHasSubwoofer: Bool
    let activeTargetHasSurrounds: Bool
    let refreshRoomState: () async -> Void
    let refreshDiscovery: () async -> Void
    let selectRoom: (SonosRoomListItem) async -> Void
    let selectGroup: (SonosDiscoveredGroup) async -> Void
    let refreshGroupControl: () async -> Void
    let addRoomToGroup: (SonosDiscoveredPlayer) async -> Void
    let removeRoomFromGroup: (SonosDiscoveredPlayer) async -> Void
    let setRoomVolume: (SonosRoomVolumeItem, Int) async -> Bool
    let toggleRoomMute: (SonosRoomVolumeItem) async -> Void

    private var isRefreshingRoomState: Bool {
        model.manualHostRefreshStatus.isRefreshing
    }

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(alignment: .leading, spacing: 28) {
                currentRoomSection
                groupControlSection
                roomListSection
                homeTheaterSection
                groupsSection
                discoverySection
            }
            .padding(20)
        }
    }

    private var currentRoomSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoomsSectionHeader(title: "Current Room", subtitle: currentRoomSubtitle)
            currentRoomCard
        }
    }

    @ViewBuilder
    private var currentRoomCard: some View {
        if model.hasManualSonosHost {
            if model.manualHostIdentityStatus.isResolved {
                NavigationLink {
                    RoomDetailView()
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
                    detail: "Loading room details.",
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
    }

    @ViewBuilder
    private var homeTheaterSection: some View {
        if model.hasManualSonosHost {
            RoomsSectionHeader(
                title: "Home Theater",
                subtitle: "TV, speech, night sound, and tuning."
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
    }

    @ViewBuilder
    private var groupsSection: some View {
        if model.hasDiscoveredGroups {
            RoomsSectionHeader(
                title: "Groups",
                subtitle: "Current groups."
            )

            RoomsGroupListCard(
                groups: model.discoveredGroups,
                selectingTargetID: model.selectingDiscoveredPlayerID,
                activeGroupID: model.selectedDiscoveredGroup?.id,
                selectGroup: selectGroup
            )
        }
    }

    @ViewBuilder
    private var groupControlSection: some View {
        if model.hasDiscoveredPlayers, model.hasManualSonosHost {
            RoomsSectionHeader(
                title: "Group Control",
                subtitle: model.activeTarget.kind == .group
                    ? "Rooms and volume."
                    : "Add rooms and adjust volume."
            )

            RoomsGroupControlCard(
                members: model.groupControlMembers,
                options: model.groupControlOptions,
                isRefreshing: model.isGroupControlRefreshing,
                addRoomToGroup: addRoomToGroup,
                removeRoomFromGroup: removeRoomFromGroup,
                setRoomVolume: setRoomVolume,
                toggleRoomMute: toggleRoomMute,
                refreshGroupControl: refreshGroupControl
            )
        }
    }

    private var roomListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoomsSectionHeader(
                title: "Room List",
                subtitle: model.roomListItems.isEmpty
                    ? "No rooms yet."
                    : roomListSubtitle
            )

            if model.roomListItems.isEmpty {
                RoomResolutionStateCard(
                    title: "No Rooms Yet",
                    detail: "Refresh to search again.",
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
        }
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoomsSectionHeader(
                title: "Discovery",
                subtitle: "Refresh nearby rooms."
            )

            RoomsDiscoveryStatusCard(
                status: model.roomDiscoveryStatus,
                roomCount: model.roomListItems.count,
                lastUpdatedAt: model.lastSonosDiscoveryRefreshAt,
                isRefreshing: model.isSonosDiscoveryRefreshing,
                refreshAction: refreshDiscovery
            )
        }
    }
}
