import Foundation

struct SonosHTControlClient {
    private let transport: SonosControlTransport

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    func fetchTVDiagnostics(host: String) async -> SonosHomeTheaterTVDiagnostics {
        async let remoteConfigured = fetchOptionalRemoteConfigured(host: host)
        async let irRepeaterState = fetchOptionalIRRepeaterState(host: host)
        async let ledFeedbackState = fetchOptionalLEDFeedbackState(host: host)

        return await SonosHomeTheaterTVDiagnostics(
            remoteConfigured: remoteConfigured,
            irRepeaterState: irRepeaterState,
            ledFeedbackState: ledFeedbackState
        )
    }

    private func fetchOptionalRemoteConfigured(host: String) async -> Bool? {
        do {
            let data = try await transport.performAction(
                service: .htControl,
                named: "IsRemoteConfigured",
                body: """
                <u:IsRemoteConfigured xmlns:u="\(SonosControlTransport.Service.htControl.soapNamespace)">
                </u:IsRemoteConfigured>
                """,
                host: host
            )

            let value = try SonosSOAPValueParser(expectedElement: "RemoteConfigured").parse(data)
            return try parseBool(value)
        } catch {
            return nil
        }
    }

    private func fetchOptionalIRRepeaterState(host: String) async -> String? {
        do {
            let data = try await transport.performAction(
                service: .htControl,
                named: "GetIRRepeaterState",
                body: """
                <u:GetIRRepeaterState xmlns:u="\(SonosControlTransport.Service.htControl.soapNamespace)">
                </u:GetIRRepeaterState>
                """,
                host: host
            )

            return try SonosSOAPValueParser(expectedElement: "CurrentIRRepeaterState").parse(data)
                .sonoicNonEmptyTrimmed
        } catch {
            return nil
        }
    }

    private func fetchOptionalLEDFeedbackState(host: String) async -> String? {
        do {
            let data = try await transport.performAction(
                service: .htControl,
                named: "GetLEDFeedbackState",
                body: """
                <u:GetLEDFeedbackState xmlns:u="\(SonosControlTransport.Service.htControl.soapNamespace)">
                </u:GetLEDFeedbackState>
                """,
                host: host
            )

            return try SonosSOAPValueParser(expectedElement: "LEDFeedbackState").parse(data)
                .sonoicNonEmptyTrimmed
        } catch {
            return nil
        }
    }

    private func parseBool(_ value: String) throws -> Bool {
        switch value {
        case "0":
            return false
        case "1":
            return true
        default:
            throw SonosControlTransport.TransportError.invalidResponse
        }
    }
}
