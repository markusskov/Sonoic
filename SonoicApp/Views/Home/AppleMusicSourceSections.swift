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
                        SourceNavigationRow(row: libraryRow(for: destination))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func libraryRow(
        for destination: SonoicAppleMusicLibraryDestination
    ) -> SourceNavigationRow.Model {
        let state = model.appleMusicLibraryState(for: destination)

        return SourceNavigationRow.Model(
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
                        SourceNavigationRow(row: browseRow(for: destination))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func browseRow(
        for destination: SonoicAppleMusicBrowseDestination
    ) -> SourceNavigationRow.Model {
        SourceNavigationRow.Model(
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
            SourceMessageCard(
                title: "Loading Library",
                detail: "Loading...",
                systemImage: "icloud.and.arrow.down"
            )
        } else if let failureDetail = state.failureDetail, state.items.isEmpty {
            SourceMessageCard(
                title: "Could Not Load Recently Added",
                detail: failureDetail,
                systemImage: "exclamationmark.triangle"
            )
        } else if state.status == .loaded && state.items.isEmpty {
            SourceMessageCard(
                title: "No Items",
                detail: "Nothing here yet.",
                systemImage: "music.note.list"
            )
        } else if state.status == .loaded || !state.items.isEmpty {
            if state.isLoading {
                SourceMessageCard(
                    title: "Refreshing",
                    detail: "Updating...",
                    systemImage: "arrow.clockwise"
                )
            }

            if let failureDetail = state.failureDetail {
                SourceMessageCard(
                    title: "Showing Cached Recently Added",
                    detail: sourceStaleDetail(failureDetail, lastUpdatedAt: state.lastUpdatedAt),
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
}

private struct AppleMusicRecentlyAddedCard: View {
    @Environment(SonoicModel.self) private var model
    let item: SonoicSourceItem
    @State private var actionFailure: SourceActionFailure?

    private var canPlay: Bool {
        model.canPlaySourceItem(item)
    }

    var body: some View {
        Group {
            if item.kind == .song && canPlay {
                Button {
                    Task {
                        await play()
                    }
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(item.title)")
            } else if item.kind != .song {
                NavigationLink {
                    SourceItemDetailView(item: item)
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .accessibilityLabel(item.title)
        .alert(item: $actionFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var cardContent: some View {
        SourceArtworkCaptionTile(
            title: item.title,
            subtitle: item.subtitle,
            artworkURL: item.artworkURL,
            artworkIdentifier: item.artworkIdentifier,
            artworkDimension: 154,
            width: 154,
            artworkCornerRadius: 18,
            spacing: 9
        )
        .contentShape(Rectangle())
    }

    private func play() async {
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
}
