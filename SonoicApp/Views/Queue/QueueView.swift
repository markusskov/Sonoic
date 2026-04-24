import SwiftUI

struct QueueView: View {
    @Environment(\.editMode) private var editMode
    @Environment(SonoicModel.self) private var model
    @State private var isClearQueueConfirmationPresented = false
    private static let autoRefreshInterval: Duration = .seconds(8)

    var body: some View {
        content
        .miniPlayerContentInset()
        .navigationTitle("Queue")
        .toolbar {
            if canEditQueue {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(isQueueInteractionDisabled)
                }
            }

            if model.hasManualSonosHost {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        isClearQueueConfirmationPresented = true
                    } label: {
                        if model.isQueueClearing {
                            ProgressView()
                        } else {
                            Image(systemName: "trash")
                        }
                    }
                    .disabled(isClearQueueDisabled)
                    .accessibilityLabel("Clear Queue")

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
                    .disabled(isQueueInteractionDisabled || isEditingQueue)
                    .accessibilityLabel("Refresh Queue")
                }
            }
        }
        .alert(
            "Clear Queue?",
            isPresented: $isClearQueueConfirmationPresented,
        ) {
            Button("Clear Queue", role: .destructive) {
                Task {
                    await model.clearQueue()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every item from the active Sonos queue.")
        }
        .alert(
            "Couldn't Update Queue",
            isPresented: Binding(
                get: {
                    model.queueOperationErrorDetail != nil
                },
                set: { isPresented in
                    if !isPresented {
                        model.queueOperationErrorDetail = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.queueOperationErrorDetail ?? "")
        }
        .task(id: model.queueRefreshContext) {
            await loadQueueForCurrentContext()
        }
        .task(id: queueAutoRefreshLoopKey) {
            await autoRefreshQueueWhileVisible()
        }
    }

    @ViewBuilder
    private var content: some View {
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
                        playQueueItem: playQueueItem,
                        deleteQueueItems: deleteQueueItems,
                        moveQueueItems: moveQueueItems
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
        guard !isQueueInteractionDisabled else {
            return
        }

        guard await model.playManualSonosQueueItem(at: position) else {
            return
        }

        await model.refreshQueue(showLoading: false)
    }

    private func deleteQueueItems(_ offsets: IndexSet) async {
        _ = await model.removeQueueItems(atOffsets: offsets)
    }

    private func moveQueueItems(_ source: IndexSet, _ destination: Int) async {
        _ = await model.moveQueueItems(fromOffsets: source, toOffset: destination)
    }

    private var queueAutoRefreshLoopKey: String {
        "\(model.selectedTab.rawValue)|\(model.manualSonosHost)"
    }

    private func autoRefreshQueueWhileVisible() async {
        guard model.selectedTab == .queue, model.hasManualSonosHost else {
            return
        }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.autoRefreshInterval)
            } catch {
                return
            }

            guard model.selectedTab == .queue, model.hasManualSonosHost else {
                return
            }

            guard !isEditingQueue, !model.isQueueMutating else {
                continue
            }

            guard model.queueState.snapshot != nil else {
                continue
            }

            await model.refreshQueue(showLoading: false)
        }
    }

    private var isClearQueueDisabled: Bool {
        isQueueInteractionDisabled
            || model.isQueueClearing
            || isEditingQueue
            || model.queueState.snapshot?.items.isEmpty == true
    }

    private var isQueueInteractionDisabled: Bool {
        model.isQueueRefreshing || model.isQueueClearing || model.isQueueMutating
    }

    private var canEditQueue: Bool {
        model.queueState.snapshot?.items.isEmpty == false
    }

    private var isEditingQueue: Bool {
        editMode?.wrappedValue.isEditing == true
    }
}

#Preview {
    NavigationStack {
        QueueView()
            .environment(SonoicModel())
    }
}
