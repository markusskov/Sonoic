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

    private var productCategory: String {
        let normalizedName = product.name.lowercased()

        switch product.role {
        case .subwoofer:
            return "Subwoofer"
        case .surroundSpeaker:
            return "Surround speaker"
        case .primaryPlayer:
            if normalizedName.contains("arc") || normalizedName.contains("beam") || normalizedName.contains("ray") {
                return "Soundbar"
            }

            if normalizedName.contains("amp") {
                return "Amplifier"
            }

            return "Speaker"
        case .bondedProduct:
            if normalizedName.contains("sub") {
                return "Subwoofer"
            }

            return "Speaker"
        }
    }

    private var roleBadgeTitle: String {
        switch product.role {
        case .primaryPlayer:
            return "Main"
        case .subwoofer:
            return "Sub"
        case .surroundSpeaker:
            return "Rear"
        case .bondedProduct:
            return "Bonded"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            RoomProductIconView(name: product.name)

            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(productCategory)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(roleBadgeTitle)
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
