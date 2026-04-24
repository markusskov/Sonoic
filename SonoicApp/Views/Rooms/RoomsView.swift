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
                selectGroup: selectGroup
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
        .navigationTitle("Rooms")
    }
}

#Preview {
    NavigationStack {
        RoomsView()
            .environment(SonoicModel())
    }
}
