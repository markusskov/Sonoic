import SwiftUI

struct HomeView: View {
    @Environment(SonoicModel.self) private var model

    var body: some View {
        let recentPlays = model.homeRecentPlays

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if model.hasManualSonosHost {
                    HomeNowPlayingCard(
                        activeTarget: model.activeTarget,
                        nowPlaying: model.nowPlaying,
                        queueState: model.queueState,
                        togglePlayback: togglePlayback,
                        openRooms: openRooms,
                        openQueue: openQueue
                    )

                    if !recentPlays.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HomeSectionHeader(title: "Recently Played")

                            HomeRecentlyPlayedSection(
                                items: recentPlays,
                                playRecentItem: playRecentItem
                            )
                        }
                    }

                    HomeSectionHeader(title: "Favorites")

                    HomeFavoritesSection(
                        state: model.homeFavoritesState,
                        playFavorite: playFavorite,
                        retryAction: refreshFavorites
                    )

                    if !model.homeFavoriteCollections.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HomeSectionHeader(title: "Playlists & Stations")

                            HomeCollectionsSection(
                                collections: model.homeFavoriteCollections,
                                playFavorite: playFavorite
                            )
                        }
                    }

                    if !model.homeSources.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HomeSectionHeader(title: "Sources")

                            HomeServicesSection(sources: model.homeSources)
                        }
                    }
                } else {
                    HomeSetupCard {
                        openRooms()
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

            await refreshHome()
        }
        .task(id: model.manualSonosHost) {
            await model.loadHomeFavoritesIfNeeded()
            await model.refreshQueue(showLoading: false)
        }
        .navigationTitle("Sonoic")
    }

    private func refreshHome() async {
        await model.refreshManualSonosPlayerState(forceRoomRefresh: false)
        await refreshFavorites()
        await model.refreshQueue(showLoading: false)
    }

    private func refreshFavorites() async {
        await model.refreshHomeFavorites(showLoading: false)
    }

    private func playFavorite(_ favorite: SonosFavoriteItem) async {
        _ = await model.playManualSonosFavorite(favorite)
    }

    private func playRecentItem(_ recentItem: SonoicRecentPlayItem) async {
        _ = await model.playRecentItem(recentItem)
    }

    private func togglePlayback() async {
        await model.toggleManualSonosPlayback()
    }

    private func openRooms() {
        model.selectedTab = .rooms
    }

    private func openQueue() {
        model.selectedTab = .queue
    }
}

private struct HomeSetupCard: View {
    let openRooms: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("Choose a Room", systemImage: "speaker.wave.2.circle")
                    .font(.headline)

                Text("Select a room to start.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Open Rooms", systemImage: "speaker.wave.3", action: openRooms)
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
