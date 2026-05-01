import SwiftUI

struct RootView: View {
    @Environment(SonoicModel.self) private var model
    @State private var isPlayerPresented = false
    @State private var isAppleMusicDetailRoutePresented = false
    @State private var routedAppleMusicItem: SonoicSourceItem?
    @State private var routedAppleMusicTab: RootTab?

    var body: some View {
        @Bindable var model = model

        TabView(selection: $model.selectedTab) {
            Tab(value: RootTab.home) {
                rootNavigationView(tab: .home) {
                    HomeView()
                }
            } label: {
                Label(RootTab.home.title, systemImage: RootTab.home.systemImage)
            }

            Tab(value: RootTab.rooms) {
                rootNavigationView(tab: .rooms) {
                    RoomsView()
                }
            } label: {
                Label(RootTab.rooms.title, systemImage: RootTab.rooms.systemImage)
            }

            Tab(value: RootTab.queue) {
                rootNavigationView(tab: .queue) {
                    QueueView()
                }
            } label: {
                Label(RootTab.queue.title, systemImage: RootTab.queue.systemImage)
            }

            Tab(value: RootTab.settings) {
                rootNavigationView(tab: .settings) {
                    SettingsView()
                }
            } label: {
                Label(RootTab.settings.title, systemImage: RootTab.settings.systemImage)
            }

            Tab(value: RootTab.search, role: .search) {
                rootNavigationView(tab: .search) {
                    SearchView()
                }
            } label: {
                Label(RootTab.search.title, systemImage: RootTab.search.systemImage)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(SonoicTheme.Colors.tabAccent)
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
        .onChange(of: model.pendingAppleMusicDetailRoute?.id) { _, _ in
            guard let item = model.pendingAppleMusicDetailRoute else {
                return
            }

            routedAppleMusicItem = item
            routedAppleMusicTab = model.selectedTab
            model.pendingAppleMusicDetailRoute = nil
            isAppleMusicDetailRoutePresented = true
        }
    }

    private func rootNavigationView<Content: View>(
        tab: RootTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .navigationDestination(isPresented: appleMusicRouteBinding(for: tab)) {
                    if let routedAppleMusicItem {
                        AppleMusicItemDetailView(item: routedAppleMusicItem)
                    }
                }
        }
    }

    private func appleMusicRouteBinding(for tab: RootTab) -> Binding<Bool> {
        Binding(
            get: {
                isAppleMusicDetailRoutePresented && routedAppleMusicTab == tab
            },
            set: { isPresented in
                guard routedAppleMusicTab == tab else {
                    return
                }

                isAppleMusicDetailRoutePresented = isPresented
                if !isPresented {
                    routedAppleMusicItem = nil
                    routedAppleMusicTab = nil
                }
            }
        )
    }
}

#Preview {
    @Previewable @State var model = SonoicModel()

    RootView()
        .environment(model)
}
