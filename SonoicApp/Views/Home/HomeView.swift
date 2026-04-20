import SwiftUI

struct HomeView: View {
    @Environment(SonoicModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if model.hasManualSonosHost {
                    HomeSectionHeader(
                        title: "Favorites",
                        subtitle: "Start something quickly from your saved Sonos favorites."
                    )

                    HomeFavoritesSection(
                        state: model.homeFavoritesState,
                        playFavorite: playFavorite,
                        retryAction: refreshFavorites
                    )

                    if !model.homeServices.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HomeSectionHeader(
                                title: "Services",
                                subtitle: "Truthful shortcuts inferred from what Sonoic can already see."
                            )

                            HomeServicesSection(services: model.homeServices)
                        }
                    }
                } else {
                    HomeSetupCard {
                        model.selectedTab = .settings
                    }
                }
            }
            .padding(20)
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .refreshable {
            guard model.hasManualSonosHost else {
                return
            }

            await refreshFavorites()
        }
        .task(id: model.manualSonosHost) {
            await model.loadHomeFavoritesIfNeeded()
        }
        .navigationTitle("Sonoic")
    }

    private func refreshFavorites() async {
        await model.refreshHomeFavorites(showLoading: false)
    }

    private func playFavorite(_ favorite: SonosFavoriteItem) async {
        _ = await model.playManualSonosFavorite(favorite)
    }
}

private struct HomeSetupCard: View {
    let openSettings: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("Connect a Player", systemImage: "speaker.wave.2.circle")
                    .font(.headline)

                Text("Add a manual Sonos player in Settings to load favorites, services, rooms, and playback controls.")
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
