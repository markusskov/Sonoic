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
    let serviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Search"
            )

            RoomSurfaceCard {
                HStack(spacing: 14) {
                    RoomSurfaceIconView(
                        systemImage: "magnifyingglass",
                        size: 44,
                        cornerRadius: 14,
                        font: .body.weight(.semibold)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(serviceName) Search")
                            .font(.body.weight(.medium))

                        Text("Not connected yet")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
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
