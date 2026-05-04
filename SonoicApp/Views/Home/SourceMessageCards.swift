import SwiftUI

struct SourceMessageCard: View {
    let title: String
    var detail: String? = nil
    let systemImage: String

    var body: some View {
        RoomSurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct SourceEmptyCard: View {
    let serviceName: String

    var body: some View {
        RoomSurfaceCard {
            Label("No \(serviceName) Items", systemImage: "music.note.list")
                .font(.headline)
        }
    }
}

struct SourceCatalogPlaceholderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Search"
            )

            SonoicListCard {
                SourceNavigationRow(
                    row: SourceNavigationRow.Model(
                        title: "Search",
                        subtitle: "Not connected yet",
                        systemImage: "magnifyingglass",
                        showsChevron: false
                    )
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}

func sourceStaleDetail(
    _ failureDetail: String,
    lastUpdatedAt: Date?,
    prefix: String = "Last successful load was"
) -> String {
    guard let lastUpdatedAt else {
        return failureDetail
    }

    return "\(prefix) \(lastUpdatedAt.formatted(.dateTime.hour().minute())).\n\n\(failureDetail)"
}
