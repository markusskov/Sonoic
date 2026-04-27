import SwiftUI

struct QueueContentView: View {
    let model: SonoicModel
    let playQueueItem: (Int) async -> Void
    let deleteQueueItems: (IndexSet) async -> Void
    let moveQueueItems: (IndexSet, Int) async -> Void

    var body: some View {
        if !model.hasManualSonosHost {
            ContentUnavailableView {
                Label("No Room Selected", systemImage: "speaker.slash.fill")
            } description: {
                Text("Choose a discovered Sonos room before trying to inspect the active queue.")
            } actions: {
                Button("Open Rooms") {
                    model.selectedTab = .rooms
                }
            }
        } else {
            queueStateContent
        }
    }

    @ViewBuilder
    private var queueStateContent: some View {
        switch model.queueState {
        case .idle, .loading:
            ContentUnavailableView {
                Label("Loading Queue", systemImage: "arrow.clockwise")
            } description: {
                Text("Reading queue...")
            }
        case let .unavailable(detail):
            ContentUnavailableView {
                Label("No Active Queue", systemImage: "list.triangle")
            } description: {
                Text(detail)
            } actions: {
                Button("Refresh", action: retryTapped)
            }
        case let .failed(detail):
            ContentUnavailableView {
                Label("Couldn't Load Queue", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(detail)
            } actions: {
                Button("Try Again", action: retryTapped)
            }
        case let .loaded(snapshot):
            loadedQueueContent(snapshot)
        }
    }

    @ViewBuilder
    private func loadedQueueContent(_ snapshot: SonosQueueSnapshot) -> some View {
        if snapshot.items.isEmpty {
            ContentUnavailableView {
                Label("Queue Is Empty", systemImage: "music.note.list")
            } description: {
                Text("The current Sonos queue has no items right now.")
            }
        } else {
            QueueSnapshotList(
                snapshot: snapshot,
                nowPlaying: model.nowPlaying,
                canMutate: snapshot.supportsLocalMutation,
                playQueueItem: playQueueItem,
                deleteQueueItems: deleteQueueItems,
                moveQueueItems: moveQueueItems
            ) {
                await model.refreshQueue(showLoading: false)
            }
        }
    }

    private func retryTapped() {
        Task {
            await model.refreshQueue()
        }
    }
}
