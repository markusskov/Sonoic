import Foundation

final class SonosQueueDIDLParser: NSObject, XMLParserDelegate {
    private struct PartialItem {
        var id: String?
        var title: String?
        var artistName: String?
        var albumTitle: String?
        var artworkURL: String?
        var duration: TimeInterval?
        var nestedMetadataXML: String?
    }

    private var items: [PartialItem] = []
    private var currentItem: PartialItem?
    private var currentItemDepth = 0
    private var currentFieldName: String?
    private var capturedValue = ""

    func parse(_ xmlString: String) throws -> [SonosQueueItem] {
        items = []
        currentItem = nil
        currentItemDepth = 0
        currentFieldName = nil
        capturedValue = ""

        guard xmlString.sonoicNonEmptyTrimmed != nil else {
            return []
        }

        let parser = XMLParser(data: Data(xmlString.utf8))
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? SonosControlTransport.TransportError.invalidResponse
        }

        return items.enumerated().map { index, item in
            queueItem(from: item, at: index)
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        let localName = localName(for: qName ?? elementName)

        if localName == "item" {
            if currentItem == nil {
                currentItem = PartialItem(id: attributeDict["id"].sonoicNonEmptyTrimmed)
                currentItemDepth = 1
            } else {
                currentItemDepth += 1
            }
            return
        }

        guard currentItem != nil,
              let fieldName = normalizedFieldName(for: localName)
        else {
            return
        }

        currentFieldName = fieldName
        capturedValue = ""

        if fieldName == "res" {
            currentItem?.duration = SonosDurationParser.parseTimeInterval(from: attributeDict["duration"])
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentFieldName != nil else {
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
        let localName = localName(for: qName ?? elementName)

        if let currentFieldName,
           normalizedFieldName(for: localName) == currentFieldName
        {
            assign(capturedValue, to: currentFieldName)
            self.currentFieldName = nil
        }

        guard localName == "item" else {
            return
        }

        currentItemDepth = max(0, currentItemDepth - 1)

        guard currentItemDepth == 0,
              let currentItem
        else {
            return
        }

        items.append(currentItem)

        resetCurrentItem()
    }

    private func localName(for elementName: String) -> String {
        elementName.sonosXMLLocalName
    }

    private func normalizedFieldName(for elementName: String) -> String? {
        switch elementName {
        case "title", "creator", "artist", "album", "albumArtURI", "res", "resMD":
            return elementName
        default:
            return nil
        }
    }

    private func assign(_ value: String, to fieldName: String) {
        guard let value = value.sonoicNonEmptyTrimmed else {
            return
        }

        switch fieldName {
        case "title":
            if currentItem?.title == nil {
                currentItem?.title = value
            }
        case "creator", "artist":
            if currentItem?.artistName == nil {
                currentItem?.artistName = value
            }
        case "album":
            if currentItem?.albumTitle == nil {
                currentItem?.albumTitle = value
            }
        case "albumArtURI":
            if currentItem?.artworkURL == nil {
                currentItem?.artworkURL = value
            }
        case "resMD":
            if currentItem?.nestedMetadataXML == nil {
                currentItem?.nestedMetadataXML = value
            }
        default:
            break
        }
    }

    private func queueItem(from partialItem: PartialItem, at index: Int) -> SonosQueueItem {
        let nestedMetadata = partialItem.nestedMetadataXML
            .flatMap { try? SonosDIDLMetadataParser().parse($0) }

        return SonosQueueItem(
            id: partialItem.id ?? "queue-item-\(index + 1)",
            title: partialItem.title ?? nestedMetadata?.title ?? "Unknown Track",
            artistName: partialItem.artistName ?? nestedMetadata?.artistName,
            albumTitle: partialItem.albumTitle ?? nestedMetadata?.albumTitle,
            artworkURL: partialItem.artworkURL ?? nestedMetadata?.albumArtURI,
            duration: partialItem.duration
        )
    }

    private func resetCurrentItem() {
        currentItem = nil
        currentItemDepth = 0
        currentFieldName = nil
        capturedValue = ""
    }
}
