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
