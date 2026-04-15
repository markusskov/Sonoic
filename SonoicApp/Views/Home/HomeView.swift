import SwiftUI

struct HomeView: View {
    @Environment(SonoicModel.self) private var model
    @State private var isTargetPickerPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HomeTargetCard(
                    activeTarget: model.activeTarget,
                    connectionState: model.connectionState,
                    sourceName: model.nowPlaying.sourceName,
                    showTargetPicker: {
                        isTargetPickerPresented = true
                    }
                )

                HomeNowPlayingCard(nowPlaying: model.nowPlaying)
            }
            .padding(20)
        }
        .navigationTitle("Sonoic")
        .sheet(isPresented: $isTargetPickerPresented) {
            HomeTargetPickerView(
                activeTarget: model.activeTarget,
                availableTargets: model.availableTargets,
                selectTarget: model.selectActiveTarget
            )
        }
    }
}

#Preview {
    HomeView()
        .environment(SonoicModel())
}
