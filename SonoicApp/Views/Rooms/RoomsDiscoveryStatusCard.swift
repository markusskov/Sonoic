import SwiftUI

struct RoomsDiscoveryStatusCard: View {
    let status: SonosRoomDiscoveryStatus
    let roomCount: Int
    let lastUpdatedAt: Date?
    let isRefreshing: Bool
    let refreshAction: () async -> Void

    private var roomCountText: String? {
        guard roomCount > 0 else {
            return nil
        }

        if roomCount == 1 {
            return "1 room is available in Sonoic right now."
        }

        return "\(roomCount) rooms are available in Sonoic right now."
    }

    private var tint: Color {
        switch status {
        case .scanning, .resolving:
            .secondary
        case .ready:
            .green
        case .failed:
            .orange
        }
    }

    private var detailText: String {
        if let lastUpdatedAt,
           !isRefreshing
        {
            return "\(status.detail) Last updated \(lastUpdatedAt.formatted(.dateTime.hour().minute()))."
        }

        return status.detail
    }

    var body: some View {
        RoomSurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                statusIcon

                VStack(alignment: .leading, spacing: 6) {
                    Text(status.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let roomCountText {
                        Text(roomCountText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button(action: refreshTapped) {
                Label(isRefreshing ? "Refreshing" : "Refresh Discovery", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isRefreshing {
            ProgressView()
                .controlSize(.regular)
                .frame(width: 24, height: 24)
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            RoomSurfaceIconView(systemImage: status.systemImage, tint: tint)
        }
    }

    private func refreshTapped() {
        Task {
            await refreshAction()
        }
    }
}
