import Foundation

struct SonoicExternalControlState: Codable, Equatable, Hashable {
    struct WidgetPresentation: Equatable, Hashable {
        var activeTarget: ActiveTarget
        var nowPlaying: NowPlaying
        var playbackState: SonosNowPlayingSnapshot.PlaybackState
        var volume: Volume
        var availability: Availability
    }

    struct Freshness: Equatable, Hashable {
        var isStale: Bool

        var title: String {
            isStale ? "Stale" : "Updated"
        }

        var systemImage: String {
            isStale ? "exclamationmark.triangle.fill" : "clock"
        }
    }

    struct ActiveTarget: Codable, Equatable, Hashable {
        enum Kind: String, Codable, Equatable, Hashable {
            case room
            case group

            var systemImage: String {
                switch self {
                case .room:
                    "speaker.wave.2.fill"
                case .group:
                    "square.stack.3d.up.fill"
                }
            }
        }

        var id: String
        var name: String
        var kind: Kind
    }

    struct NowPlaying: Codable, Equatable, Hashable {
        var title: String
        var artistName: String?
        var subtitle: String?
        var sourceName: String
        var artworkIdentifier: String?
    }

    struct Progress: Codable, Equatable, Hashable {
        var elapsedSeconds: Int
        var durationSeconds: Int

        var fractionComplete: Double {
            guard durationSeconds > 0 else {
                return 0
            }

            return min(max(Double(elapsedSeconds) / Double(durationSeconds), 0), 1)
        }

        var elapsedText: String {
            formatTime(elapsedSeconds)
        }

        var durationText: String {
            formatTime(durationSeconds)
        }

        private func formatTime(_ totalSeconds: Int) -> String {
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60

            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                return String(format: "%d:%02d", minutes, seconds)
            }
        }
    }

    struct Volume: Codable, Equatable, Hashable {
        var level: Int
        var isMuted: Bool

        var labelText: String {
            isMuted ? "Muted" : "\(level)%"
        }

        var systemImage: String {
            isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        }
    }

    enum Availability: String, Codable, Equatable, Hashable {
        case ready
        case connecting
        case stale
        case unavailable

        var title: String {
            switch self {
            case .ready:
                "Connected"
            case .connecting:
                "Connecting"
            case .stale:
                "Stale"
            case .unavailable:
                "Unavailable"
            }
        }

        var systemImage: String {
            switch self {
            case .ready:
                "checkmark.circle.fill"
            case .connecting:
                "dot.radiowaves.left.and.right"
            case .stale:
                "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
            case .unavailable:
                "wifi.slash"
            }
        }
    }

    var activeTarget: ActiveTarget
    var nowPlaying: NowPlaying
    var playbackState: SonosNowPlayingSnapshot.PlaybackState
    var progress: Progress?
    var volume: Volume
    var availability: Availability
    var updatedAt: Date
}

extension SonoicExternalControlState {
    init(
        activeTarget: ActiveTarget,
        nowPlayingSnapshot: SonosNowPlayingSnapshot,
        volume: Volume,
        availability: Availability,
        updatedAt: Date
    ) {
        self.init(
            activeTarget: activeTarget,
            nowPlaying: .init(
                title: nowPlayingSnapshot.title,
                artistName: nowPlayingSnapshot.artistName,
                subtitle: nowPlayingSnapshot.subtitle,
                sourceName: nowPlayingSnapshot.sourceName,
                artworkIdentifier: nowPlayingSnapshot.artworkIdentifier
            ),
            playbackState: nowPlayingSnapshot.playbackState,
            progress: .init(nowPlayingSnapshot: nowPlayingSnapshot),
            volume: volume,
            availability: availability,
            updatedAt: updatedAt
        )
    }

    static let staleInterval: TimeInterval = 2 * 60

    static let unconfigured = SonoicExternalControlState(
        activeTarget: .init(
            id: "unconfigured-room",
            name: "No Room Loaded",
            kind: .room
        ),
        nowPlaying: .init(
            title: "No Player Connected",
            artistName: nil,
            subtitle: nil,
            sourceName: "Open Rooms to choose a player",
            artworkIdentifier: nil
        ),
        playbackState: .paused,
        progress: nil,
        volume: .init(level: 0, isMuted: false),
        availability: .unavailable,
        updatedAt: .now
    )

    static let preview = SonoicExternalControlState(
        activeTarget: .init(
            id: "living-room",
            name: "Living Room",
            kind: .room
        ),
        nowPlaying: .init(
            title: "Unwritten",
            artistName: "Natasha Bedingfield",
            subtitle: "Natasha Bedingfield • Unwritten",
            sourceName: "Apple Music",
            artworkIdentifier: nil
        ),
        playbackState: .playing,
        progress: .init(elapsedSeconds: 52, durationSeconds: 201),
        volume: .init(level: 24, isMuted: false),
        availability: .ready,
        updatedAt: .now
    )

    var staleDate: Date {
        updatedAt.addingTimeInterval(Self.staleInterval)
    }

    func isStale(relativeTo referenceDate: Date) -> Bool {
        referenceDate >= staleDate
    }

    func freshness(relativeTo referenceDate: Date) -> Freshness {
        Freshness(isStale: isStale(relativeTo: referenceDate))
    }

    func freshness(isStale: Bool) -> Freshness {
        Freshness(isStale: isStale)
    }
    
    var widgetPresentation: WidgetPresentation {
        WidgetPresentation(
            activeTarget: activeTarget,
            nowPlaying: nowPlaying,
            playbackState: playbackState,
            volume: volume,
            availability: availability
        )
    }
}

private extension SonoicExternalControlState.Progress {
    init?(nowPlayingSnapshot: SonosNowPlayingSnapshot) {
        guard let elapsedTime = nowPlayingSnapshot.elapsedTime,
              let duration = nowPlayingSnapshot.duration
        else {
            return nil
        }

        let elapsedSeconds = max(0, Int(elapsedTime.rounded()))
        let durationSeconds = max(0, Int(duration.rounded()))
        guard durationSeconds > 0 else {
            return nil
        }

        self.init(elapsedSeconds: elapsedSeconds, durationSeconds: durationSeconds)
    }
}
