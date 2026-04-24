import SwiftUI

struct HomeFavoritesSection: View {
    let state: SonosFavoritesState
    let playFavorite: (SonosFavoriteItem) async -> Void
    let retryAction: () async -> Void

    var body: some View {
        switch state {
        case .idle, .loading:
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        HomeFavoriteLoadingCard()
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        case .empty:
            HomeMessageCard(
                title: "No Favorites Yet",
                detail: "Save a few Sonos favorites in the Sonos app and they'll appear here for quick playback."
            )
        case let .failed(detail):
            HomeActionCard(
                title: "Couldn't Load Favorites",
                detail: detail,
                buttonTitle: "Try Again",
                buttonSystemImage: "arrow.clockwise",
                action: retryAction
            )
        case let .loaded(snapshot):
            HomeFavoritesCarousel(items: snapshot.items, playFavorite: playFavorite)
        }
    }
}

struct HomeCollectionsSection: View {
    let collections: [SonosFavoriteItem]
    let playFavorite: (SonosFavoriteItem) async -> Void

    var body: some View {
        HomeFavoritesCarousel(items: collections, playFavorite: playFavorite)
    }
}

private struct HomeFavoritesCarousel: View {
    let items: [SonosFavoriteItem]
    let playFavorite: (SonosFavoriteItem) async -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(items) { favorite in
                    HomeFavoriteCard(favorite: favorite) {
                        await playFavorite(favorite)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}
