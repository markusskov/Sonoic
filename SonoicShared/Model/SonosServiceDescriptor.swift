import Foundation

struct SonosServiceDescriptor: Identifiable, Codable, Equatable, Hashable {
    enum Kind: String, Codable, Equatable, Hashable {
        case appleMusic
        case spotify
        case sonosRadio
        case genericStreaming
    }

    var kind: Kind
    var id: String
    var name: String
    var systemImage: String

    static let appleMusic = SonosServiceDescriptor(
        kind: .appleMusic,
        id: "apple-music",
        name: "Apple Music",
        systemImage: "music.note"
    )
    static let spotify = SonosServiceDescriptor(
        kind: .spotify,
        id: "spotify",
        name: "Spotify",
        systemImage: "waveform.circle.fill"
    )
    static let sonosRadio = SonosServiceDescriptor(
        kind: .sonosRadio,
        id: "sonos-radio",
        name: "Sonos Radio",
        systemImage: "dot.radiowaves.left.and.right"
    )
    static let genericStreaming = SonosServiceDescriptor(
        kind: .genericStreaming,
        id: "streaming-audio",
        name: "Streaming Audio",
        systemImage: "antenna.radiowaves.left.and.right"
    )
}
