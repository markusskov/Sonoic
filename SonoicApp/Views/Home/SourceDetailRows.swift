import SwiftUI

struct AppleMusicSourceHeader: View {
    let source: SonoicSource
    let authorizationState: SonoicAppleMusicAuthorizationState
    let serviceDetails: SonoicAppleMusicServiceDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Apple Music", systemImage: source.service.systemImage)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 10) {
                Text(authorizationState.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                AppleMusicStatusChips(
                    authorizationState: authorizationState,
                    serviceDetails: serviceDetails
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AppleMusicStatusChips: View {
    let authorizationState: SonoicAppleMusicAuthorizationState
    let serviceDetails: SonoicAppleMusicServiceDetails

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                AppleMusicStatusChip(
                    title: authorizationState.title,
                    systemImage: authorizationState.systemImage,
                    tint: authorizationState.allowsCatalogSearch ? .green : .secondary
                )

                AppleMusicStatusChip(
                    title: storefrontTitle,
                    systemImage: "globe",
                    tint: .secondary
                )

                AppleMusicStatusChip(
                    title: catalogPlaybackTitle,
                    systemImage: "music.note",
                    tint: .secondary
                )

                AppleMusicStatusChip(
                    title: cloudLibraryTitle,
                    systemImage: "icloud",
                    tint: .secondary
                )
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private var storefrontTitle: String {
        if serviceDetails.isLoading {
            return "Loading"
        }

        return serviceDetails.storefrontCountryCode ?? "Storefront"
    }

    private var catalogPlaybackTitle: String {
        switch serviceDetails.canPlayCatalogContent {
        case .some(true):
            "Catalog"
        case .some(false):
            "Preview Only"
        case .none:
            "Catalog"
        }
    }

    private var cloudLibraryTitle: String {
        switch serviceDetails.hasCloudLibraryEnabled {
        case .some(true):
            "Library"
        case .some(false):
            "No Library"
        case .none:
            "Library"
        }
    }
}

private struct AppleMusicStatusChip: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.45), in: Capsule())
    }
}

struct AppleMusicLibrarySection: View {
    @Environment(SonoicModel.self) private var model

    private let destinations = SonoicAppleMusicLibraryDestination.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Library",
                subtitle: "Your saved Apple Music playlists, artists, albums, and songs."
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
            subtitle: destination.subtitle,
            systemImage: destination.systemImage,
            badgeTitle: libraryBadgeTitle(for: state)
        )
    }

    private func libraryBadgeTitle(for state: SonoicAppleMusicLibraryState) -> String {
        switch state.status {
        case .idle:
            "Open"
        case .loading:
            "Loading"
        case .loaded:
            "\(state.items.count)"
        case .failed:
            "Error"
        }
    }
}

struct AppleMusicDiscoverySection: View {
    private let rows: [AppleMusicSourceNavigationRow.Model] = [
        .init(title: "Popular Recommendations", subtitle: "Editorial and listener-driven picks", systemImage: "sparkles", showsChevron: false),
        .init(title: "Categories", subtitle: "Browse moods, genres, and activity lanes", systemImage: "square.grid.2x2", showsChevron: false),
        .init(title: "Playlists Created for You", subtitle: "Personalized mixes when library auth expands", systemImage: "person.crop.circle.badge.checkmark", showsChevron: false),
        .init(title: "Apple Music Playlists", subtitle: "Curated playlists from Apple Music", systemImage: "music.note.list", showsChevron: false),
        .init(title: "New Releases", subtitle: "Fresh albums and singles by service", systemImage: "calendar.badge.plus", showsChevron: false),
        .init(title: "Radio Shows", subtitle: "Apple Music radio and hosted shows", systemImage: "dot.radiowaves.left.and.right", showsChevron: false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Browse",
                subtitle: "Catalog lanes for discovery, recommendations, and future Sonos-native starts."
            )

            RoomSurfaceCard {
                AppleMusicSourceRows(rows: rows)
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
        var badgeTitle = "Soon"
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

            Text(row.badgeTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.45), in: Capsule())

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

                Label(originTitle, systemImage: item.service.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    private var originTitle: String {
        switch item.origin {
        case .catalogSearch:
            "Catalog"
        case .favorite:
            "Favorite"
        case .recentPlay:
            "Recent Play"
        }
    }

    private func playTapped() {
        Task {
            await playAction()
        }
    }
}

struct SourceSearchSection: View {
    let serviceName: String
    @Binding var query: String
    let state: SonoicSourceSearchState
    let availabilityMessage: SourceSearchAvailabilityMessage?
    let selectItem: (SonoicSourceItem) -> Void
    let search: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Catalog",
                subtitle: "Search Apple Music metadata. Playback stays Sonos-native until a playable payload exists."
            )

            RoomSurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        SourceSearchField(
                            query: $query,
                            serviceName: serviceName,
                            submit: searchTapped
                        )

                        Button(action: searchTapped) {
                            if state.isSearching {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .disabled(!state.hasQuery || state.isSearching)
                        .accessibilityLabel("Search \(serviceName)")
                    }

                    if let availabilityMessage {
                        SourceSearchMessageRow(
                            title: availabilityMessage.title,
                            detail: availabilityMessage.detail,
                            systemImage: availabilityMessage.systemImage
                        )
                    } else if !state.hasQuery || state.status == .idle {
                        SourceSearchIdleRow(serviceName: serviceName)
                    } else if let failureDetail = state.failureDetail {
                        SourceSearchMessageRow(
                            title: "Search Failed",
                            detail: failureDetail,
                            systemImage: "exclamationmark.triangle"
                        )
                    } else if state.status == .loaded && state.items.isEmpty {
                        SourceSearchMessageRow(
                            title: "No Results",
                            detail: "Apple Music did not return catalog matches for this search.",
                            systemImage: "magnifyingglass"
                        )
                    } else {
                        ForEach(state.items) { item in
                            SourceItemRow(item: item) {
                                selectItem(item)
                            } playAction: {}
                        }
                    }
                }
            }
        }
    }

    private func searchTapped() {
        Task {
            await search()
        }
    }
}

struct SourceSearchAvailabilityMessage: Equatable {
    var title: String
    var detail: String
    var systemImage: String
}

private struct SourceSearchField: View {
    @Binding var query: String
    let serviceName: String
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("Search \(serviceName)", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .onSubmit(submit)

            if query.sonoicNonEmptyTrimmed != nil {
                Button(action: clearQuery) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.quaternary.opacity(0.35), in: Capsule())
        .frame(maxWidth: .infinity)
    }

    private func clearQuery() {
        query = ""
    }
}

private struct SourceSearchMessageRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            RoomSurfaceIconView(
                systemImage: systemImage,
                size: 44,
                cornerRadius: 14,
                font: .body.weight(.semibold)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }
}

private struct SourceSearchIdleRow: View {
    let serviceName: String

    var body: some View {
        HStack(spacing: 14) {
            RoomSurfaceIconView(
                systemImage: "music.magnifyingglass",
                size: 44,
                cornerRadius: 14,
                font: .body.weight(.semibold)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("\(serviceName) Search")
                    .font(.body.weight(.medium))

                Text("Enter a search term to preview catalog metadata")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }
}

struct SourceEmptyCard: View {
    let serviceName: String

    var body: some View {
        RoomSurfaceCard {
            Label("No \(serviceName) Items Yet", systemImage: "music.note.list")
                .font(.headline)

            Text("Favorites and recent plays from this source will appear here after Sonoic sees them on Sonos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct SourceCatalogPlaceholderCard: View {
    let serviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Catalog",
                subtitle: "Search and service browsing will connect here later."
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
