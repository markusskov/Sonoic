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
        RoomSurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

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

            if !setupProducts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Setup")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(setupProducts) { product in
                            HStack(spacing: 12) {
                                RoomProductIconView(name: product.name)

                                Text(product.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Divider()

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

                Button {
                    Task {
                        await refreshAction()
                    }
                } label: {
                    Text(isRefreshing ? "Refreshing" : "Refresh")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRefreshing)
            }
        }
    }
}

struct RoomsEmptyStateCard: View {
    let openSettings: () -> Void

    var body: some View {
        RoomSurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("No Room Loaded", systemImage: "speaker.slash.fill")
                    .font(.headline)

                Text("Sonoic needs a manual player in Settings before it can show your current room and setup.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Open Settings", systemImage: "slider.horizontal.3", action: openSettings)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct RoomsUpcomingRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
