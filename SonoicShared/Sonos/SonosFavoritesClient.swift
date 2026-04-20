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
}
