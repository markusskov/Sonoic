import SwiftUI

struct SearchView: View {
    @Environment(SonoicModel.self) private var model
    @State private var query = ""
    @State private var selectedServiceID = SonosServiceDescriptor.appleMusic.id

    private var services: [SonosServiceDescriptor] {
        orderedServices(model.homeSources.map(\.service) + SonosServiceCatalog.browsableServices)
    }

    private var selectedService: SonosServiceDescriptor {
        services.first { $0.id == selectedServiceID } ?? .appleMusic
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 28) {
                    SearchHeader()

                    SearchServicePicker(
                        services: services,
                        selectedServiceID: $selectedServiceID
                    )

                    SearchInputCard(
                        query: $query,
                        service: selectedService
                    )

                    SearchScopeSection(service: selectedService)

                    SearchComingSoonCard(service: selectedService)
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle("Search")
    }

    private func orderedServices(_ services: [SonosServiceDescriptor]) -> [SonosServiceDescriptor] {
        var seen = Set<String>()
        return services.filter { service in
            if seen.contains(service.id) {
                return false
            }

            seen.insert(service.id)
            return true
        }
    }
}

private struct SearchHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Search", systemImage: "magnifyingglass")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)

            Text("Find songs, artists, albums, and playlists across connected music services.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SearchServicePicker: View {
    let services: [SonosServiceDescriptor]
    @Binding var selectedServiceID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Service",
                subtitle: "Choose where Sonoic should search first."
            )

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

private struct SearchInputCard: View {
    @Binding var query: String
    let service: SonosServiceDescriptor

    var body: some View {
        RoomSurfaceCard {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Search \(service.name)", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)

                if query.sonoicNonEmptyTrimmed != nil {
                    Button(action: clearQuery) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
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

private struct SearchScopeSection: View {
    let service: SonosServiceDescriptor

    private let scopes: [(title: String, systemImage: String)] = [
        ("Songs", "music.note"),
        ("Artists", "music.mic"),
        ("Albums", "rectangle.stack"),
        ("Playlists", "music.note.list")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Find",
                subtitle: "These scopes will become filters as service search expands."
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(scopes, id: \.title) { scope in
                    SearchScopeCard(
                        title: scope.title,
                        systemImage: scope.systemImage,
                        service: service
                    )
                }
            }
        }
    }
}

private struct SearchScopeCard: View {
    let title: String
    let systemImage: String
    let service: SonosServiceDescriptor

    var body: some View {
        RoomSurfaceCard {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.pink)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(service.name)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SearchComingSoonCard: View {
    let service: SonosServiceDescriptor

    var body: some View {
        RoomSurfaceCard {
            Label("Search Shell Ready", systemImage: "sparkles")
                .font(.headline)

            Text("\(service.name) search will connect here after we decide the shared search result model and Sonos-native playback rules.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        SearchView()
            .environment(SonoicModel())
    }
}
