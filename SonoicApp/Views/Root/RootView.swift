import SwiftUI

struct RootView: View {
    @Environment(SonoicModel.self) private var model
    @State private var isPlayerPresented = false

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedTab) {
            Tab(value: RootTab.home) {
                NavigationStack {
                    HomeView()
                }
            } label: {
                Label(RootTab.home.title, systemImage: RootTab.home.systemImage)
            }

            Tab(value: RootTab.rooms) {
                NavigationStack {
                    RoomsView()
                }
            } label: {
                Label(RootTab.rooms.title, systemImage: RootTab.rooms.systemImage)
            }

            Tab(value: RootTab.queue) {
                NavigationStack {
                    QueueView()
                }
            } label: {
                Label(RootTab.queue.title, systemImage: RootTab.queue.systemImage)
            }

            Tab(value: RootTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            } label: {
                Label(RootTab.settings.title, systemImage: RootTab.settings.systemImage)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerMiniBar(
                nowPlaying: model.nowPlaying,
                openPlayer: {
                    isPlayerPresented = true
                },
                togglePlayback: {
                    Task {
                        await model.toggleManualSonosPlayback()
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 55)
        }
        .sheet(isPresented: $isPlayerPresented) {
            PlayerSheetView()
                .environment(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    @Previewable @State var model = SonoicModel()

    RootView()
        .environment(model)
}
