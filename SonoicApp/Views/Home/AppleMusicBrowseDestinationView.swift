import SwiftUI

struct AppleMusicBrowseDestinationView: View {
    @Environment(SonoicModel.self) private var model

    let destination: SonoicAppleMusicBrowseDestination

    private var state: SonoicAppleMusicBrowseState {
        model.appleMusicBrowseState(for: destination)
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    content
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle(destination.title)
        .task(id: destination.id) {
            model.loadAppleMusicBrowseDestination(destination)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: refreshTapped) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(state.isLoading)
                .accessibilityLabel("Refresh \(destination.title)")
            }
        }
        .refreshable {
            refreshTapped()
        }
    }

    private var header: some View {
        Label(destination.title, systemImage: destination.systemImage)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading && state.sections.isEmpty && state.genres.isEmpty {
            SourceMessageCard(
                title: "Loading \(destination.title)",
                systemImage: "icloud.and.arrow.down"
            )
        } else if let failureDetail = state.failureDetail, state.sections.isEmpty && state.genres.isEmpty {
            SourceMessageCard(
                title: "Could Not Load \(destination.title)",
                detail: failureDetail,
                systemImage: "exclamationmark.triangle"
            )
        } else if !state.sections.isEmpty {
            if state.isLoading {
                SourceMessageCard(
                    title: "Refreshing",
                    systemImage: "arrow.clockwise"
                )
            }

            if let failureDetail = state.failureDetail {
                SourceMessageCard(
                    title: "Showing Cached \(destination.title)",
                    detail: sourceStaleDetail(failureDetail, lastUpdatedAt: state.lastUpdatedAt),
                    systemImage: "exclamationmark.triangle"
                )
            }

            ForEach(state.sections) { section in
                AppleMusicBrowseSectionView(section: section)
            }
        } else if !state.genres.isEmpty {
            if state.isLoading {
                SourceMessageCard(
                    title: "Refreshing Categories",
                    systemImage: "arrow.clockwise"
                )
            }

            if let failureDetail = state.failureDetail {
                SourceMessageCard(
                    title: "Showing Cached Categories",
                    detail: sourceStaleDetail(failureDetail, lastUpdatedAt: state.lastUpdatedAt),
                    systemImage: "exclamationmark.triangle"
                )
            }

            AppleMusicBrowseGenreSection(genres: state.genres)
        } else {
            SourceMessageCard(
                title: "No Items",
                systemImage: destination.systemImage
            )
        }
    }

    private func refreshTapped() {
        model.loadAppleMusicBrowseDestination(destination, force: true)
    }

}

private struct AppleMusicBrowseSectionView: View {
    let section: SonoicSourceItemDetailSection
    @State private var visibleItemCount = 10

    private let visibleItemIncrement = 10

    private var previewItems: [SonoicSourceItem] {
        Array(section.items.prefix(visibleItemCount))
    }

    private var showsMoreButton: Bool {
        section.items.count > previewItems.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: section.title,
                subtitle: section.subtitle
            )

            SonoicListCard {
                SonoicListRows(previewItems) { item, _ in
                    SourceItemNavigationRow(item: item)
                }

                if showsMoreButton {
                    SonoicListMoreButton(action: showMoreItems)
                }
            }
        }
        .onChange(of: section.items) { _, _ in
            visibleItemCount = 10
        }
    }

    private func showMoreItems() {
        visibleItemCount = min(
            section.items.count,
            visibleItemCount + visibleItemIncrement
        )
    }
}

private struct AppleMusicBrowseGenreSection: View {
    let genres: [SonoicAppleMusicGenreItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Categories"
            )

            SonoicListCard {
                SonoicListRows(
                    genres,
                    dividerLeadingPadding: SonoicTheme.Layout.iconDividerLeading
                ) { genre, _ in
                    AppleMusicBrowseGenreRow(genre: genre)
                }
            }
        }
    }
}

private struct AppleMusicBrowseGenreRow: View {
    let genre: SonoicAppleMusicGenreItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.body.weight(.semibold))
                .foregroundStyle(SonoicTheme.Colors.serviceAccent)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(genre.title)
                    .font(SonoicTheme.Typography.sectionTitle)
                    .foregroundStyle(SonoicTheme.Colors.primary)

                Text(genre.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(SonoicTheme.Colors.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        AppleMusicBrowseDestinationView(destination: .popularRecommendations)
    }
}
