import SwiftUI

struct RoomsSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RoomSurfaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct RoomProductIconView: View {
    let name: String

    private var systemImage: String {
        let normalizedName = name.lowercased()

        if normalizedName.contains("sub") {
            return "speaker.fill"
        }

        if normalizedName.contains("arc") || normalizedName.contains("beam") || normalizedName.contains("ray") {
            return "speaker.wave.3.fill"
        }

        return "speaker.wave.2.fill"
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
