import Foundation

struct SonosQueueItem: Identifiable, Equatable {
    let id: String
    var title: String
    var artistName: String?
    var albumTitle: String?
    var artworkURL: String?
    var duration: TimeInterval?

    var subtitle: String? {
        var parts: [String] = []

        if let artistName, !artistName.isEmpty {
            parts.append(artistName)
        }

        if let albumTitle, !albumTitle.isEmpty {
            parts.append(albumTitle)
        }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " • ")
    }

    var durationText: String? {
        guard let duration else {
            return nil
        }

        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SonosQueueSnapshot: Equatable {
    var items: [SonosQueueItem]
    var currentItemIndex: Int?
    var sourceURI: String? = nil

    var currentItem: SonosQueueItem? {
        guard let currentItemIndex,
              items.indices.contains(currentItemIndex)
        else {
            return nil
        }

        return items[currentItemIndex]
    }

    var sourceOwnership: SonosPlaybackSourceOwnership {
        SonosPlaybackSourceOwnership(uri: sourceURI)
    }

    var supportsLocalMutation: Bool {
        sourceOwnership.supportsLocalQueueMutation
    }

    var itemCountText: String {
        if items.count == 1 {
            return "1 item"
        }

        return "\(items.count) items"
    }

    var currentPositionText: String? {
        guard let currentItemIndex,
              items.indices.contains(currentItemIndex)
        else {
            return nil
        }

        return "Track \(currentItemIndex + 1) of \(items.count)"
    }

    func removingItems(atOffsets offsets: IndexSet) -> SonosQueueSnapshot {
        var updatedItems = items
        let previousCurrentItemID = currentItem?.id
        let removedCurrentItem = currentItemIndex.map(offsets.contains) ?? false
        let removedCurrentIndex = currentItemIndex

        for offset in offsets.sorted(by: >) where updatedItems.indices.contains(offset) {
            updatedItems.remove(at: offset)
        }

        let nextCurrentItemIndex = resolvedCurrentItemIndex(
            in: updatedItems,
            previousCurrentItemID: previousCurrentItemID,
            removedCurrentItem: removedCurrentItem,
            removedCurrentIndex: removedCurrentIndex
        )

        return SonosQueueSnapshot(
            items: updatedItems,
            currentItemIndex: nextCurrentItemIndex,
            sourceURI: sourceURI
        )
    }

    func movingItems(fromOffsets source: IndexSet, toOffset destination: Int) -> SonosQueueSnapshot {
        var updatedItems = items
        moveItems(in: &updatedItems, fromOffsets: source, toOffset: destination)

        let nextCurrentItemIndex = resolvedCurrentItemIndex(
            in: updatedItems,
            previousCurrentItemID: currentItem?.id,
            removedCurrentItem: false,
            removedCurrentIndex: currentItemIndex
        )

        return SonosQueueSnapshot(
            items: updatedItems,
            currentItemIndex: nextCurrentItemIndex,
            sourceURI: sourceURI
        )
    }

    private func resolvedCurrentItemIndex(
        in updatedItems: [SonosQueueItem],
        previousCurrentItemID: String?,
        removedCurrentItem: Bool,
        removedCurrentIndex: Int?
    ) -> Int? {
        if let previousCurrentItemID,
           let movedCurrentIndex = updatedItems.firstIndex(where: { $0.id == previousCurrentItemID })
        {
            return movedCurrentIndex
        }

        guard removedCurrentItem,
              let removedCurrentIndex,
              !updatedItems.isEmpty
        else {
            return nil
        }

        return min(removedCurrentIndex, updatedItems.count - 1)
    }

    private func moveItems(
        in items: inout [SonosQueueItem],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        let sourceOffsets = source.sorted()
        guard !sourceOffsets.isEmpty else {
            return
        }

        let movedItems = sourceOffsets.compactMap { offset in
            items.indices.contains(offset) ? items[offset] : nil
        }

        for offset in sourceOffsets.reversed() where items.indices.contains(offset) {
            items.remove(at: offset)
        }

        let removedBeforeDestinationCount = sourceOffsets.reduce(into: 0) { count, offset in
            if offset < destination {
                count += 1
            }
        }
        let insertionIndex = max(0, min(destination - removedBeforeDestinationCount, items.count))
        items.insert(contentsOf: movedItems, at: insertionIndex)
    }
}
