import SwiftUI

enum SonoicTheme {
    enum Colors {
        static let primary = Color.primary
        static let secondary = Color.secondary
        static let tertiary = Color.secondary.opacity(0.62)
        static let accent = Color.accentColor
        static let serviceAccent = Color.pink
    }

    enum Typography {
        static let listTitle = Font.body.weight(.medium)
        static let listSubtitle = Font.footnote
        static let sectionTitle = Font.headline
        static let badge = Font.caption.weight(.semibold)
    }

    enum Radius {
        static let surface: CGFloat = 24
        static let listTile: CGFloat = 8
        static let icon: CGFloat = 14
    }

    enum Layout {
        static let screenPadding: CGFloat = 20
        static let surfacePadding: CGFloat = 20
        static let listHorizontalPadding: CGFloat = 16
        static let listVerticalPadding: CGFloat = 4
        static let rowVerticalPadding: CGFloat = 12
        static let artworkDividerLeading: CGFloat = 0
        static let navigationDividerLeading: CGFloat = 58
        static let roomDividerLeading: CGFloat = 56
        static let iconDividerLeading: CGFloat = 46
    }

    enum Spacing {
        static let section: CGFloat = 14
        static let cardStack: CGFloat = 18
        static let row: CGFloat = 14
    }
}

struct SonoicListCard<Content: View>: View {
    var isInteractive = false
    var horizontalPadding = SonoicTheme.Layout.listHorizontalPadding
    var verticalPadding = SonoicTheme.Layout.listVerticalPadding
    var cornerRadius = SonoicTheme.Radius.surface

    private let content: Content

    init(
        isInteractive: Bool = false,
        horizontalPadding: CGFloat = SonoicTheme.Layout.listHorizontalPadding,
        verticalPadding: CGFloat = SonoicTheme.Layout.listVerticalPadding,
        cornerRadius: CGFloat = SonoicTheme.Radius.surface,
        @ViewBuilder content: () -> Content
    ) {
        self.isInteractive = isInteractive
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            isInteractive ? .regular.interactive() : .regular,
            in: .rect(cornerRadius: cornerRadius)
        )
    }
}

struct SonoicListRows<Item: Identifiable, RowContent: View>: View {
    let items: [Item]
    var dividerLeadingPadding = SonoicTheme.Layout.artworkDividerLeading

    private let rowContent: (Item, Int) -> RowContent

    init(
        _ items: [Item],
        dividerLeadingPadding: CGFloat = SonoicTheme.Layout.artworkDividerLeading,
        @ViewBuilder rowContent: @escaping (Item, Int) -> RowContent
    ) {
        self.items = items
        self.dividerLeadingPadding = dividerLeadingPadding
        self.rowContent = rowContent
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                rowContent(item, index)

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, dividerLeadingPadding)
                }
            }
        }
    }
}

struct SonoicListMoreButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("More")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SonoicTheme.Colors.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.42), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .accessibilityLabel("Show more")
    }
}
