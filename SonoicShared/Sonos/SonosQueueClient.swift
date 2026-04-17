import Foundation

struct SonosQueueClient {
    enum ClientError: LocalizedError {
        case unavailableForCurrentSource

        var errorDescription: String? {
            switch self {
            case .unavailableForCurrentSource:
                "The active source isn't using the Sonos queue right now."
            }
        }
    }

    private struct BrowsePage {
        var items: [SonosQueueItem]
        var numberReturned: Int
        var totalMatches: Int
    }

    private static let browsePageSize = 100

    private let transport: SonosControlTransport
    private let didlParser = SonosQueueDIDLParser()

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    func fetchSnapshot(host: String) async throws -> SonosQueueSnapshot {
        let currentURI = try await fetchCurrentURI(host: host)

        guard SonosMetadataHeuristics.isQueueContainerURI(currentURI) else {
            throw ClientError.unavailableForCurrentSource
        }

        let items = try await fetchQueueItems(host: host)
        let currentTrackNumber = await fetchCurrentTrackNumber(host: host)
        return SonosQueueSnapshot(
            items: items,
            currentItemIndex: resolvedCurrentItemIndex(
                trackNumber: currentTrackNumber,
                itemCount: items.count
            )
        )
    }

    private func fetchQueueItems(host: String) async throws -> [SonosQueueItem] {
        var items: [SonosQueueItem] = []
        var startingIndex = 0
        var totalMatches = 0

        repeat {
            let page = try await fetchQueuePage(
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

        return items
    }

    private func fetchQueuePage(host: String, startingIndex: Int, requestedCount: Int) async throws -> BrowsePage {
        let data = try await transport.performAction(
            service: .contentDirectory,
            named: "Browse",
            body: """
            <u:Browse xmlns:u="\(SonosControlTransport.Service.contentDirectory.soapNamespace)">
              <ObjectID>Q:0</ObjectID>
              <BrowseFlag>BrowseDirectChildren</BrowseFlag>
              <Filter>*</Filter>
              <StartingIndex>\(startingIndex)</StartingIndex>
              <RequestedCount>\(requestedCount)</RequestedCount>
              <SortCriteria></SortCriteria>
            </u:Browse>
            """,
            host: host
        )

        let result = try SonosSOAPValueParser(expectedElement: "Result").parse(data)
        let items = try didlParser.parse(result)

        return BrowsePage(
            items: items,
            numberReturned: try parseCount(
                SonosSOAPValueParser(expectedElement: "NumberReturned").parse(data)
            ),
            totalMatches: try parseCount(
                SonosSOAPValueParser(expectedElement: "TotalMatches").parse(data)
            )
        )
    }

    private func fetchCurrentURI(host: String) async throws -> String? {
        let data = try await transport.performAction(
            service: .avTransport,
            named: "GetMediaInfo",
            body: """
            <u:GetMediaInfo xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:GetMediaInfo>
            """,
            host: host
        )

        return extractOptionalSOAPValue(named: "CurrentURI", from: data)
    }

    private func fetchCurrentTrackNumber(host: String) async -> Int? {
        guard let data = try? await transport.performAction(
            service: .avTransport,
            named: "GetPositionInfo",
            body: """
            <u:GetPositionInfo xmlns:u="\(SonosControlTransport.Service.avTransport.soapNamespace)">
              <InstanceID>0</InstanceID>
            </u:GetPositionInfo>
            """,
            host: host
        ),
        let trackValue = extractOptionalSOAPValue(named: "Track", from: data)
        else {
            return nil
        }

        return Int(trackValue)
    }

    private func resolvedCurrentItemIndex(trackNumber: Int?, itemCount: Int) -> Int? {
        guard let trackNumber, trackNumber > 0 else {
            return nil
        }

        let currentItemIndex = trackNumber - 1
        guard currentItemIndex < itemCount else {
            return nil
        }

        return currentItemIndex
    }

    private func parseCount(_ value: String) throws -> Int {
        guard let count = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SonosControlTransport.TransportError.invalidResponse
        }

        return count
    }

    private func extractOptionalSOAPValue(named elementName: String, from data: Data) -> String? {
        try? SonosSOAPValueParser(expectedElement: elementName).parse(data)
    }
}
