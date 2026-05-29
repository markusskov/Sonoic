import SwiftUI

struct HomeServicesSection: View {
    let sources: [SonoicSource]

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(sources) { source in
                        NavigationLink {
                            SourceDetailView(source: source)
                        } label: {
                            HomeServiceChip(source: source)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct HomeServiceChip: View {
    let source: SonoicSource

    var body: some View {
        serviceIcon
            .frame(width: 78, height: 78)
            .accessibilityLabel(source.service.name)
    }

    @ViewBuilder
    private var serviceIcon: some View {
        if let iconAssetName = source.service.iconAssetName {
            Image(iconAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay(serviceBorder)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        } else {
            Image(systemName: source.service.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SonoicTheme.Colors.primary)
                .frame(width: 72, height: 72)
                .glassEffect(.regular, in: Circle())
                .overlay(serviceBorder)
        }
    }

    private var serviceBorder: some View {
        Circle()
            .strokeBorder(
                source.isCurrent ? SonoicTheme.Colors.tabAccent.opacity(0.9) : Color.white.opacity(0.12),
                lineWidth: source.isCurrent ? 2 : 1
            )
    }
}
