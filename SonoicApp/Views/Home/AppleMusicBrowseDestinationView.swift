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
        VStack(alignment: .leading, spacing: 10) {
            Label(destination.title, systemImage: destination.systemImage)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)

            Text(destination.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading {
            AppleMusicBrowseMessageCard(
                title: "Loading \(destination.title)",
                detail: "Reading Apple Music catalog metadata.",
                systemImage: "icloud.and.arrow.down"
            )
        } else if let failureDetail = state.failureDetail {
            AppleMusicBrowseMessageCard(
                title: "Could Not Load \(destination.title)",
                detail: failureDetail,
                systemImage: "exclamationmark.triangle"
            )
        } else if !state.sections.isEmpty {
            ForEach(state.sections) { section in
                AppleMusicBrowseSectionView(section: section)
            }
        } else if !state.genres.isEmpty {
            AppleMusicBrowseGenreSection(genres: state.genres)
        } else {
            nextStepsCard
        }
    }

    private var nextStepsCard: some View {
        RoomSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                AppleMusicBrowseStatusRow(
                    title: "Show Apple Music items",
                    subtitle: "Use the matching catalog or personalized endpoint for this lane.",
                    systemImage: "checklist"
                )
                Divider()
                    .padding(.leading, 46)
                AppleMusicBrowseStatusRow(
                    title: "Resolve Sonos playback",
                    subtitle: "Map selected results to Sonos-native service payloads before enabling Play.",
                    systemImage: "speaker.wave.2"
                )
            }
        }
    }

    private func refreshTapped() {
        model.loadAppleMusicBrowseDestination(destination, force: true)
    }
}

private struct AppleMusicBrowseSectionView: View {
    let section: SonoicAppleMusicItemDetailSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: section.title,
                subtitle: section.subtitle ?? "Apple Music catalog metadata"
            )

            RoomSurfaceCard {
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

private struct AppleMusicBrowseGenreSection: View {
    let genres: [SonoicAppleMusicGenreItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Categories",
                subtitle: "Apple Music genres used by catalog charts."
            )

            RoomSurfaceCard {
                VStack(spacing: 0) {
                    ForEach(Array(genres.enumerated()), id: \.element.id) { index, genre in
                        AppleMusicBrowseGenreRow(genre: genre)

                        if index < genres.count - 1 {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
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
                .foregroundStyle(.pink)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(genre.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(genre.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

private struct AppleMusicBrowseMessageCard: View {
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

private struct AppleMusicBrowseStatusRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.pink)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppleMusicBrowseDestinationView(destination: .popularRecommendations)
    }
}
