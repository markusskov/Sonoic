import Foundation

struct SonosNowPlayingSnapshot: Equatable {
    enum PlaybackState: String, Codable, Equatable, Hashable {
        case playing
        case paused
        case buffering

        var title: String {
            switch self {
            case .playing:
                "Playing"
            case .paused:
                "Paused"
            case .buffering:
                "Buffering"
            }
        }

        var systemImage: String {
            switch self {
            case .playing:
                "pause.fill"
            case .paused:
                "play.fill"
            case .buffering:
                "arrow.trianglehead.2.clockwise.rotate.90"
            }
        }

        var controlTitle: String {
            switch self {
            case .playing:
                "Pause"
            case .paused, .buffering:
                "Play"
            }
        }

        var controlSystemImage: String {
            switch self {
            case .playing:
                "pause.fill"
            case .paused, .buffering:
                "play.fill"
            }
        }
    }

    var title: String
    var artistName: String?
    var albumTitle: String?
    var sourceName: String
    var playbackState: PlaybackState
    var artworkURL: String? = nil
    var artworkIdentifier: String? = nil
    var elapsedTime: TimeInterval? = nil
    var duration: TimeInterval? = nil
    var transportActions: SonosTransportActions? = nil

    static let unconfigured = SonosNowPlayingSnapshot(
        title: "No Player Connected",
        artistName: nil,
        albumTitle: nil,
        sourceName: "Open Rooms to choose a player",
        playbackState: .paused
    )

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

    var supportsTrackNavigation: Bool {
        guard let transportActions else {
            return sourceName != "TV Audio"
        }

        return transportActions.canSkipNext || transportActions.canSkipPrevious
    }

    var canPlay: Bool {
        transportActions?.canPlay ?? (playbackState != .playing)
    }

    var canPause: Bool {
        transportActions?.canPause ?? (playbackState == .playing || playbackState == .buffering)
    }

    var canTogglePlayback: Bool {
        canPlay || canPause
    }

    var canSkipNext: Bool {
        transportActions?.canSkipNext ?? supportsTrackNavigation
    }

    var canSkipPrevious: Bool {
        transportActions?.canSkipPrevious ?? supportsTrackNavigation
    }

    var canSeek: Bool {
        transportActions?.canSeek ?? true
    }
}

struct SonosTransportActions: Equatable, Hashable {
    private var normalizedActions: Set<String>

    init(rawActions: Set<String>) {
        normalizedActions = Set(rawActions.compactMap { $0.sonoicNonEmptyTrimmed?.lowercased() })
    }

    init(actionsString: String) {
        let rawActions = actionsString
            .split(separator: ",")
            .map(String.init)
            .compactMap(\.sonoicNonEmptyTrimmed)

        self.init(rawActions: Set(rawActions))
    }

    var canPlay: Bool {
        contains("Play")
    }

    var canPause: Bool {
        contains("Pause")
    }

    var canStop: Bool {
        contains("Stop")
    }

    var canSeek: Bool {
        contains("Seek")
    }

    var canSkipNext: Bool {
        contains("Next")
    }

    var canSkipPrevious: Bool {
        contains("Previous")
    }

    private func contains(_ action: String) -> Bool {
        normalizedActions.contains(action.lowercased())
    }
}

extension String {
    nonisolated var sonoicTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var sonoicNonEmptyTrimmed: String? {
        let trimmedValue = sonoicTrimmed
        guard !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }
}

extension Optional where Wrapped == String {
    nonisolated var sonoicNonEmptyTrimmed: String? {
        self?.sonoicNonEmptyTrimmed
    }
}
