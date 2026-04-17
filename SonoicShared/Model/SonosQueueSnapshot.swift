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

    var currentItem: SonosQueueItem? {
        guard let currentItemIndex,
              items.indices.contains(currentItemIndex)
        else {
            return nil
        }

        return items[currentItemIndex]
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
}
