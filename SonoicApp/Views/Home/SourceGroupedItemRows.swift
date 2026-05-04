import SwiftUI

struct SourceGroupedItemRows: View {
    let items: [SonoicSourceItem]
    var showsSectionTitles = false
    var usesCompactCards = true
    var initialVisibleItemCount = 10
    var additionalVisibleItemCount = 10

    @State private var visibleItemCounts: [String: Int] = [:]

    private var sections: [SourceItemSection] {
        SonoicSourceItem.Kind.searchResultOrder.compactMap { kind in
            let sectionItems = items.filter { $0.kind == kind }

            guard !sectionItems.isEmpty else {
                return nil
            }

            return SourceItemSection(kind: kind, items: sectionItems)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SonoicTheme.Spacing.cardStack) {
            ForEach(sections) { section in
                Group {
                    if usesCompactCards {
                        SonoicListCard {
                            sectionContent(section)
                        }
                    } else {
                        RoomSurfaceCard {
                            sectionContent(section)
                        }
                    }
                }
            }
        }
        .onChange(of: items) { _, _ in
            visibleItemCounts = [:]
        }
    }

    @ViewBuilder
    private func sectionContent(_ section: SourceItemSection) -> some View {
        let visibleItems = visibleItems(for: section)

        VStack(alignment: .leading, spacing: showsSectionTitles ? 6 : 0) {
            if showsSectionTitles {
                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            SonoicListRows(visibleItems) { item, _ in
                SourceItemNavigationRow(item: item)
            }

            if visibleItems.count < section.items.count {
                SonoicListMoreButton {
                    showMoreItems(in: section)
                }
            }
        }
    }

    private func visibleItems(for section: SourceItemSection) -> [SonoicSourceItem] {
        Array(section.items.prefix(visibleItemCount(for: section)))
    }

    private func visibleItemCount(for section: SourceItemSection) -> Int {
        min(
            section.items.count,
            visibleItemCounts[section.id] ?? initialVisibleItemCount
        )
    }

    private func showMoreItems(in section: SourceItemSection) {
        visibleItemCounts[section.id] = min(
            section.items.count,
            visibleItemCount(for: section) + additionalVisibleItemCount
        )
    }
}

private struct SourceItemSection: Identifiable {
    var kind: SonoicSourceItem.Kind
    var items: [SonoicSourceItem]

    var id: String {
        kind.rawValue
    }

    var title: String {
        items.count == 1 ? kind.title : kind.pluralTitle
    }
}

private extension SonoicSourceItem.Kind {
    static let searchResultOrder: [SonoicSourceItem.Kind] = [
        .artist,
        .song,
        .album,
        .playlist,
        .station,
        .unknown
    ]

    var pluralTitle: String {
        switch self {
        case .album:
            "Albums"
        case .artist:
            "Artists"
        case .playlist:
            "Playlists"
        case .song:
            "Songs"
        case .station:
            "Stations"
        case .unknown:
            "Other"
        }
    }
}
