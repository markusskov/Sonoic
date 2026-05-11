import SwiftUI

extension QueueView {
    var queueAutoRefreshLoopKey: String {
        "\(model.selectedTab.rawValue)|\(model.manualSonosHost)"
    }

    var isClearQueueDisabled: Bool {
        isQueueInteractionDisabled
            || model.isQueueClearing
            || !canEditQueue
            || isEditingQueue
            || model.queueState.snapshot?.items.isEmpty == true
    }

    var isQueueInteractionDisabled: Bool {
        model.isQueueRefreshing || model.isQueueClearing || model.isQueueMutating
    }

    var canEditQueue: Bool {
        guard let snapshot = model.queueState.snapshot else {
            return false
        }

        return snapshot.supportsLocalMutation && !snapshot.items.isEmpty
    }

    var isEditingQueue: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    func loadQueueForCurrentContext() async {
        guard model.hasManualSonosHost else {
            return
        }

        await model.refreshQueue(showLoading: model.queueState.snapshot == nil)
    }

    func playQueueItem(at position: Int) async {
        guard canEditQueue, !isQueueInteractionDisabled else {
            return
        }

        guard await model.playLocalSonosQueueItem(at: position) else {
            return
        }

        await model.refreshQueue(showLoading: false)
    }

    func deleteQueueItems(_ offsets: IndexSet) async {
        guard canEditQueue else {
            return
        }

        _ = await model.removeQueueItems(atOffsets: offsets)
    }

    func moveQueueItems(_ source: IndexSet, _ destination: Int) async {
        guard canEditQueue else {
            return
        }

        _ = await model.moveQueueItems(fromOffsets: source, toOffset: destination)
    }

    func autoRefreshQueueWhileVisible() async {
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

            guard isQueueReadyForAutoRefresh else {
                continue
            }

            await model.refreshQueue(showLoading: false)
        }
    }

    private var isQueueReadyForAutoRefresh: Bool {
        !isEditingQueue
            && !model.isQueueMutating
            && model.queueState.snapshot != nil
    }
}
