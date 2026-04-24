import SwiftUI

struct RoomGroupedRoomRow: View {
    let roomName: String

    var body: some View {
        HStack(spacing: 14) {
            RoomSurfaceIconView(
                systemImage: "speaker.wave.2.fill",
                size: 44,
                cornerRadius: 14,
                font: .body.weight(.semibold),
                style: .glass
            )

            Text(roomName)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

struct RoomFactRow: View {
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

struct RoomProductRow: View {
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
