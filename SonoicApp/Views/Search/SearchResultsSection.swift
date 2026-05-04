import SwiftUI

struct SearchResultsSection: View {
    let session: SonoicSourceSearchSessionState
    let sources: [SonoicSource]
    let states: [String: SonoicSourceSearchState]
    let availabilityMessage: SearchMessage?
    let canRequestAuthorization: Bool
    let requestAuthorization: () -> Void
    let selectSource: (String?) -> Void
    let selectScope: (SonoicSourceSearchScope) -> Void

    private var visibleItems: [SonoicSourceItem] {
        session.visibleItems(in: states, sources: sources)
    }

    private var isSearching: Bool {
        session.isSearching(in: states, sources: sources)
    }

    private var failureDetail: String? {
        session.failureDetail(in: states, sources: sources)
    }

    var body: some View {
        if shouldShowResults {
            VStack(alignment: .leading, spacing: 14) {
                if shouldShowFilters {
                    SearchSourceFilterRow(
                        sources: sources,
                        selectedServiceID: session.selectedServiceID,
                        select: selectSource
                    )

                    SearchScopeFilterRow(
                        selectedScope: session.scope,
                        select: selectScope
                    )
                }

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
                } else if let failureDetail {
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

                if isSearching && visibleItems.isEmpty {
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
                } else if session.hasLoadedEmptyResults(in: states, sources: sources) {
                    RoomSurfaceCard {
                        SearchMessageRow(
                            message: SearchMessage(
                                title: "No Results",
                                detail: "No matches.",
                                systemImage: "magnifyingglass"
                            )
                        )
                    }
                } else if !visibleItems.isEmpty {
                    SourceGroupedItemRows(items: visibleItems)
                }
            }
        }
    }

    private var shouldShowResults: Bool {
        availabilityMessage != nil
            || (
                session.hasActiveSubmittedQuery && (
                    isSearching
                        || failureDetail != nil
                        || session.hasLoadedEmptyResults(in: states, sources: sources)
                        || !visibleItems.isEmpty
                )
            )
    }

    private var shouldShowFilters: Bool {
        session.hasActiveSubmittedQuery && (
            isSearching
                || session.hasLoadedEmptyResults(in: states, sources: sources)
                || !visibleItems.isEmpty
        )
    }

    private var latestUpdatedAt: Date? {
        session.sourceIDs(from: sources)
            .compactMap { states[$0]?.lastUpdatedAt }
            .max()
    }

    private func staleDetail(_ failureDetail: String) -> String {
        guard !visibleItems.isEmpty,
              let lastUpdatedAt = latestUpdatedAt
        else {
            return failureDetail
        }

        return sourceStaleDetail(
            failureDetail,
            lastUpdatedAt: lastUpdatedAt,
            prefix: "Showing previous results from"
        )
    }
}

private struct SearchSourceFilterRow: View {
    let sources: [SonoicSource]
    let selectedServiceID: String?
    let select: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                if sources.count > 1 {
                    SearchFilterChip(
                        title: "All",
                        systemImage: "square.grid.2x2",
                        isSelected: selectedServiceID == nil
                    ) {
                        select(nil)
                    }
                }

                ForEach(sources) { source in
                    SearchFilterChip(
                        title: sources.count == 1 ? source.service.name : nil,
                        systemImage: source.service.systemImage,
                        isSelected: selectedServiceID == source.service.id || sources.count == 1
                    ) {
                        select(source.service.id)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SearchScopeFilterRow: View {
    let selectedScope: SonoicSourceSearchScope
    let select: (SonoicSourceSearchScope) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(SonoicSourceSearchScope.allCases) { scope in
                    SearchFilterChip(
                        title: scope.title,
                        systemImage: nil,
                        isSelected: selectedScope == scope
                    ) {
                        select(scope)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SearchFilterChip: View {
    let title: String?
    let systemImage: String?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }

                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(isSelected ? SonoicTheme.Colors.primary : SonoicTheme.Colors.secondary)
            .padding(.horizontal, title == nil ? 12 : 14)
            .padding(.vertical, 9)
            .frame(minWidth: title == nil ? 44 : nil)
            .frame(minHeight: 40)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.interactive() : .regular,
            in: .capsule
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
