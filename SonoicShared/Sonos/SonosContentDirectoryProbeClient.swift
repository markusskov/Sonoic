import Foundation

struct SonosContentDirectoryProbeClient {
    private struct BrowsePage {
        var entries: [SonosContentDirectoryProbeEntry]
        var numberReturned: Int
        var totalMatches: Int
    }

    private static let objectIDs: [(id: String, title: String)] = [
        ("0", "Root"),
        ("FV:2", "Favorites"),
        ("Q:0", "Queue"),
        ("R:0", "Recent Candidate"),
        ("RP:0", "Recent Played Candidate"),
    ]

    private static let browsePageSize = 40

    private let transport: SonosControlTransport
    private let didlParser = SonosContentDirectoryProbeDIDLParser()

    init(transport: SonosControlTransport = SonosControlTransport()) {
        self.transport = transport
    }

    func fetchProbeSnapshot(host: String) async -> SonosContentDirectoryProbeSnapshot {
        var browses: [SonosContentDirectoryProbeBrowse] = []

        for objectID in Self.objectIDs {
            browses.append(await fetchBrowse(host: host, objectID: objectID.id, title: objectID.title))
        }

        for candidate in recentCandidates(from: browses) {
            guard !browses.contains(where: { $0.objectID == candidate.id }) else {
                continue
            }

            browses.append(await fetchBrowse(host: host, objectID: candidate.id, title: candidate.title))
        }

        return SonosContentDirectoryProbeSnapshot(
            observedAt: .now,
            browses: browses
        )
    }

    private func fetchBrowse(
        host: String,
        objectID: String,
        title: String
    ) async -> SonosContentDirectoryProbeBrowse {
        do {
            let page = try await fetchPage(
                host: host,
                objectID: objectID,
                startingIndex: 0,
                requestedCount: Self.browsePageSize
            )

            return SonosContentDirectoryProbeBrowse(
                objectID: objectID,
                title: title,
                status: page.entries.isEmpty ? .empty : .loaded,
                numberReturned: page.numberReturned,
                totalMatches: page.totalMatches,
                entries: page.entries
            )
        } catch {
            return SonosContentDirectoryProbeBrowse(
                objectID: objectID,
                title: title,
                status: .failed(error.localizedDescription),
                numberReturned: nil,
                totalMatches: nil,
                entries: []
            )
        }
    }

    private func fetchPage(
        host: String,
        objectID: String,
        startingIndex: Int,
        requestedCount: Int
    ) async throws -> BrowsePage {
        let data = try await transport.performAction(
            service: .contentDirectory,
            named: "Browse",
            body: """
            <u:Browse xmlns:u="\(SonosControlTransport.Service.contentDirectory.soapNamespace)">
              <ObjectID>\(objectID.sonoicXMLEscaped)</ObjectID>
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
        let result = try requiredValue(named: "Result", in: values)

        return BrowsePage(
            entries: try didlParser.parse(result),
            numberReturned: try parseCount(try requiredValue(named: "NumberReturned", in: values)),
            totalMatches: try parseCount(try requiredValue(named: "TotalMatches", in: values))
        )
    }

    private func recentCandidates(
        from browses: [SonosContentDirectoryProbeBrowse]
    ) -> [SonosContentDirectoryProbeEntry] {
        browses
            .flatMap(\.entries)
            .filter(\.looksLikeRecentlyPlayedContainer)
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

private final class SonosContentDirectoryProbeDIDLParser: NSObject, XMLParserDelegate {
    private var entries: [SonosContentDirectoryProbeEntry] = []
    private var currentEntry: SonosContentDirectoryProbeEntry?
    private var capturedElementName: String?
    private var capturedValue = ""

    func parse(_ xml: String) throws -> [SonosContentDirectoryProbeEntry] {
        entries = []
        currentEntry = nil
        capturedElementName = nil
        capturedValue = ""

        guard let data = xml.data(using: .utf8) else {
            throw SonosControlTransport.TransportError.invalidResponse
        }

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? SonosControlTransport.TransportError.invalidResponse
        }

        return entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        switch elementName.sonosXMLLocalName {
        case "container":
            currentEntry = SonosContentDirectoryProbeEntry(
                id: attributeDict["id"] ?? "container-\(entries.count)",
                parentID: attributeDict["parentID"]?.sonoicNonEmptyTrimmed,
                kind: .container,
                title: "Untitled",
                itemClass: nil,
                creator: nil,
                album: nil,
                resourceURI: nil,
                albumArtURI: nil
            )
        case "item":
            currentEntry = SonosContentDirectoryProbeEntry(
                id: attributeDict["id"] ?? "item-\(entries.count)",
                parentID: attributeDict["parentID"]?.sonoicNonEmptyTrimmed,
                kind: .item,
                title: "Untitled",
                itemClass: nil,
                creator: nil,
                album: nil,
                resourceURI: nil,
                albumArtURI: nil
            )
        case "res":
            capturedElementName = "res"
            capturedValue = ""
        case "title", "creator", "artist", "album", "class", "albumArtURI":
            guard currentEntry != nil else {
                return
            }

            capturedElementName = elementName.sonosXMLLocalName
            capturedValue = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capturedElementName != nil else {
            return
        }

        capturedValue.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.sonosXMLLocalName

        switch localName {
        case "container", "item":
            if let currentEntry {
                entries.append(currentEntry)
            }
            currentEntry = nil
        default:
            guard let capturedElementName,
                  localName == capturedElementName
            else {
                return
            }

            apply(capturedValue, for: capturedElementName)
            self.capturedElementName = nil
            capturedValue = ""
        }
    }

    private func apply(_ value: String, for elementName: String) {
        guard let trimmedValue = value.sonoicNonEmptyTrimmed else {
            return
        }

        switch elementName {
        case "title":
            currentEntry?.title = trimmedValue
        case "creator", "artist":
            if currentEntry?.creator == nil {
                currentEntry?.creator = trimmedValue
            }
        case "album":
            currentEntry?.album = trimmedValue
        case "class":
            currentEntry?.itemClass = trimmedValue
        case "albumArtURI":
            currentEntry?.albumArtURI = trimmedValue
        case "res":
            currentEntry?.resourceURI = trimmedValue
        default:
            break
        }
    }
}

private extension String {
    var sonoicXMLEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
