import SwiftUI

private enum SourcePlaylistPendingAction {
    case shuffle
    case play
    case favorite
}

struct SourcePlaylistActionRow: View {
    let isFavorite: Bool
    var canShuffle = true
    var canFavorite = true
    let shuffle: () async -> Void
    let play: () async -> Void
    let favorite: () async -> Void
    @State private var pendingAction: SourcePlaylistPendingAction?

    var body: some View {
        HStack(spacing: 14) {
            Button {
                run(.shuffle, operation: shuffle)
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3.weight(.semibold))
                    .frame(width: 54, height: 54)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .sonoicCommandPulse(isActive: pendingAction == .shuffle, cornerRadius: 27)
            .disabled(!canShuffle)
            .opacity(canShuffle ? 1 : 0.42)
            .accessibilityLabel("Shuffle")

            Button {
                run(.play, operation: play)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .sonoicCommandPulse(isActive: pendingAction == .play, cornerRadius: 27)
            .accessibilityLabel("Play")

            if canFavorite {
                Button {
                    run(.favorite, operation: favorite)
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.title3.weight(.semibold))
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .sonoicCommandPulse(isActive: pendingAction == .favorite, cornerRadius: 27)
                .accessibilityLabel(isFavorite ? "Saved to Sonos Favorites" : "Save to Sonos Favorites")
            }
        }
    }

    private func run(_ action: SourcePlaylistPendingAction, operation: @escaping () async -> Void) {
        pendingAction = action

        Task {
            await operation()
            try? await Task.sleep(for: .milliseconds(160))

            await MainActor.run {
                if pendingAction == action {
                    pendingAction = nil
                }
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
    @State private var isPending = false

    var body: some View {
        Button(action: playTapped) {
            Label("Play", systemImage: "play.fill")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .sonoicCommandPulse(isActive: isPending, cornerRadius: 27)
        .accessibilityLabel("Play")
    }

    private func playTapped() {
        isPending = true

        Task {
            await play()
            try? await Task.sleep(for: .milliseconds(160))

            await MainActor.run {
                isPending = false
            }
        }
    }
}
