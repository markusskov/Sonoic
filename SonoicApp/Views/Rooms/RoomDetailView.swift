import SwiftUI

struct RoomDetailView: View {
    @Environment(SonoicModel.self) private var model

    private var activeTarget: SonosActiveTarget {
        model.activeTarget
    }

    private var setupSummary: String {
        let count = activeTarget.setupProducts.count
        guard count != 1 else {
            return "1 product linked to this room."
        }

        return "\(count) products linked to this room."
    }

    private var groupedRoomSummary: String {
        let count = activeTarget.memberNames.count
        guard count != 1 else {
            return "1 room moving with this target."
        }

        return "\(count) rooms moving together right now."
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 28) {
                    RoomVolumeControlsSection(
                        activeTarget: activeTarget,
                        targetVolume: model.externalVolume,
                        roomVolumeState: model.roomVolumeState,
                        mutatingRoomVolumeIDs: model.mutatingRoomVolumeIDs,
                        operationErrorDetail: model.roomVolumeOperationErrorDetail,
                        isEnabled: model.hasManualSonosHost,
                        refreshAction: refreshRoomVolumes,
                        setTargetVolume: setTargetVolume,
                        toggleTargetMute: toggleTargetMute,
                        setRoomVolume: setRoomVolume,
                        toggleRoomMute: toggleRoomMute
                    )

                    if activeTarget.kind == .group {
                        RoomsSectionHeader(
                            title: "Group",
                            subtitle: "The current Sonos group Sonoic is controlling right now."
                        )

                        RoomSurfaceCard {
                            RoomFactRow(title: "Group", value: activeTarget.name)

                            if let coordinatorName = activeTarget.householdName.sonoicNonEmptyTrimmed {
                                Divider()
                                RoomFactRow(title: "Coordinator", value: coordinatorName)
                            }
                        }

                        RoomsSectionHeader(
                            title: "Grouped Rooms",
                            subtitle: groupedRoomSummary
                        )

                        RoomSurfaceCard {
                            VStack(spacing: 0) {
                                ForEach(Array(activeTarget.memberNames.enumerated()), id: \.offset) { index, roomName in
                                    RoomGroupedRoomRow(roomName: roomName)

                                    if index < activeTarget.memberNames.count - 1 {
                                        Divider()
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                        }
                    } else {
                        RoomsSectionHeader(
                            title: "Name",
                            subtitle: "The current room Sonoic is controlling right now."
                        )

                        RoomSurfaceCard {
                            RoomFactRow(title: "Room", value: activeTarget.name)
                        }

                        RoomsSectionHeader(
                            title: "Products",
                            subtitle: setupSummary
                        )

                        RoomSurfaceCard {
                            VStack(spacing: 0) {
                                ForEach(Array(activeTarget.setupProducts.enumerated()), id: \.element.id) { index, product in
                                    RoomProductRow(product: product)

                                    if index < activeTarget.setupProducts.count - 1 {
                                        Divider()
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle(activeTarget.name)
        .task(id: activeTarget.id) {
            await refreshRoomVolumes()
        }
        .refreshable {
            await refreshRoomVolumes()
        }
    }

    private func refreshRoomVolumes() async {
        await model.refreshRoomVolumes(showLoading: model.roomVolumeState.snapshot?.targetID != activeTarget.id)
    }

    private func setTargetVolume(_ level: Int) async -> Bool {
        let didSetVolume = await model.setManualSonosVolume(to: level)
        if didSetVolume {
            await model.refreshRoomVolumes(showLoading: false)
        }

        return didSetVolume
    }

    private func toggleTargetMute() async {
        await model.toggleManualSonosMute()
        await model.refreshRoomVolumes(showLoading: false)
    }

    private func setRoomVolume(_ item: SonosRoomVolumeItem, level: Int) async -> Bool {
        await model.setRoomVolume(item, to: level)
    }

    private func toggleRoomMute(_ item: SonosRoomVolumeItem) async {
        await model.toggleRoomMute(item)
    }
}

#Preview {
    @Previewable @State var model = SonoicModel()

    NavigationStack {
        RoomDetailView()
            .environment(model)
    }
    .onAppear {
        model.activeTarget = SonosActiveTarget(
            id: "living-room",
            name: "Living Room",
            householdName: "Sonos Arc Ultra",
            kind: .room,
            memberNames: ["Living Room", "Sub Mini"],
            bondedAccessories: [
                .init(
                    id: "living-room:satellite:sub-mini",
                    name: "Sub Mini",
                    role: .subwoofer
                )
            ]
        )
    }
}
