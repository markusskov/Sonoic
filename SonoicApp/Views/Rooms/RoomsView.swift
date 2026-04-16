import SwiftUI

struct RoomsView: View {
    @Environment(SonoicModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                RoomsSectionHeader(
                    title: "Current Room",
                    subtitle: model.hasManualSonosHost
                        ? "Your active room and bonded setup."
                        : "Connect a player in Settings to load your room."
                )

                if model.hasManualSonosHost {
                    NavigationLink {
                        RoomDetailView(activeTarget: model.activeTarget)
                    } label: {
                        RoomsCurrentRoomCard(
                            roomName: model.activeTarget.name,
                            roomSummary: model.activeTarget.summary,
                            setupProducts: model.activeTarget.setupProducts
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    RoomsEmptyStateCard {
                        model.selectedTab = .settings
                    }
                }

                RoomsSectionHeader(
                    title: "Coming Next",
                    subtitle: "Discovery and grouping will expand this tab."
                )

                RoomSurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        RoomsUpcomingRow(
                            title: "Room discovery",
                            detail: "Find nearby Sonos rooms instead of relying on one manual host.",
                            systemImage: "dot.radiowaves.left.and.right"
                        )

                        RoomsUpcomingRow(
                            title: "Grouping",
                            detail: "See real room combinations and switch targets with confidence.",
                            systemImage: "square.stack.3d.up.fill"
                        )

                        RoomsUpcomingRow(
                            title: "Household overview",
                            detail: "Surface the rest of the home theater and room relationships cleanly.",
                            systemImage: "house.fill"
                        )
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Rooms")
    }
}

private struct RoomsCurrentRoomCard: View {
    let roomName: String
    let roomSummary: String
    let setupProducts: [SonosActiveTarget.SetupProduct]

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
        }
    }
}

private struct RoomsEmptyStateCard: View {
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

private struct RoomsUpcomingRow: View {
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

#Preview {
    NavigationStack {
        RoomsView()
            .environment(SonoicModel())
    }
}
