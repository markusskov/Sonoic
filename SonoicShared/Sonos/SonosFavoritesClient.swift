import Foundation

struct SonosFavoritesClient {
    private struct BrowsePage {
        var items: [SonosFavoriteItem]
        var numberReturned: Int
        var totalMatches: Int
    }

    private static let favoritesObjectID = "FV:2"
    private static let browsePageSize = 100

    private let transport: SonosControlTransport
    private let didlParser = SonosFavoritesDIDLParser()

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    @discardableResult
    func addFavorite(host: String, payload: SonosPlayablePayload) async throws -> String {
        let preparedPayload = try SonosPlayablePayloadPreparer().prepare(payload)
        let data = try await transport.performAction(
            service: .contentDirectory,
            named: "CreateObject",
            body: """
            <u:CreateObject xmlns:u="\(SonosControlTransport.Service.contentDirectory.soapNamespace)">
              <ContainerID>\(Self.favoritesObjectID)</ContainerID>
              <Elements>\(favoriteDIDL(for: preparedPayload).sonoicFavoritesXMLEscaped)</Elements>
            </u:CreateObject>
            """,
            host: host
        )

        let values = try SonosSOAPValuesParser(
            expectedElements: ["ObjectID", "Result"]
        ).parse(data)
        return try requiredValue(named: "ObjectID", in: values)
    }

    func removeFavorite(host: String, objectID: String) async throws {
        _ = try await transport.performAction(
            service: .contentDirectory,
            named: "DestroyObject",
            body: """
            <u:DestroyObject xmlns:u="\(SonosControlTransport.Service.contentDirectory.soapNamespace)">
              <ObjectID>\(objectID.sonoicFavoritesXMLEscaped)</ObjectID>
            </u:DestroyObject>
            """,
            host: host
        )
    }

    func fetchSnapshot(host: String) async throws -> SonosFavoritesSnapshot {
        var items: [SonosFavoriteItem] = []
        var startingIndex = 0
        var totalMatches = 0

        repeat {
            let page = try await fetchPage(
                host: host,
                startingIndex: startingIndex,
                requestedCount: Self.browsePageSize
            )
            items.append(contentsOf: page.items)
            totalMatches = page.totalMatches

            guard page.numberReturned > 0 else {
                break
            }

            startingIndex += page.numberReturned
        } while startingIndex < totalMatches

        return SonosFavoritesSnapshot(items: items)
    }

    private func fetchPage(host: String, startingIndex: Int, requestedCount: Int) async throws -> BrowsePage {
        let data = try await transport.performAction(
            service: .contentDirectory,
            named: "Browse",
            body: """
            <u:Browse xmlns:u="\(SonosControlTransport.Service.contentDirectory.soapNamespace)">
              <ObjectID>\(Self.favoritesObjectID)</ObjectID>
              <BrowseFlag>BrowseDirectChildren</BrowseFlag>
              <Filter>*</Filter>
              <StartingIndex>\(startingIndex)</StartingIndex>
              <RequestedCount>\(requestedCount)</RequestedCount>
              <SortCriteria></SortCriteria>
            </u:Browse>
            """,
            host: host
        )

        let values = try SonosSOAPValuesParser(
            expectedElements: ["Result", "NumberReturned", "TotalMatches"]
        ).parse(data)
        let items = try resolvedItems(
            from: requiredValue(named: "Result", in: values),
            host: host
        )

        return BrowsePage(
            items: items,
            numberReturned: try parseCount(
                try requiredValue(named: "NumberReturned", in: values)
            ),
            totalMatches: try parseCount(
                try requiredValue(named: "TotalMatches", in: values)
            )
        )
    }

    private func resolvedItems(from xml: String, host: String) throws -> [SonosFavoriteItem] {
        try didlParser.parse(xml).map { item in
            var item = item
            if let artworkURL = item.artworkURL,
               let resolvedArtworkURL = try? transport.url(for: artworkURL, host: host)
            {
                item.artworkURL = resolvedArtworkURL.absoluteString
            }

            if item.service == .genericStreaming {
                item.service = nil
            }

            return item
        }
    }

    private func parseCount(_ value: String) throws -> Int {
        guard let trimmedValue = value.sonoicNonEmptyTrimmed,
              let count = Int(trimmedValue)
        else {
            throw SonosControlTransport.TransportError.invalidResponse
        }

        return count
    }

    private func requiredValue(named elementName: String, in values: [String: String]) throws -> String {
        guard let value = values[elementName] else {
            throw SonosControlTransport.TransportError.missingValue(elementName)
        }

        return value
    }

    private func favoriteDIDL(for payload: SonosPlayablePayload) -> String {
        """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"><item id="" parentID="\(Self.favoritesObjectID)" restricted="true"><dc:title>\(payload.title.sonoicFavoritesXMLEscaped)</dc:title>\(optionalElement("r:description", payload.service?.name))\(optionalElement("upnp:albumArtURI", payload.artworkURL))<upnp:class>object.itemobject.item.sonos-favorite</upnp:class><res protocolInfo="\(protocolInfo(for: payload.uri).sonoicFavoritesXMLEscaped)">\(payload.uri.sonoicFavoritesXMLEscaped)</res>\(optionalElement("r:resMD", payload.metadataXML))</item></DIDL-Lite>
        """
    }

    private func optionalElement(_ name: String, _ value: String?) -> String {
        guard let value = value?.sonoicNonEmptyTrimmed else {
            return ""
        }

        return "<\(name)>\(value.sonoicFavoritesXMLEscaped)</\(name)>"
    }

    private func protocolInfo(for uri: String) -> String {
        if uri.hasPrefix("x-rincon-cpcontainer:") {
            return "x-rincon-cpcontainer:*:*:*"
        }

        if uri.hasPrefix("x-sonosapi-hls:") {
            return "sonos.com-http:*:application/vnd.apple.mpegurl:*"
        }

        if uri.hasPrefix("x-sonosapi-") {
            return "sonos.com-http:*:audio/mp4:*"
        }

        return "*:*:*:*"
    }
}

private extension String {
    var sonoicFavoritesXMLEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
