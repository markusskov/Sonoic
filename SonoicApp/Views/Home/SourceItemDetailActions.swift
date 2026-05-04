import SwiftUI

struct SourcePlaylistActionRow: View {
    let isFavorite: Bool
    var canShuffle = true
    var canFavorite = true
    let shuffle: () async -> Void
    let play: () async -> Void
    let favorite: () async -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Task {
                    await shuffle()
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3.weight(.semibold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .disabled(!canShuffle)
            .opacity(canShuffle ? 1 : 0.42)
            .accessibilityLabel("Shuffle")

            Button {
                Task {
                    await play()
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel("Play")

            if canFavorite {
                Button {
                    Task {
                        await favorite()
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.title3.weight(.semibold))
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel(isFavorite ? "Saved to Sonos Favorites" : "Save to Sonos Favorites")
            }
        }
    }
}

struct SourcePlaylistActionSkeletonRow: View {
    var canFavorite = true

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 54, height: 54)

            Capsule()
                .fill(.white.opacity(0.16))
                .frame(maxWidth: .infinity)
                .frame(height: 54)

            if canFavorite {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 54, height: 54)
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SourceItemActionCard: View {
    let play: () async -> Void

    var body: some View {
        Button {
            Task {
                await play()
            }
        } label: {
            Label("Play", systemImage: "play.fill")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Play")
    }
}
