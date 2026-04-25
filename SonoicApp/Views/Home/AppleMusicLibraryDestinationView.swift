import SwiftUI

struct AppleMusicLibraryDestinationView: View {
    @Environment(SonoicModel.self) private var model
    @State private var state: SonoicAppleMusicLibraryState
    @State private var selectedItem: SonoicSourceItem?

    let destination: SonoicAppleMusicLibraryDestination

    init(destination: SonoicAppleMusicLibraryDestination) {
        self.destination = destination
        _state = State(initialValue: SonoicAppleMusicLibraryState(destination: destination))
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
            await loadIfNeeded()
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
        .sheet(item: $selectedItem) { item in
            SourceItemDetailSheet(item: item) {}
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
            AppleMusicLibraryMessageCard(
                title: "Loading \(destination.title)",
                detail: "Reading your Apple Music library metadata.",
                systemImage: "icloud.and.arrow.down"
            )
        } else if let failureDetail = state.failureDetail {
            AppleMusicLibraryMessageCard(
                title: "Could Not Load \(destination.title)",
                detail: failureDetail,
                systemImage: "exclamationmark.triangle"
            )
        } else if state.status == .loaded && state.items.isEmpty {
            AppleMusicLibraryMessageCard(
                title: "No \(destination.title)",
                detail: "Apple Music did not return saved \(destination.title.lowercased()) for this library.",
                systemImage: "music.note.list"
            )
        } else if state.status == .loaded {
            libraryItemsSection
        } else {
            AppleMusicLibraryMessageCard(
                title: "\(destination.title) Ready",
                detail: "Tap refresh to load this Apple Music library lane.",
                systemImage: destination.systemImage
            )
        }
    }

    private var libraryItemsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: destination.title,
                subtitle: "Apple Music library metadata. These are not Sonos-playable yet."
            )

            RoomSurfaceCard {
                VStack(spacing: 0) {
                    ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                        SourceItemRow(item: item) {
                            selectedItem = item
                        } playAction: {}

                        if index < state.items.count - 1 {
                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
            }
        }
    }

    private func refreshTapped() {
        Task {
            await load()
        }
    }

    private func loadIfNeeded() async {
        guard state.status == .idle else {
            return
        }

        await load()
    }

    private func load() async {
        if state.isLoading {
            return
        }

        guard destination.isImplemented else {
            state = SonoicAppleMusicLibraryState(
                destination: destination,
                status: .failed("\(destination.title) browsing is coming next.")
            )
            return
        }

        model.refreshAppleMusicAuthorizationState()
        guard model.appleMusicAuthorizationState.allowsCatalogSearch else {
            state = SonoicAppleMusicLibraryState(
                destination: destination,
                status: .failed(model.appleMusicAuthorizationState.detail)
            )
            return
        }

        if model.appleMusicServiceDetails.hasCloudLibraryEnabled == .some(false) {
            state = SonoicAppleMusicLibraryState(
                destination: destination,
                status: .failed("iCloud Music Library is not enabled for this Apple Music account.")
            )
            return
        }

        state = SonoicAppleMusicLibraryState(destination: destination, status: .loading)

        do {
            let items = try await fetchItems()
            state = SonoicAppleMusicLibraryState(
                destination: destination,
                items: items,
                status: .loaded
            )
        } catch {
            state = SonoicAppleMusicLibraryState(
                destination: destination,
                status: .failed(error.localizedDescription)
            )
        }
    }

    private func fetchItems() async throws -> [SonoicSourceItem] {
        switch destination {
        case .playlists:
            try await model.appleMusicCatalogSearchClient.fetchLibraryPlaylists()
        case .albums:
            try await model.appleMusicCatalogSearchClient.fetchLibraryAlbums()
        case .songs:
            try await model.appleMusicCatalogSearchClient.fetchLibrarySongs()
        case .artists:
            try await model.appleMusicCatalogSearchClient.fetchLibraryArtists()
        }
    }
}

private struct AppleMusicLibraryMessageCard: View {
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

#Preview {
    NavigationStack {
        AppleMusicLibraryDestinationView(destination: .albums)
            .environment(SonoicModel())
    }
}
