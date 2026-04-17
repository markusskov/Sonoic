import SwiftUI

struct QueueView: View {
    @Environment(SonoicModel.self) private var model

    var body: some View {
        content
        .navigationTitle("Queue")
        .toolbar {
            if model.hasManualSonosHost {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await model.refreshQueue(showLoading: false)
                        }
                    } label: {
                        if model.isQueueRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isQueueRefreshing)
                }
            }
        }
        .task(id: model.queueRefreshContext) {
            await loadQueueForCurrentContext()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasManualSonosHost {
            ContentUnavailableView {
                Label("No Player Connected", systemImage: "speaker.slash.fill")
            } description: {
                Text("Connect a manual Sonos player in Settings before trying to inspect the active queue.")
            } actions: {
                Button("Open Settings") {
                    model.selectedTab = .settings
                }
            }
        } else {
            switch model.queueState {
            case .idle, .loading:
                ContentUnavailableView {
                    Label("Loading Queue", systemImage: "arrow.clockwise")
                } description: {
                    Text("Sonoic is reading the active Sonos queue from the selected room.")
                }
            case let .unavailable(detail):
                ContentUnavailableView {
                    Label("No Active Queue", systemImage: "list.triangle")
                } description: {
                    Text(detail)
                }
            case let .failed(detail):
                ContentUnavailableView {
                    Label("Couldn't Load Queue", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(detail)
                } actions: {
                    Button("Try Again") {
                        Task {
                            await model.refreshQueue()
                        }
                    }
                }
            case let .loaded(snapshot):
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
                        playQueueItem: playQueueItem
                    ) {
                        await model.refreshQueue(showLoading: false)
                    }
                }
            }
        }
    }

    private func loadQueueForCurrentContext() async {
        guard model.hasManualSonosHost else {
            return
        }

        await model.refreshQueue(showLoading: model.queueState.snapshot == nil)
    }

    private func playQueueItem(at position: Int) async {
        guard await model.playManualSonosQueueItem(at: position) else {
            return
        }

        await model.refreshQueue(showLoading: false)
    }
}

#Preview {
    NavigationStack {
        QueueView()
            .environment(SonoicModel())
    }
}
