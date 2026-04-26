import SwiftUI

struct SearchHeader: View {
    var body: some View {
        Label("Search", systemImage: "magnifyingglass")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
    let service: SonosServiceDescriptor
    let state: SonoicSourceSearchState
    let supportsCatalogSearch: Bool
    let submit: () -> Void

    var body: some View {
        RoomSurfaceCard {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Search \(service.name)", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .onSubmit(submit)

                if query.sonoicNonEmptyTrimmed != nil {
                    Button(action: clearQuery) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }

                Button(action: submit) {
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
                .disabled(!supportsCatalogSearch || !state.hasQuery || state.isSearching)
                .accessibilityLabel("Search \(service.name)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(.quaternary.opacity(0.35), in: Capsule())
        }
    }

    private func clearQuery() {
        query = ""
    }
}

struct SearchRecentQueriesSection: View {
    let service: SonosServiceDescriptor
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

                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(recentSearches) { recentSearch in
                            Button {
                                select(recentSearch)
                            } label: {
                                Label(recentSearch.query, systemImage: "clock")
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                            .accessibilityLabel("Search \(recentSearch.query)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct SearchResultsSection: View {
    let service: SonosServiceDescriptor
    let state: SonoicSourceSearchState
    let availabilityMessage: SearchMessage?
    let canRequestAuthorization: Bool
    let requestAuthorization: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(title: "Results")

            RoomSurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    if let availabilityMessage {
                        SearchMessageRow(message: availabilityMessage)

                        if canRequestAuthorization {
                            Button(action: requestAuthorization) {
                                Label("Authorize Apple Music", systemImage: "person.crop.circle.badge.checkmark")
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                        }
                    } else if !state.hasQuery || state.status == .idle {
                        SearchMessageRow(
                            message: SearchMessage(
                                title: "\(service.name)",
                                detail: "Search the catalog.",
                                systemImage: "music.magnifyingglass"
                            )
                        )
                    } else if let failureDetail = state.failureDetail {
                        SearchMessageRow(
                            message: SearchMessage(
                                title: "Search Failed",
                                detail: staleDetail(failureDetail),
                                systemImage: "exclamationmark.triangle"
                            )
                        )
                    }

                    if state.status == .loaded && state.items.isEmpty {
                        SearchMessageRow(
                            message: SearchMessage(
                                title: "No Results",
                                detail: "No matches.",
                                systemImage: "magnifyingglass"
                            )
                        )
                    } else if !state.items.isEmpty {
                        SourceGroupedItemRows(items: state.items)
                    }
                }
            }
        }
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

struct SearchComingSoonCard: View {
    let service: SonosServiceDescriptor

    var body: some View {
        RoomSurfaceCard {
            Label(service.name, systemImage: service.systemImage)
                .font(.headline)

            Text("Coming later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
