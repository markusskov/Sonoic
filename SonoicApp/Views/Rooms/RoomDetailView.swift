import SwiftUI

struct RoomDetailView: View {
    let activeTarget: SonosActiveTarget

    private var setupSummary: String {
        let count = activeTarget.setupProducts.count
        guard count != 1 else {
            return "1 product linked to this room."
        }

        return "\(count) products linked to this room."
    }

    private var groupedRoomSummary: String {
        let count = activeTarget.memberNames.count
        guard count != 1 else {
            return "1 room moving with this target."
        }

        return "\(count) rooms moving together right now."
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 28) {
                    if activeTarget.kind == .group {
                        RoomsSectionHeader(
                            title: "Group",
                            subtitle: "The current Sonos group Sonoic is controlling right now."
                        )

                        RoomSurfaceCard {
                            RoomFactRow(title: "Group", value: activeTarget.name)

                            if let coordinatorName = activeTarget.householdName.sonoicNonEmptyTrimmed {
                                Divider()
                                RoomFactRow(title: "Coordinator", value: coordinatorName)
                            }
                        }

                        RoomsSectionHeader(
                            title: "Grouped Rooms",
                            subtitle: groupedRoomSummary
                        )

                        RoomSurfaceCard {
                            VStack(spacing: 0) {
                                ForEach(Array(activeTarget.memberNames.enumerated()), id: \.offset) { index, roomName in
                                    RoomGroupedRoomRow(roomName: roomName)

                                    if index < activeTarget.memberNames.count - 1 {
                                        Divider()
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                        }
                    } else {
                        RoomsSectionHeader(
                            title: "Name",
                            subtitle: "The current room Sonoic is controlling right now."
                        )

                        RoomSurfaceCard {
                            RoomFactRow(title: "Room", value: activeTarget.name)
                        }

                        RoomsSectionHeader(
                            title: "Products",
                            subtitle: setupSummary
                        )

                        RoomSurfaceCard {
                            VStack(spacing: 0) {
                                ForEach(Array(activeTarget.setupProducts.enumerated()), id: \.element.id) { index, product in
                                    RoomProductRow(product: product)

                                    if index < activeTarget.setupProducts.count - 1 {
                                        Divider()
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle(activeTarget.name)
    }
}

private struct RoomGroupedRoomRow: View {
    let roomName: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))

            Text(roomName)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

private struct RoomFactRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(value)
                .foregroundStyle(.primary)
        }
        .font(.body)
    }
}

private struct RoomProductRow: View {
    let product: SonosActiveTarget.SetupProduct

    var body: some View {
        HStack(spacing: 14) {
            RoomProductIconView(product: product)

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(product.categoryTitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(product.badgeTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        RoomDetailView(
            activeTarget: SonosActiveTarget(
                id: "living-room",
                name: "Living Room",
                householdName: "Sonos Arc Ultra",
                kind: .room,
                memberNames: ["Living Room", "Sub Mini"],
                bondedAccessories: [
                    .init(
                        id: "living-room:satellite:sub-mini",
                        name: "Sub Mini",
                        role: .subwoofer
                    )
                ]
            )
        )
    }
}
