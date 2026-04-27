import Foundation

struct SonosControlTransport {
    struct HTTPPayload {
        var data: Data
        var response: HTTPURLResponse
    }

    enum Service {
        case renderingControl
        case groupRenderingControl
        case avTransport
        case contentDirectory
        case musicServices
        case zoneGroupTopology
        case htControl

        nonisolated var soapNamespace: String {
            switch self {
            case .renderingControl:
                "urn:schemas-upnp-org:service:RenderingControl:1"
            case .groupRenderingControl:
                "urn:schemas-upnp-org:service:GroupRenderingControl:1"
            case .avTransport:
                "urn:schemas-upnp-org:service:AVTransport:1"
            case .contentDirectory:
                "urn:schemas-upnp-org:service:ContentDirectory:1"
            case .musicServices:
                "urn:schemas-upnp-org:service:MusicServices:1"
            case .zoneGroupTopology:
                "urn:schemas-upnp-org:service:ZoneGroupTopology:1"
            case .htControl:
                "urn:schemas-upnp-org:service:HTControl:1"
            }
        }

        nonisolated var controlPath: String {
            switch self {
            case .renderingControl:
                "/MediaRenderer/RenderingControl/Control"
            case .groupRenderingControl:
                "/MediaRenderer/GroupRenderingControl/Control"
            case .avTransport:
                "/MediaRenderer/AVTransport/Control"
            case .contentDirectory:
                "/MediaServer/ContentDirectory/Control"
            case .musicServices:
                "/MusicServices/Control"
            case .zoneGroupTopology:
                "/ZoneGroupTopology/Control"
            case .htControl:
                "/HTControl/Control"
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

    nonisolated func performGET(resource: String, host: String) async throws -> Data {
        let payload = try await performGETWithResponse(resource: resource, host: host)
        return payload.data
    }

    nonisolated func performGETWithResponse(resource: String, host: String) async throws -> HTTPPayload {
        let resourceURL = try url(for: resource, host: host)
        var request = URLRequest(url: resourceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try validate(response)
        return HTTPPayload(data: data, response: httpResponse)
    }

    nonisolated func performAction(service: Service, named actionName: String, body: String, host: String) async throws -> Data {
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
        _ = try validate(response)
        return data
    }

    nonisolated func url(for resource: String, host: String) throws -> URL {
        let trimmedResource = resource.sonoicTrimmed

        if let absoluteURL = URL(string: trimmedResource), absoluteURL.scheme != nil {
            return absoluteURL
        }

        guard let resolvedURL = URL(string: trimmedResource, relativeTo: try baseURL(for: host))?.absoluteURL else {
            throw TransportError.invalidHost
        }

        return resolvedURL
    }

    nonisolated private func controlURL(for host: String, service: Service) throws -> URL {
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

    nonisolated private func validate(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransportError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw TransportError.httpStatus(httpResponse.statusCode)
        }

        return httpResponse
    }

    nonisolated private func baseURL(for host: String) throws -> URL {
        let trimmedHost = host.sonoicTrimmed
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

    nonisolated private func soapEnvelope(containing body: String) -> String {
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
