import Foundation

struct SonosRenderingControlClient {
    enum ClientError: LocalizedError {
        case invalidVolume(String)
        case invalidMute(String)

        var errorDescription: String? {
            switch self {
            case let .invalidVolume(value):
                "The Sonos player returned an invalid volume value: \(value)."
            case let .invalidMute(value):
                "The Sonos player returned an invalid mute value: \(value)."
            }
        }
    }

    private let transport: SonosControlTransport

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    func fetchVolume(host: String) async throws -> SonoicExternalControlState.Volume {
        async let volumeLevel = fetchVolumeLevel(host: host)
        async let isMuted = fetchMuteState(host: host)
        return try await SonoicExternalControlState.Volume(level: volumeLevel, isMuted: isMuted)
    }

    func setMute(host: String, isMuted: Bool) async throws {
        _ = try await transport.performAction(
            service: .renderingControl,
            named: "SetMute",
            body: """
            <u:SetMute xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
              <DesiredMute>\(isMuted ? "1" : "0")</DesiredMute>
            </u:SetMute>
            """,
            host: host
        )
    }

    private func fetchVolumeLevel(host: String) async throws -> Int {
        let data = try await transport.performAction(
            service: .renderingControl,
            named: "GetVolume",
            body: """
            <u:GetVolume xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
            </u:GetVolume>
            """,
            host: host
        )

        let value = try SonosSOAPValueParser(expectedElement: "CurrentVolume").parse(data)
        guard let level = Int(value), (0...100).contains(level) else {
            throw ClientError.invalidVolume(value)
        }

        return level
    }

    private func fetchMuteState(host: String) async throws -> Bool {
        let data = try await transport.performAction(
            service: .renderingControl,
            named: "GetMute",
            body: """
            <u:GetMute xmlns:u="\(SonosControlTransport.Service.renderingControl.soapNamespace)">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
            </u:GetMute>
            """,
            host: host
        )

        let value = try SonosSOAPValueParser(expectedElement: "CurrentMute").parse(data)

        return switch value {
        case "0":
            false
        case "1":
            true
        default:
            throw ClientError.invalidMute(value)
        }
    }
}
