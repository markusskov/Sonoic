import SwiftUI

struct SearchDiscoverySection: View {
    let service: SonosServiceDescriptor
    let isAppleMusicAvailable: Bool

    private let destinations: [SonoicAppleMusicBrowseDestination] = [
        .categories,
        .popularRecommendations,
        .appleMusicPlaylists,
        .newReleases
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if service.kind == .appleMusic && isAppleMusicAvailable {
            VStack(alignment: .leading, spacing: 14) {
                HomeSectionHeader(title: "Browse")

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(destinations) { destination in
                        NavigationLink {
                            AppleMusicBrowseDestinationView(destination: destination)
                        } label: {
                            SearchDiscoveryTile(destination: destination)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct SearchDiscoveryTile: View {
    let destination: SonoicAppleMusicBrowseDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: destination.systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(SonoicTheme.Colors.serviceAccent)
                .frame(width: 42, height: 42)

            Spacer(minLength: 0)

            Text(title)
                .font(SonoicTheme.Typography.sectionTitle)
                .foregroundStyle(SonoicTheme.Colors.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var title: String {
        switch destination {
        case .categories:
            "Categories"
        case .popularRecommendations:
            "Popular"
        case .appleMusicPlaylists:
            "Playlists"
        case .newReleases:
            "New Releases"
        default:
            destination.title
        }
    }
}
