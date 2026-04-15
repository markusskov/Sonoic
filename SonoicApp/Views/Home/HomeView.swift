import SwiftUI

struct HomeView: View {
    @Environment(SonoicModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HomeNowPlayingCard(nowPlaying: model.nowPlaying)
            }
            .padding(20)
        }
        .navigationTitle("Sonoic")
    }
}

#Preview {
    HomeView()
        .environment(SonoicModel())
}
