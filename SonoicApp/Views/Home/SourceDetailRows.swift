import SwiftUI

struct SourceActionFailure: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
}

struct SourceNavigationRow: View {
    struct Model: Identifiable, Equatable {
        var title: String
        var subtitle: String?
        var systemImage: String
        var badgeTitle: String?
        var showsChevron = true

        var id: String {
            title
        }
    }

    let row: Model

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: row.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SonoicTheme.Colors.serviceAccent)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(SonoicTheme.Typography.listTitle)
                    .foregroundStyle(SonoicTheme.Colors.primary)
                    .lineLimit(1)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(SonoicTheme.Typography.listSubtitle)
                        .foregroundStyle(SonoicTheme.Colors.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let badgeTitle = row.badgeTitle {
                Text(badgeTitle)
                    .font(SonoicTheme.Typography.badge)
                    .foregroundStyle(SonoicTheme.Colors.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.45), in: Capsule())
            }

            if row.showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SonoicTheme.Colors.tertiary)
            }
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

struct SourceItemRow: View {
    let item: SonoicSourceItem
    let selectAction: () -> Void
    let playAction: () async -> Void

    private var shouldPlayOnRowTap: Bool {
        item.kind == .song && item.playbackCapability.canPlay
    }

    var body: some View {
        HStack(spacing: 14) {
            SourceItemMetadataRow(item: item)

            if shouldPlayOnRowTap {
                Button(action: selectAction) {
                    SourceItemOptionsIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options for \(item.title)")
            } else if item.playbackCapability.canPlay {
                Button(action: playTapped) {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(item.title)")
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: rowTapped)
    }

    private func rowTapped() {
        guard shouldPlayOnRowTap else {
            selectAction()
            return
        }

        playTapped()
    }

    private func playTapped() {
        Task {
            await playAction()
        }
    }
}

struct SourceItemNavigationRow: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem
    var playOverride: (() async -> Void)?
    var isCompact = false
    @State private var actionFailure: SourceActionFailure?

    private var canPlay: Bool {
        playOverride != nil || model.canPlaySourceItem(item)
    }

    private var shouldPlayOnRowTap: Bool {
        item.kind == .song && canPlay
    }

    private var canOpenDetail: Bool {
        item.kind != .song
    }

    private var isFavorited: Bool {
        favoriteObjectID != nil
    }

    private var favoriteObjectID: String? {
        model.sourceFavoriteObjectID(for: item)
    }

    private var hasAuxiliaryActions: Bool {
        canPlay || model.sourceAdapter(for: item).capabilities.supportsFavorites || item.externalURL != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            if shouldPlayOnRowTap {
                Button {
                    Task {
                        await play()
                    }
                } label: {
                    SourceItemMetadataRow(item: item, isCompact: isCompact)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(item.title)")
            } else if canOpenDetail {
                NavigationLink {
                    SourceItemDetailView(item: item)
                } label: {
                    SourceItemMetadataRow(item: item, isCompact: isCompact)
                }
                .buttonStyle(.plain)
            } else {
                SourceItemMetadataRow(item: item, isCompact: isCompact)
            }

            if shouldPlayOnRowTap || hasAuxiliaryActions {
                Menu {
                    Button {
                        Task {
                            await play()
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .disabled(!canPlay)

                    Button {
                        Task {
                            await toggleFavorite()
                        }
                    } label: {
                        Label(
                            isFavorited ? "Remove Favorite" : "Save to Favorites",
                            systemImage: isFavorited ? "heart.fill" : "heart"
                        )
                        .foregroundStyle(.primary)
                    }

                    if let externalURL = item.externalURL.flatMap(URL.init(string:)) {
                        ShareLink(item: externalURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    SourceItemOptionsIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options for \(item.title)")
            }

            if canOpenDetail && !shouldPlayOnRowTap {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, isCompact ? 8 : 12)
        .alert(item: $actionFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func play() async {
        if let playOverride {
            await playOverride()
            return
        }

        do {
            let didStart = try await model.playSourceItem(item)

            if !didStart {
                actionFailure = SourceActionFailure(
                    title: "Could Not Start",
                    detail: "Sonos could not start this item."
                )
            }
        } catch {
            actionFailure = SourceActionFailure(
                title: "Could Not Start",
                detail: error.localizedDescription
            )
        }
    }

    private func toggleFavorite() async {
        let wasFavorited = favoriteObjectID != nil

        do {
            _ = try await model.toggleSourceFavorite(for: item)
        } catch {
            actionFailure = SourceActionFailure(
                title: wasFavorited ? "Could Not Remove Favorite" : "Could Not Save Favorite",
                detail: error.localizedDescription
            )
        }
    }
}

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

private struct SourceItemMetadataRow: View {
    let item: SonoicSourceItem
    var isCompact = false

    private var artworkDimension: CGFloat {
        isCompact ? 52 : 58
    }

    var body: some View {
        HStack(spacing: isCompact ? 12 : 14) {
            HomeFavoriteArtworkView(
                artworkURL: item.artworkURL,
                artworkIdentifier: item.artworkIdentifier,
                maximumDisplayDimension: artworkDimension
            )
            .frame(width: artworkDimension, height: artworkDimension)

            VStack(alignment: .leading, spacing: isCompact ? 3 : 5) {
                Text(item.title)
                    .font(SonoicTheme.Typography.listTitle)
                    .foregroundStyle(SonoicTheme.Colors.primary)
                    .lineLimit(1)

                if let displaySubtitle {
                    Text(displaySubtitle)
                        .font(SonoicTheme.Typography.listSubtitle)
                        .foregroundStyle(SonoicTheme.Colors.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displaySubtitle: String? {
        guard let subtitle = item.subtitle else {
            return item.kind == .album ? "Album" : nil
        }

        guard item.kind == .album else {
            return subtitle
        }

        return "\(subtitle) • Album"
    }

}

private struct SourceItemOptionsIcon: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.body.weight(.semibold))
            .foregroundStyle(SonoicTheme.Colors.secondary)
            .frame(width: 44, height: 44)
    }
}
