import SwiftUI

struct QueueView: View {
    @Environment(\.editMode) var editMode
    @Environment(SonoicModel.self) var model
    @State private var isClearQueueConfirmationPresented = false
    static let autoRefreshInterval: Duration = .seconds(8)

    var body: some View {
        QueueContentView(
            model: model,
            playQueueItem: playQueueItem,
            deleteQueueItems: deleteQueueItems,
            moveQueueItems: moveQueueItems
        )
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
}

#Preview {
    NavigationStack {
        QueueView()
            .environment(SonoicModel())
    }
}
