import SwiftUI

struct HomeTheaterLoadingCard: View {
    let isRefreshing: Bool

    var body: some View {
        RoomSurfaceCard {
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 6) {
                    Text(isRefreshing ? "Loading Home Theater" : "Home Theater")
                        .font(.headline)

                    Text("Reading EQ, cinema controls, and TV-control state from the selected room.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct HomeTheaterFailureCard: View {
    let detail: String
    let retry: () async -> Void

    var body: some View {
        RoomSurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 52, height: 52)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn't Load Home Theater")
                        .font(.headline)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Try Again", systemImage: "arrow.clockwise", action: retryTapped)
                .buttonStyle(.glass)
        }
    }

    private func retryTapped() {
        Task {
            await retry()
        }
    }
}
