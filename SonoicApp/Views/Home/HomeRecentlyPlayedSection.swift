import SwiftUI

struct HomeRecentlyPlayedSection: View {
    let items: [SonoicRecentPlayItem]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(items) { item in
                    HomeRecentPlayCard(item: item)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

private struct HomeRecentPlayCard: View {
    @Environment(SonoicModel.self) private var model
    let item: SonoicRecentPlayItem
    @State private var actionFailure: SourceActionFailure?

    private var sourceItem: SonoicSourceItem? {
        guard item.service != nil else {
            return nil
        }

        return SonoicSourceItem(recentPlay: item)
    }

    private var canPlaySourceItem: Bool {
        sourceItem.map(model.canPlaySourceItem) ?? false
    }

    var body: some View {
        Group {
            if let sourceItem, sourceItem.kind == .song, canPlaySourceItem {
                Button {
                    Task {
                        await play(sourceItem)
                    }
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(item.title)")
            } else if let sourceItem, sourceItem.kind != .song {
                NavigationLink {
                    SourceItemDetailView(item: sourceItem)
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .frame(width: 156, alignment: .leading)
        .alert(item: $actionFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var cardContent: some View {
        SourceArtworkCaptionTile(
            title: item.title,
            subtitle: item.subtitle ?? item.sourceName,
            badgeTitle: item.sourceName,
            badgeSystemImage: item.service?.systemImage ?? "music.note",
            artworkURL: item.artworkURL,
            artworkIdentifier: item.artworkIdentifier,
            artworkDimension: 156,
            width: 156,
            titleFont: .subheadline.weight(.semibold),
            subtitleFont: .caption,
            badgeFont: .caption2.weight(.medium)
        )
    }

    private func play(_ sourceItem: SonoicSourceItem) async {
        do {
            let didStart = try await model.playSourceItem(sourceItem)

            if !didStart {
                actionFailure = SourceActionFailure(
                    title: "Could Not Start",
                    detail: "Sonos could not start this item."
                )
            }
        } catch {
            actionFailure = SourceActionFailure(
                title: "Could Not Start",
                detail: error.localizedDescription
            )
        }
    }
}
