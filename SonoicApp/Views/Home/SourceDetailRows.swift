import SwiftUI

struct SourceItemRow: View {
    let item: SonoicSourceItem
    let playAction: () async -> Void

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
        .padding(.vertical, 12)
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
    let search: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Catalog",
                subtitle: "Search will start here before service auth and Sonos-native playback arrive."
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
                    } else if !state.hasQuery {
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
                            SourceItemRow(item: item) {}
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

                Text("Catalog browsing is not connected yet")
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
