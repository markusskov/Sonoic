import Foundation

struct SonosAVTransportClient {
    enum ClientError: LocalizedError {
        case invalidTransportState(String)

        var errorDescription: String? {
            switch self {
            case let .invalidTransportState(value):
                "The Sonos player returned an invalid transport state: \(value)."
            }
        }
    }

    private let transport: SonosControlTransport

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    func fetchPlaybackState(host: String) async throws -> SonosNowPlayingSnapshot.PlaybackState {
        let data = try await transport.performAction(
            service: .avTransport,
            named: "GetTransportInfo",
            body: """
            <u:GetTransportInfo xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:GetTransportInfo>
            """,
            host: host
        )

        let value = try SonosSOAPValueParser(expectedElement: "CurrentTransportState").parse(data)

        return switch value {
        case "PLAYING":
            .playing
        case "PAUSED_PLAYBACK", "STOPPED", "NO_MEDIA_PRESENT":
            .paused
        case "TRANSITIONING":
            .buffering
        default:
            throw ClientError.invalidTransportState(value)
        }
    }

    func play(host: String) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "Play",
            body: """
            <u:Play xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Speed>1</Speed>
            </u:Play>
            """,
            host: host
        )
    }

    func pause(host: String) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "Pause",
            body: """
            <u:Pause xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:Pause>
            """,
            host: host
        )
    }

    func next(host: String) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "Next",
            body: """
            <u:Next xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:Next>
            """,
            host: host
        )
    }

    func previous(host: String) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "Previous",
            body: """
            <u:Previous xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:Previous>
            """,
            host: host
        )
    }

    func seek(host: String, timeInterval: TimeInterval) async throws {
        _ = try await transport.performAction(
            service: .avTransport,
            named: "Seek",
            body: """
            <u:Seek xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Unit>REL_TIME</Unit>
              <Target>\(formattedSeekTarget(for: timeInterval))</Target>
            </u:Seek>
            """,
            host: host
        )
    }

    private func formattedSeekTarget(for timeInterval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(timeInterval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
