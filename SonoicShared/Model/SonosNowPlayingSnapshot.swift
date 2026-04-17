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

    static let unconfigured = SonosNowPlayingSnapshot(
        title: "No Player Connected",
        artistName: nil,
        albumTitle: nil,
        sourceName: "Open Settings to connect a player",
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
        sourceName != "TV Audio"
    }
}
