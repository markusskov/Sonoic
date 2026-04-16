import SwiftUI

struct RoomDetailView: View {
    let activeTarget: SonosActiveTarget

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                RoomsSectionHeader(
                    title: "Name",
                    subtitle: "The current room Sonoic is controlling right now."
                )

                RoomSurfaceCard {
                    RoomFactRow(title: "Room", value: activeTarget.name)
                }

                RoomsSectionHeader(
                    title: "Products",
                    subtitle: "Resolved from the configured player and bonded setup."
                )

                RoomSurfaceCard {
                    VStack(spacing: 0) {
                        ForEach(Array(activeTarget.setupProducts.enumerated()), id: \.element.id) { index, product in
                            RoomProductRow(
                                name: product.name,
                                detail: product.role.detail
                            )

                            if index < activeTarget.setupProducts.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(activeTarget.name)
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
    let name: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            RoomProductIconView(name: name)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
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
