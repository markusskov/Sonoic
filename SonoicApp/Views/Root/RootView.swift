import SwiftUI

struct RootView: View {
    @Environment(SonoicModel.self) private var model
    @State private var isPlayerPresented = false

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedTab) {
            Tab(value: RootTab.home) {
                rootNavigationView {
                    HomeView()
                }
            } label: {
                Label(RootTab.home.title, systemImage: RootTab.home.systemImage)
            }

            Tab(value: RootTab.rooms) {
                rootNavigationView {
                    RoomsView()
                }
            } label: {
                Label(RootTab.rooms.title, systemImage: RootTab.rooms.systemImage)
            }

            Tab(value: RootTab.queue) {
                rootNavigationView {
                    QueueView()
                }
            } label: {
                Label(RootTab.queue.title, systemImage: RootTab.queue.systemImage)
            }

            Tab(value: RootTab.settings) {
                rootNavigationView {
                    SettingsView()
                }
            } label: {
                Label(RootTab.settings.title, systemImage: RootTab.settings.systemImage)
            }

            Tab(value: RootTab.search, role: .search) {
                rootNavigationView {
                    SearchView()
                }
            } label: {
                Label(RootTab.search.title, systemImage: RootTab.search.systemImage)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .overlay(alignment: .bottom) {
            if model.hasManualSonosHost {
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
                .padding(.bottom, MiniPlayerLayout.bottomSpacing)
            }
        }
        .sheet(isPresented: $isPlayerPresented) {
            PlayerSheetView()
                .environment(model)
                .presentationDetents([.fraction(1.0)])
                .presentationBackground(.clear)
                .presentationDragIndicator(.visible)
        }
    }

    private func rootNavigationView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
        }
    }
}

#Preview {
    @Previewable @State var model = SonoicModel()

    RootView()
        .environment(model)
}
