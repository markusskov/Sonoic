import SwiftUI

struct HomeTheaterView: View {
    @Environment(SonoicModel.self) var model
    @State var bassLevel = 0.0
    @State var trebleLevel = 0.0
    @State var subLevel = 0.0
    @State var isAdjustingBass = false
    @State var isAdjustingTreble = false
    @State var isAdjustingSub = false

    var body: some View {
        content
            .miniPlayerContentInset()
            .scrollIndicators(.hidden)
            .navigationTitle("Home Theater")
            .toolbar {
                if model.hasManualSonosHost {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await refreshHomeTheater(showLoading: false)
                            }
                        } label: {
                            if model.isHomeTheaterRefreshing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(model.isHomeTheaterRefreshing || model.isHomeTheaterMutating)
                        .accessibilityLabel("Refresh Home Theater")
                    }
                }
            }
            .alert(
                "Couldn't Update Home Theater",
                isPresented: Binding(
                    get: {
                        model.homeTheaterOperationErrorDetail != nil
                    },
                    set: { isPresented in
                        if !isPresented {
                            model.homeTheaterOperationErrorDetail = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.homeTheaterOperationErrorDetail ?? "")
            }
            .task(id: model.homeTheaterRefreshContext) {
                await loadHomeTheaterIfNeeded()
            }
            .onChange(of: model.homeTheaterState.settings, initial: true) { _, settings in
                syncLocalLevels(from: settings)
            }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasManualSonosHost {
            ContentUnavailableView {
                Label("No Room Selected", systemImage: "speaker.slash.fill")
            } description: {
                Text("Choose a discovered Sonos room before tuning home theater controls.")
            } actions: {
                Button("Open Rooms") {
                    model.selectedTab = .rooms
                }
            }
        } else {
            ScrollView {
                GlassEffectContainer(spacing: 18) {
                    VStack(alignment: .leading, spacing: 28) {
                        switch model.homeTheaterState {
                        case .idle, .loading:
                            HomeTheaterLoadingCard(isRefreshing: model.isHomeTheaterRefreshing)
                        case let .failed(detail):
                            HomeTheaterFailureCard(detail: detail) {
                                await refreshHomeTheater(showLoading: true)
                            }
                        case let .loaded(settings):
                            loadedContent(settings)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeTheaterView()
            .environment(SonoicModel())
    }
}
