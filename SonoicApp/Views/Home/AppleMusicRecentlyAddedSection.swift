import SwiftUI

struct AppleMusicRecentlyAddedSection: View {
    @Environment(SonoicModel.self) private var model

    private var state: SonoicAppleMusicRecentlyAddedState {
        model.appleMusicRecentlyAddedState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "Recently Added"
            )

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading && state.items.isEmpty {
            SourceMessageCard(
                title: "Loading Library",
                systemImage: "icloud.and.arrow.down"
            )
        } else if let failureDetail = state.failureDetail, state.items.isEmpty {
            SourceMessageCard(
                title: "Could Not Load Recently Added",
                detail: failureDetail,
                systemImage: "exclamationmark.triangle"
            )
        } else if state.status == .loaded && state.items.isEmpty {
            SourceMessageCard(
                title: "No Items",
                systemImage: "music.note.list"
            )
        } else if state.status == .loaded || !state.items.isEmpty {
            if state.isLoading {
                SourceMessageCard(
                    title: "Refreshing",
                    systemImage: "arrow.clockwise"
                )
            }

            if let failureDetail = state.failureDetail {
                SourceMessageCard(
                    title: "Showing Cached Recently Added",
                    detail: sourceStaleDetail(failureDetail, lastUpdatedAt: state.lastUpdatedAt),
                    systemImage: "exclamationmark.triangle"
                )
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(state.items) { item in
                        AppleMusicRecentlyAddedCard(item: item)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

private struct AppleMusicRecentlyAddedCard: View {
    @Environment(SonoicModel.self) private var model

    let item: SonoicSourceItem
    @State private var actionFailure: SourceActionFailure?

    private var canPlay: Bool {
        model.canPlaySourceItem(item)
    }

    var body: some View {
        Group {
            if item.kind == .song && canPlay {
                Button {
                    Task {
                        await play()
                    }
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(item.title)")
            } else if item.kind != .song {
                NavigationLink {
                    SourceItemDetailView(item: item)
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
        .accessibilityLabel(item.title)
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
            subtitle: item.subtitle,
            artworkURL: item.artworkURL,
            artworkIdentifier: item.artworkIdentifier,
            artworkDimension: 154,
            width: 154,
            artworkCornerRadius: 18,
            spacing: 9
        )
        .contentShape(Rectangle())
    }

    private func play() async {
        do {
            let didStart = try await model.playSourceItem(item)

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
