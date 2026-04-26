import SwiftUI

struct AppleMusicItemCollectionView: View {
    let title: String
    let subtitle: String
    let items: [SonoicSourceItem]

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    RoomSurfaceCard {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                SourceItemNavigationRow(item: item)

                                if index < items.count - 1 {
                                    Divider()
                                        .padding(.leading, 76)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .miniPlayerContentInset()
        .scrollIndicators(.hidden)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        AppleMusicItemCollectionView(
            title: "Tracks",
            subtitle: "Apple Music metadata",
            items: [
                SonoicSourceItem.appleMusicMetadata(
                    id: "preview-song",
                    title: "Sweet Jane",
                    subtitle: "Garrett Kato",
                    artworkURL: nil,
                    kind: .song,
                    origin: .catalogSearch
                )
            ]
        )
        .environment(SonoicModel())
    }
}
