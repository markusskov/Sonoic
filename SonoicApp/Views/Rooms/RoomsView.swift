import SwiftUI

struct RoomsView: View {
    @Environment(SonoicModel.self) var model

    var body: some View {
        ScrollView {
            RoomsViewContent(
                model: model,
                currentRoomSubtitle: currentRoomSubtitle,
                currentRoomDiscoveryDetail: currentRoomDiscoveryDetail,
                discoveryTint: discoveryTint,
                discoveryActionTitle: discoveryActionTitle,
                discoveryAction: discoveryAction,
                roomListSubtitle: roomListSubtitle,
                isTVAudioActive: isTVAudioActive,
                activeTargetHasSubwoofer: activeTargetHasSubwoofer,
                activeTargetHasSurrounds: activeTargetHasSurrounds,
                refreshRoomState: refreshRoomState,
                refreshDiscovery: refreshDiscovery,
                selectRoom: selectRoom,
                selectGroup: selectGroup,
                refreshGroupControl: refreshGroupControl,
                addRoomToGroup: addRoomToGroup,
                removeRoomFromGroup: removeRoomFromGroup,
                setRoomVolume: setRoomVolume,
                toggleRoomMute: toggleRoomMute
            )
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .refreshable {
            await refreshAllRoomState()
        }
        .task(id: model.manualSonosHost) {
            await loadRoomStateIfNeeded()
        }
        .task(id: groupControlRefreshContext) {
            await refreshGroupControl()
        }
        .alert(
            "Couldn't Update Group",
            isPresented: Binding(
                get: {
                    model.groupControlErrorDetail != nil || model.roomVolumeOperationErrorDetail != nil
                },
                set: { isPresented in
                    if !isPresented {
                        model.groupControlErrorDetail = nil
                        model.roomVolumeOperationErrorDetail = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.groupControlErrorDetail ?? model.roomVolumeOperationErrorDetail ?? "")
        }
        .navigationTitle("Rooms")
    }
}

#Preview {
    NavigationStack {
        RoomsView()
            .environment(SonoicModel())
    }
}
