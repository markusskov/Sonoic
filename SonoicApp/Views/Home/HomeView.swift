import SwiftUI

struct HomeView: View {
    @Environment(SonoicModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.hasManualSonosHost {
                    HomeNowPlayingCard(nowPlaying: model.nowPlaying)
                } else {
                    HomeSetupCard {
                        model.selectedTab = .settings
                    }
                }
            }
            .padding(20)
        }
        .miniPlayerContentInset()
        .navigationTitle("Sonoic")
    }
}

private struct HomeSetupCard: View {
    let openSettings: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("Connect a Player", systemImage: "speaker.wave.2.circle")
                    .font(.headline)

                Text("Add a manual Sonos player in Settings to load real now playing, room, and playback controls.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Open Settings", systemImage: "slider.horizontal.3", action: openSettings)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    HomeView()
        .environment(SonoicModel())
}
