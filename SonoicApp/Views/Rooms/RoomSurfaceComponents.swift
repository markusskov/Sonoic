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
    private let isInteractive: Bool
    private let content: Content

    init(isInteractive: Bool = false, @ViewBuilder content: () -> Content) {
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            isInteractive ? .regular.interactive() : .regular,
            in: .rect(cornerRadius: 24)
        )
    }
}

struct RoomProductIconView: View {
    let product: SonosActiveTarget.SetupProduct

    var body: some View {
        Image(systemName: product.systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
