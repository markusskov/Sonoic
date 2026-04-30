import SwiftUI

struct AppleMusicSourceHeader: View {
    let source: SonoicSource
    let authorizationState: SonoicAppleMusicAuthorizationState
    let requestAuthorization: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Apple Music", systemImage: source.service.systemImage)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if !authorizationState.allowsCatalogSearch {
                VStack(alignment: .leading, spacing: 10) {
                    Text(authorizationState.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if authorizationState.canRequestAuthorization {
                        Button(action: requestAuthorization) {
                            Label("Connect Apple Music", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                    }
                }
            } else if authorizationState.canRequestAuthorization {
                Button(action: requestAuthorization) {
                    Label("Connect Apple Music", systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppleMusicLibrarySection: View {
    @Environment(SonoicModel.self) private var model

    private let destinations = SonoicAppleMusicLibraryDestination.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Library"
            )

            SonoicListCard {
                SonoicListRows(
                    destinations,
                    dividerLeadingPadding: SonoicTheme.Layout.navigationDividerLeading
                ) { destination, _ in
                    NavigationLink {
                        AppleMusicLibraryDestinationView(destination: destination)
                    } label: {
                        AppleMusicSourceNavigationRow(row: libraryRow(for: destination))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func libraryRow(
        for destination: SonoicAppleMusicLibraryDestination
    ) -> AppleMusicSourceNavigationRow.Model {
        let state = model.appleMusicLibraryState(for: destination)

        return AppleMusicSourceNavigationRow.Model(
            title: destination.title,
            systemImage: destination.systemImage,
            badgeTitle: libraryBadgeTitle(for: state)
        )
    }

    private func libraryBadgeTitle(for state: SonoicAppleMusicLibraryState) -> String? {
        switch state.status {
        case .idle:
            nil
        case .loading:
            "Loading"
        case .loaded:
            state.items.isEmpty ? nil : "\(state.items.count)"
        case .failed:
            "Error"
        }
    }
}

struct AppleMusicSearchEntrySection: View {
    let openSearch: () -> Void

    var body: some View {
        Button(action: openSearch) {
            SonoicListCard(isInteractive: true) {
                HStack(spacing: 14) {
                    RoomSurfaceIconView(
                        systemImage: "magnifyingglass",
                        size: 44,
                        cornerRadius: 14,
                        font: .body.weight(.semibold)
                    )

                    Text("Search Apple Music")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search Apple Music")
    }
}

struct AppleMusicDiscoverySection: View {
    @Environment(SonoicModel.self) private var model

    private let destinations: [SonoicAppleMusicBrowseDestination] = [
        .popularRecommendations,
        .categories,
        .playlistsForYou,
        .appleMusicPlaylists,
        .radioShows
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Browse"
            )

            SonoicListCard {
                SonoicListRows(
                    destinations,
                    dividerLeadingPadding: SonoicTheme.Layout.navigationDividerLeading
                ) { destination, _ in
                    NavigationLink {
                        AppleMusicBrowseDestinationView(destination: destination)
                    } label: {
                        AppleMusicSourceNavigationRow(row: browseRow(for: destination))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func browseRow(
        for destination: SonoicAppleMusicBrowseDestination
    ) -> AppleMusicSourceNavigationRow.Model {
        AppleMusicSourceNavigationRow.Model(
            title: destination.title,
            systemImage: destination.systemImage,
            badgeTitle: browseBadgeTitle(for: model.appleMusicBrowseState(for: destination))
        )
    }

    private func browseBadgeTitle(for state: SonoicAppleMusicBrowseState) -> String? {
        switch state.status {
        case .idle:
            return nil
        case .loading:
            return "Loading"
        case .loaded:
            let count = state.sections.reduce(state.genres.count) { total, section in
                total + section.items.count
            }
            return count > 0 ? "\(count)" : nil
        case .failed:
            return "Error"
        }
    }
}

struct AppleMusicRecentlyAddedSection: View {
    @Environment(SonoicModel.self) private var model

    private var state: SonoicAppleMusicRecentlyAddedState {
        model.appleMusicRecentlyAddedState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Recently Added"
            )

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading && state.items.isEmpty {
            AppleMusicRecentlyAddedMessageRow(
                title: "Loading Library",
                detail: "Loading...",
                systemImage: "icloud.and.arrow.down"
            )
        } else if let failureDetail = state.failureDetail, state.items.isEmpty {
            AppleMusicRecentlyAddedMessageRow(
                title: "Could Not Load Recently Added",
                detail: failureDetail,
                systemImage: "exclamationmark.triangle"
            )
        } else if state.status == .loaded && state.items.isEmpty {
            AppleMusicRecentlyAddedMessageRow(
                title: "No Items",
                detail: "Nothing here yet.",
                systemImage: "music.note.list"
            )
        } else if state.status == .loaded || !state.items.isEmpty {
            if state.isLoading {
                AppleMusicRecentlyAddedMessageRow(
                    title: "Refreshing",
                    detail: "Updating...",
                    systemImage: "arrow.clockwise"
                )
            }

            if let failureDetail = state.failureDetail {
                AppleMusicRecentlyAddedMessageRow(
                    title: "Showing Cached Recently Added",
                    detail: staleDetail(failureDetail),
                    systemImage: "exclamationmark.triangle"
                )
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(state.items) { item in
                        AppleMusicRecentlyAddedCard(item: item)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    private func staleDetail(_ failureDetail: String) -> String {
        guard let lastUpdatedAt = state.lastUpdatedAt else {
            return failureDetail
        }

        return "Last successful load was \(lastUpdatedAt.formatted(.dateTime.hour().minute())).\n\n\(failureDetail)"
    }
}

private struct AppleMusicRecentlyAddedCard: View {
    let item: SonoicSourceItem

    var body: some View {
        NavigationLink {
            AppleMusicItemDetailView(item: item)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HomeFavoriteArtworkView(
                    artworkURL: item.artworkURL,
                    artworkIdentifier: item.artworkIdentifier,
                    maximumDisplayDimension: 160
                )
                .frame(width: 154, height: 154)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .frame(width: 154, alignment: .leading)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .frame(width: 154, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }
}

private struct AppleMusicRecentlyAddedMessageRow: View {
    let title: String
    let detail: String
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

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct AppleMusicSourceRows: View {
    let rows: [AppleMusicSourceNavigationRow.Model]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                AppleMusicSourceNavigationRow(row: row)

                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 58)
                }
            }
        }
    }
}

private struct AppleMusicSourceNavigationRow: View {
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
            rowContent
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: rowTapped)
    }

    private var rowContent: some View {
        Group {
            HomeFavoriteArtworkView(
                artworkURL: item.artworkURL,
                artworkIdentifier: item.artworkIdentifier,
                maximumDisplayDimension: 58
            )
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if shouldPlayOnRowTap {
                Button(action: selectAction) {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
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
    @State private var actionFailure: SourceItemActionFailure?
    @State private var localFavoriteObjectID: String?

    private var exactPlaybackCandidate: SonoicSonosPlaybackCandidate? {
        model.appleMusicExactPlaybackCandidate(for: item)
    }

    private var generatedPlaybackCandidate: SonoicAppleMusicGeneratedPayloadCandidate? {
        guard exactPlaybackCandidate == nil else {
            return nil
        }

        return model.appleMusicGeneratedPlaybackCandidate(for: item)
    }

    private var canPlay: Bool {
        playOverride != nil
            || exactPlaybackCandidate != nil
            || generatedPlaybackCandidate != nil
            || nativePlaybackPayload != nil
    }

    private var shouldPlayOnRowTap: Bool {
        item.kind == .song && canPlay
    }

    private var isFavorited: Bool {
        favoriteObjectID != nil
    }

    private var favoriteObjectID: String? {
        localFavoriteObjectID ?? exactPlaybackCandidate?.verifiedFavoriteObjectID
    }

    private var nativePlaybackPayload: SonosPlayablePayload? {
        if case let .sonosNative(payload) = item.playbackCapability {
            payload
        } else {
            nil
        }
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
            } else {
                NavigationLink {
                    AppleMusicItemDetailView(item: item)
                } label: {
                    SourceItemMetadataRow(item: item, isCompact: isCompact)
                }
                .buttonStyle(.plain)
            }

            if shouldPlayOnRowTap {
                Menu {
                    Button {
                        Task {
                            await play()
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }

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
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options for \(item.title)")
            } else if canPlay {
                Button {
                    Task {
                        await play()
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(item.title)")
            }

            if !shouldPlayOnRowTap {
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

        if let exactPlaybackCandidate {
            _ = await model.playManualSonosPayload(exactPlaybackCandidate.payload)
            return
        }

        guard let generatedPlaybackCandidate,
              let payload = try? generatedPlaybackCandidate.preparedPlaybackPayload(for: item)
        else {
            if let nativePlaybackPayload {
                _ = await model.playManualSonosPayload(nativePlaybackPayload)
            }

            return
        }

        _ = await model.playManualSonosPayload(payload)
    }

    private func toggleFavorite() async {
        if let favoriteObjectID {
            do {
                try await model.removeSonosFavorite(objectID: favoriteObjectID)
                localFavoriteObjectID = nil
            } catch {
                actionFailure = SourceItemActionFailure(
                    title: "Could Not Remove Favorite",
                    detail: error.localizedDescription
                )
            }

            return
        }

        guard let payload = favoritePlaybackPayload()
        else {
            actionFailure = SourceItemActionFailure(
                title: "Could Not Save Favorite",
                detail: "This song does not have a Sonos favorite payload yet."
            )
            return
        }

        do {
            localFavoriteObjectID = try await model.addSonosFavorite(payload)
        } catch {
            actionFailure = SourceItemActionFailure(
                title: "Could Not Save Favorite",
                detail: error.localizedDescription
            )
        }
    }

    private func favoritePlaybackPayload() -> SonosPlayablePayload? {
        if let generatedPlaybackCandidate = model.appleMusicGeneratedPlaybackCandidate(for: item) {
            return try? generatedPlaybackCandidate.preparedPlaybackPayload(for: item)
        }

        guard exactPlaybackCandidate?.verifiedFavoriteObjectID != nil else {
            return nil
        }

        return exactPlaybackCandidate?.payload
    }
}

private struct SourceItemActionFailure: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
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
