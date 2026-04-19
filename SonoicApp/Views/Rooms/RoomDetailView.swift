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
            .padding(20)
        }
        .miniPlayerContentInset()
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
