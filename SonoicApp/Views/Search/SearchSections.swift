import SwiftUI

struct SearchServicePicker: View {
    let services: [SonosServiceDescriptor]
    @Binding var selectedServiceID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(title: "Service")

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(services) { service in
                        SearchServiceChip(
                            service: service,
                            isSelected: selectedServiceID == service.id
                        ) {
                            selectedServiceID = service.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct SearchServiceChip: View {
    let service: SonosServiceDescriptor
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Label(service.name, systemImage: service.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 42)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.interactive() : .regular,
            in: .capsule
        )
        .accessibilityLabel("Search \(service.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SearchInputCard: View {
    @Binding var query: String
    @Binding var isFocused: Bool
    let service: SonosServiceDescriptor
    let state: SonoicSourceSearchState
    let supportsCatalogSearch: Bool
    let submit: () -> Void
    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Search \(service.name)", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .focused($fieldIsFocused)
                    .onSubmit(submit)

                submitButton
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.38), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(fieldIsFocused ? Color.accentColor.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1)
            }

            if fieldIsFocused || query.sonoicNonEmptyTrimmed != nil {
                Button(action: clearQuery) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Clear search")
            }
        }
        .onChange(of: fieldIsFocused) { _, newValue in
            isFocused = newValue
        }
        .onChange(of: isFocused) { _, newValue in
            if !newValue {
                fieldIsFocused = false
            }
        }
    }

    @ViewBuilder
    private var submitButton: some View {
        if state.isSearching {
            ProgressView()
                .controlSize(.small)
                .frame(width: 22, height: 22)
        } else if supportsCatalogSearch && state.hasQuery {
            Button(action: submit) {
                Image(systemName: "arrow.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Search \(service.name)")
        }
    }

    private func clearQuery() {
        query = ""
    }
}

struct SearchRecentQueriesSection: View {
    let recentSearches: [SonoicRecentSourceSearch]
    let select: (SonoicRecentSourceSearch) -> Void
    let clear: () -> Void

    var body: some View {
        if !recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    HomeSectionHeader(
                        title: "Recent"
                    )

                    Spacer(minLength: 0)

                    Button("Clear", action: clear)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                SonoicListCard {
                    SonoicListRows(
                        Array(recentSearches.prefix(5)),
                        dividerLeadingPadding: SonoicTheme.Layout.navigationDividerLeading
                    ) { recentSearch, _ in
                        Button {
                            select(recentSearch)
                        } label: {
                            SearchRecentQueryRow(recentSearch: recentSearch)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Search \(recentSearch.query)")
                    }
                }
            }
        }
    }
}

private struct SearchRecentQueryRow: View {
    let recentSearch: SonoicRecentSourceSearch

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)

            Text(recentSearch.query)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

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

struct SearchResultsSection: View {
    let state: SonoicSourceSearchState
    let availabilityMessage: SearchMessage?
    let canRequestAuthorization: Bool
    let requestAuthorization: () -> Void

    var body: some View {
        if shouldShowResults {
            VStack(alignment: .leading, spacing: 14) {
                if let availabilityMessage {
                    RoomSurfaceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            SearchMessageRow(message: availabilityMessage)

                            if canRequestAuthorization {
                                Button(action: requestAuthorization) {
                                    Label("Connect Apple Music", systemImage: "person.crop.circle.badge.checkmark")
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                            }
                        }
                    }
                } else if let failureDetail = state.failureDetail {
                    RoomSurfaceCard {
                        SearchMessageRow(
                            message: SearchMessage(
                                title: "Search Failed",
                                detail: staleDetail(failureDetail),
                                systemImage: "exclamationmark.triangle"
                            )
                        )
                    }
                }

                if state.isSearching && state.items.isEmpty {
                    RoomSurfaceCard {
                        HStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 44, height: 44)

                            Text("Searching")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)
                        }
                    }
                } else if state.status == .loaded && state.items.isEmpty {
                    RoomSurfaceCard {
                        SearchMessageRow(
                            message: SearchMessage(
                                title: "No Results",
                                detail: "No matches.",
                                systemImage: "magnifyingglass"
                            )
                        )
                    }
                } else if !state.items.isEmpty {
                    SourceGroupedItemRows(items: state.items)
                }
            }
        }
    }

    private var shouldShowResults: Bool {
        availabilityMessage != nil
            || state.isSearching
            || state.failureDetail != nil
            || (state.status == .loaded && state.hasQuery)
            || !state.items.isEmpty
    }

    private func staleDetail(_ failureDetail: String) -> String {
        guard !state.items.isEmpty,
              let lastUpdatedAt = state.lastUpdatedAt
        else {
            return failureDetail
        }

        return "Showing previous results from \(lastUpdatedAt.formatted(.dateTime.hour().minute())).\n\n\(failureDetail)"
    }
}

struct SearchMessage: Equatable {
    var title: String
    var detail: String
    var systemImage: String
}

private struct SearchMessageRow: View {
    let message: SearchMessage

    var body: some View {
        HStack(spacing: 14) {
            RoomSurfaceIconView(
                systemImage: message.systemImage,
                size: 44,
                cornerRadius: 14,
                font: .body.weight(.semibold)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.body.weight(.medium))

                Text(message.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }
}
