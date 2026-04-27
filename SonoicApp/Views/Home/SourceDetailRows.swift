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

            RoomSurfaceCard {
                VStack(spacing: 0) {
                    ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                        NavigationLink {
                            AppleMusicLibraryDestinationView(destination: destination)
                        } label: {
                            AppleMusicSourceNavigationRow(row: libraryRow(for: destination))
                        }
                        .buttonStyle(.plain)

                        if index < destinations.count - 1 {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
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
            RoomSurfaceCard(isInteractive: true) {
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

            RoomSurfaceCard {
                VStack(spacing: 0) {
                    ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                        NavigationLink {
                            AppleMusicBrowseDestinationView(destination: destination)
                        } label: {
                            AppleMusicSourceNavigationRow(row: browseRow(for: destination))
                        }
                        .buttonStyle(.plain)

                        if index < destinations.count - 1 {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
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
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 154, alignment: .leading)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
                .foregroundStyle(.pink)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let badgeTitle = row.badgeTitle {
                Text(badgeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.45), in: Capsule())
            }

            if row.showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
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

    var body: some View {
        HStack(spacing: 14) {
            rowContent
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: selectAction)
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
                    .lineLimit(2)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if item.playbackCapability.canPlay {
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

    private func playTapped() {
        Task {
            await playAction()
        }
    }
}

struct SourceItemNavigationRow: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem

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
        exactPlaybackCandidate != nil || generatedPlaybackCandidate != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                AppleMusicItemDetailView(item: item)
            } label: {
                SourceItemMetadataRow(item: item)
            }
            .buttonStyle(.plain)

            if canPlay {
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

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
    }

    private func play() async {
        if let exactPlaybackCandidate {
            _ = await model.playManualSonosPayload(exactPlaybackCandidate.payload)
            return
        }

        guard let generatedPlaybackCandidate,
              let payload = try? generatedPlaybackCandidate.preparedPlaybackPayload(for: item)
        else {
            return
        }

        _ = await model.playManualSonosPayload(payload)
    }
}

struct SourceGroupedItemRows: View {
    let items: [SonoicSourceItem]

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
        VStack(alignment: .leading, spacing: 18) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.kind.pluralTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    VStack(spacing: 0) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            SourceItemNavigationRow(item: item)

                            if index < section.items.count - 1 {
                                Divider()
                                    .padding(.leading, 76)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SourceItemSection: Identifiable {
    var kind: SonoicSourceItem.Kind
    var items: [SonoicSourceItem]

    var id: String {
        kind.rawValue
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

    var body: some View {
        HStack(spacing: 14) {
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
                    .lineLimit(2)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
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
