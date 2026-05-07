import Foundation

enum SonosPlaybackSourceOwnership: String, Equatable {
    case unavailable
    case sonosQueue
    case serviceContainer
    case directServiceStream
    case groupCoordinator
    case tvAudio
    case lineIn
    case musicLibrary
    case webStream
    case unknown

    init(uri: String?) {
        guard let normalizedURI = uri.sonoicNonEmptyTrimmed?.lowercased() else {
            self = .unavailable
            return
        }

        if normalizedURI.hasPrefix("x-rincon-queue:") {
            self = .sonosQueue
        } else if normalizedURI.hasPrefix("x-rincon-cpcontainer:") {
            self = .serviceContainer
        } else if normalizedURI.hasPrefix("x-rincon:") {
            self = .groupCoordinator
        } else if normalizedURI.hasPrefix("x-sonos-htastream:") {
            self = .tvAudio
        } else if normalizedURI.hasPrefix("x-rincon-stream:") {
            self = .lineIn
        } else if normalizedURI.hasPrefix("x-file-cifs:") {
            self = .musicLibrary
        } else if normalizedURI.hasPrefix("x-sonos-http:")
            || normalizedURI.hasPrefix("x-sonosapi-radio:")
            || normalizedURI.hasPrefix("x-sonosapi-stream:")
            || normalizedURI.hasPrefix("x-sonosapi-hls-static:")
            || normalizedURI.hasPrefix("x-sonosapi-hls:")
            || normalizedURI.hasPrefix("x-sonosapi-http:")
            || normalizedURI.hasPrefix("x-sonosapi-static:")
            || normalizedURI.hasPrefix("x-rincon-mp3radio:")
        {
            self = .directServiceStream
        } else if normalizedURI.hasPrefix("http://") || normalizedURI.hasPrefix("https://") {
            self = .webStream
        } else {
            self = .unknown
        }
    }

    var title: String {
        switch self {
        case .unavailable:
            "Unavailable"
        case .sonosQueue:
            "Sonos Queue"
        case .serviceContainer:
            "Service Container"
        case .directServiceStream:
            "Service Stream"
        case .groupCoordinator:
            "Group Coordinator"
        case .tvAudio:
            "TV Audio"
        case .lineIn:
            "Line-In"
        case .musicLibrary:
            "Music Library"
        case .webStream:
            "Web Stream"
        case .unknown:
            "Unknown"
        }
    }

    var diagnosticDetail: String {
        switch self {
        case .unavailable:
            "No current URI was reported."
        case .sonosQueue:
            "Playback is owned by Q:0."
        case .serviceContainer:
            "Playback came from a service container, not the editable queue."
        case .directServiceStream:
            "Playback came directly from a service stream."
        case .groupCoordinator:
            "URI points at a Sonos group coordinator."
        case .tvAudio:
            "Playback is owned by home theater input."
        case .lineIn:
            "Playback is owned by line-in."
        case .musicLibrary:
            "Playback is owned by local music library."
        case .webStream:
            "Playback is owned by a web stream."
        case .unknown:
            "Sonoic does not recognize this URI family yet."
        }
    }

    var isQueueBacked: Bool {
        self == .sonosQueue
    }

    var supportsLocalQueueMutation: Bool {
        isQueueBacked
    }
}
