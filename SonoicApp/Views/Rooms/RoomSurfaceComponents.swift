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
        RoomSurfaceIconView(
            systemImage: product.systemImage,
            size: 44,
            cornerRadius: 14,
            font: .body.weight(.semibold),
            style: .glass
        )
    }
}

struct RoomSurfaceIconView: View {
    enum Style {
        case material
        case glass
    }

    let systemImage: String
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 18
    var font: Font = .title3.weight(.semibold)
    var tint: Color = .primary
    var style: Style = .material

    var body: some View {
        switch style {
        case .material:
            icon
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .glass:
            icon
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(font)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
    }
}
