import SwiftUI

struct RoomsView: View {
    @Environment(SonoicModel.self) private var model

    private var isRefreshingRoomState: Bool {
        model.manualHostRefreshStatus.isRefreshing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                RoomsSectionHeader(
                    title: "Current Room",
                    subtitle: model.hasManualSonosHost
                        ? "Your active room and bonded setup."
                        : "Connect a player in Settings to load your room."
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
                    RoomsEmptyStateCard {
                        model.selectedTab = .settings
                    }
                }

                RoomsSectionHeader(
                    title: "Room List",
                    subtitle: model.roomListItems.isEmpty
                        ? "Discovery will populate this when real room scanning arrives."
                        : "The current fallback room list will grow into real discovered rooms."
                )

                if model.roomListItems.isEmpty {
                    RoomSurfaceCard {
                        Text("No rooms are available yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    RoomsListCard(items: model.roomListItems)
                }

                RoomsSectionHeader(
                    title: "Discovery",
                    subtitle: "Groundwork for real room lists and grouping."
                )

                RoomsDiscoveryStatusCard(
                    status: model.roomDiscoveryStatus,
                    roomCount: model.roomListItems.count
                )

                RoomSurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        RoomsUpcomingRow(
                            title: "Room list",
                            detail: "Show nearby Sonos rooms instead of only the active manual-host room.",
                            systemImage: "list.bullet"
                        )

                        RoomsUpcomingRow(
                            title: "Grouping",
                            detail: "See real room combinations and switch targets with confidence.",
                            systemImage: "square.stack.3d.up.fill"
                        )

                        RoomsUpcomingRow(
                            title: "Household overview",
                            detail: "Surface the rest of the home theater and room relationships cleanly.",
                            systemImage: "house.fill"
                        )
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await refreshRoomState()
        }
        .task(id: model.manualSonosHost) {
            await loadRoomStateIfNeeded()
        }
        .navigationTitle("Rooms")
    }

    private func refreshRoomState() async {
        await model.refreshManualSonosPlayerState()
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
}

#Preview {
    NavigationStack {
        RoomsView()
            .environment(SonoicModel())
    }
}
