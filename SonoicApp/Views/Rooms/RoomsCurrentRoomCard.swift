import SwiftUI

struct RoomsCurrentRoomCard: View {
    let roomName: String
    let roomSummary: String
    let setupProducts: [SonosActiveTarget.SetupProduct]
    let topologyStatus: SonosRoomDataStatus
    let isRefreshing: Bool
    let lastUpdatedAt: Date?
    let refreshAction: () async -> Void

    private var refreshStatusText: String {
        if isRefreshing {
            return "Refreshing room details..."
        }

        switch topologyStatus {
        case .idle, .loading:
            return "Loading bonded setup..."
        case .failed:
            return "Setup details unavailable right now."
        case .resolved:
            break
        }

        if let lastUpdatedAt {
            return "Updated \(lastUpdatedAt.formatted(.dateTime.hour().minute()))"
        }

        return "Pull down or tap refresh to reload this room."
    }

    private var refreshStatusDetail: String? {
        topologyStatus.failureDetail
    }

    var body: some View {
        RoomSurfaceCard(isInteractive: true) {
            header
            setupProductsList
            Divider()
            refreshStatus
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            RoomSurfaceIconView(systemImage: "speaker.wave.3.fill")

            VStack(alignment: .leading, spacing: 6) {
                Text(roomName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(roomSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var setupProductsList: some View {
        if !setupProducts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Setup")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(setupProducts) { product in
                        HStack(spacing: 12) {
                            RoomProductIconView(product: product)

                            Text(product.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var refreshStatus: some View {
        HStack(spacing: 12) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(topologyStatus.failureDetail == nil ? Color.secondary : .orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(refreshStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let refreshStatusDetail {
                    Text(refreshStatusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button(isRefreshing ? "Refreshing" : "Refresh", action: refreshTapped)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRefreshing)
        }
    }

    private func refreshTapped() {
        Task {
            await refreshAction()
        }
    }
}
