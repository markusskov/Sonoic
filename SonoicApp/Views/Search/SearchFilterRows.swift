import SwiftUI

struct SearchMessage: Equatable {
    var title: String
    var detail: String
    var systemImage: String
}

struct SearchSourceFilterRow: View {
    let sources: [SonoicSource]
    let selectedServiceID: String?
    let select: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                if sources.count > 1 {
                    SearchFilterChip(
                        title: "All",
                        systemImage: "square.grid.2x2",
                        isSelected: selectedServiceID == nil
                    ) {
                        select(nil)
                    }
                }

                ForEach(sources) { source in
                    SearchFilterChip(
                        title: sources.count == 1 ? source.service.name : nil,
                        systemImage: source.service.systemImage,
                        isSelected: selectedServiceID == source.service.id || sources.count == 1
                    ) {
                        select(source.service.id)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }
}

struct SearchScopeFilterRow: View {
    let selectedScope: SonoicSourceSearchScope
    let select: (SonoicSourceSearchScope) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(SonoicSourceSearchScope.allCases) { scope in
                    SearchFilterChip(
                        title: scope.title,
                        systemImage: nil,
                        isSelected: selectedScope == scope
                    ) {
                        select(scope)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }
}

struct SearchMessageRow: View {
    let message: SearchMessage

    var body: some View {
        HStack(spacing: 14) {
            RoomSurfaceIconView(
                systemImage: message.systemImage,
                size: 44,
                cornerRadius: 14,
                font: .body.weight(.semibold)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.body.weight(.medium))

                Text(message.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }
}

private struct SearchFilterChip: View {
    let title: String?
    let systemImage: String?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }

                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(isSelected ? SonoicTheme.Colors.primary : SonoicTheme.Colors.secondary)
            .padding(.horizontal, title == nil ? 12 : 14)
            .padding(.vertical, 9)
            .frame(minWidth: title == nil ? 44 : nil)
            .frame(minHeight: 40)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.interactive() : .regular,
            in: .capsule
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
