import SwiftUI

struct RootView: View {
    @Environment(SonoicModel.self) private var model
    @State private var isPlayerPresented = false

    private static let miniPlayerBottomSpacing: CGFloat = 55
    private static let miniPlayerContentInset: CGFloat = 156

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
                .padding(.bottom, Self.miniPlayerBottomSpacing)
            }
        }
        .sheet(isPresented: $isPlayerPresented) {
            PlayerSheetView()
                .environment(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func rootNavigationView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.hasManualSonosHost {
                Color.clear
                    .frame(height: Self.miniPlayerContentInset)
            }
        }
    }
}

#Preview {
    @Previewable @State var model = SonoicModel()

    RootView()
        .environment(model)
}
