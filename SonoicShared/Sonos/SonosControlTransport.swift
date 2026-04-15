import Foundation

struct SonosControlTransport {
    enum Service {
        case renderingControl
        case avTransport

        var soapNamespace: String {
            switch self {
            case .renderingControl:
                "urn:schemas-upnp-org:service:RenderingControl:1"
            case .avTransport:
                "urn:schemas-upnp-org:service:AVTransport:1"
            }
        }

        var controlPath: String {
            switch self {
            case .renderingControl:
                "/MediaRenderer/RenderingControl/Control"
            case .avTransport:
                "/MediaRenderer/AVTransport/Control"
            }
        }
    }

    enum TransportError: LocalizedError {
        case invalidHost
        case invalidResponse
        case httpStatus(Int)
        case missingValue(String)

        var errorDescription: String? {
            switch self {
            case .invalidHost:
                "Enter a valid Sonos player host or IP address."
            case .invalidResponse:
                "The Sonos player returned an unreadable response."
            case let .httpStatus(statusCode):
                "The Sonos player returned HTTP \(statusCode)."
            case let .missingValue(name):
                "The Sonos player did not return \(name)."
            }
        }
    }

    func performAction(service: Service, named actionName: String, body: String, host: String) async throws -> Data {
        let controlURL = try controlURL(for: host, service: service)
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.httpBody = soapEnvelope(containing: body).data(using: .utf8)
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "\"\(service.soapNamespace)#\(actionName)\"",
            forHTTPHeaderField: "SOAPACTION"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransportError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw TransportError.httpStatus(httpResponse.statusCode)
        }

        return data
    }

    func url(for resource: String, host: String) throws -> URL {
        let trimmedResource = resource.trimmingCharacters(in: .whitespacesAndNewlines)

        if let absoluteURL = URL(string: trimmedResource), absoluteURL.scheme != nil {
            return absoluteURL
        }

        guard let resolvedURL = URL(string: trimmedResource, relativeTo: try baseURL(for: host))?.absoluteURL else {
            throw TransportError.invalidHost
        }

        return resolvedURL
    }

    private func controlURL(for host: String, service: Service) throws -> URL {
        let url = try baseURL(for: host)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw TransportError.invalidHost
        }

        components.path = service.controlPath
        components.query = nil
        components.fragment = nil

        guard let controlURL = components.url else {
            throw TransportError.invalidHost
        }

        return controlURL
    }

    private func baseURL(for host: String) throws -> URL {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw TransportError.invalidHost
        }

        let candidate = trimmedHost.contains("://") ? trimmedHost : "http://\(trimmedHost)"
        guard var components = URLComponents(string: candidate), components.host != nil else {
            throw TransportError.invalidHost
        }

        components.scheme = "http"
        components.port = components.port ?? 1400
        components.path = ""
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw TransportError.invalidHost
        }

        return url
    }

    private func soapEnvelope(containing body: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            \(body)
          </s:Body>
        </s:Envelope>
        """
    }
}
